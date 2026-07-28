//
//  FenixuzChatExport.swift
//  Telegram
//
//  Novagram: export a chat's history to disk.
//
//  Stage 1 — JSON, text only. The output matches the official client's
//  `result.json` schema (see EXPORT_PLAN.md), so files produced here can be read
//  by anything that already parses a Telegram export.
//
//  Media download, the HTML writer and progress/cancel come in later stages; the
//  format enum and the folder layout are already shaped for them.
//

import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit

enum ChatExportFormat: Equatable {
    case json
    case html
    case both
}

enum ChatExportError: Error {
    case noMessages
    case writeFailed(String)
}

struct ChatExportResult {
    let folder: URL
    let fileCount: Int
    let totalSize: Int64
    let messageCount: Int
}

final class FenixuzChatExport {

    // MARK: - Public entry point

    /// Reads the whole local history for `peerId` and writes it to disk.
    /// Runs the postbox read on a background queue; the returned signal fires on main.
    static func export(context: AccountContext, peerId: PeerId, format: ChatExportFormat = .json) -> Signal<ChatExportResult, ChatExportError> {
        return collectMessages(context: context, peerId: peerId)
        |> mapToSignal { payload -> Signal<ChatExportResult, ChatExportError> in
            guard !payload.messages.isEmpty else {
                return .fail(.noMessages)
            }
            return write(payload: payload, format: format)
        }
        |> deliverOnMainQueue
    }

    // MARK: - Collect

    private struct Payload {
        let chatTitle: String
        let chatType: String
        let chatId: Int64
        let messages: [Message]
        let accountPeerId: PeerId
    }

    private static func collectMessages(context: AccountContext, peerId: PeerId) -> Signal<Payload, ChatExportError> {
        let accountPeerId = context.peerId
        return context.account.postbox.transaction { transaction -> Payload in
            let peer = transaction.getPeer(peerId)

            var collected: [Message] = []
            // withAllMessages walks every locally stored message for this peer — no
            // paging needed. (scanMessages is NOT the right call here: it walks a tag
            // index, so an empty tag matches nothing rather than everything.)
            transaction.withAllMessages(peerId: peerId, namespace: Namespaces.Message.Cloud) { message in
                collected.append(message)
                return true
            }
            // scan order is newest-first; exports read oldest-first
            collected.sort(by: { $0.timestamp < $1.timestamp })

            return Payload(
                chatTitle: peer?.displayTitle ?? "",
                chatType: chatType(for: peer),
                chatId: peerId.id._internalGetInt64Value(),
                messages: collected,
                accountPeerId: accountPeerId
            )
        }
        |> castError(ChatExportError.self)
    }

    private static func chatType(for peer: Peer?) -> String {
        guard let peer = peer else {
            return "unknown"
        }
        if peer is TelegramUser {
            return "personal_chat"
        }
        if let channel = peer as? TelegramChannel {
            switch channel.info {
            case .broadcast:
                return "public_channel"
            case .group:
                return "public_supergroup"
            }
        }
        if peer is TelegramGroup {
            return "private_group"
        }
        return "unknown"
    }

    // MARK: - Write

    private static func write(payload: Payload, format: ChatExportFormat) -> Signal<ChatExportResult, ChatExportError> {
        return Signal { subscriber in
            do {
                let folder = try makeExportFolder()
                var written: [URL] = []

                if format == .json || format == .both {
                    let data = try buildJSON(payload: payload)
                    let url = folder.appendingPathComponent("result.json")
                    try data.write(to: url)
                    written.append(url)
                }

                // stage 2 adds the HTML writer here

                let totalSize = written.reduce(Int64(0)) { sum, url in
                    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                    return sum + ((attributes?[.size] as? Int64) ?? 0)
                }

                subscriber.putNext(ChatExportResult(
                    folder: folder,
                    fileCount: written.count,
                    totalSize: totalSize,
                    messageCount: payload.messages.count
                ))
                subscriber.putCompletion()
            } catch let error as ChatExportError {
                subscriber.putError(error)
            } catch {
                subscriber.putError(.writeFailed(error.localizedDescription))
            }
            return EmptyDisposable
        }
        |> runOn(.concurrentDefaultQueue())
    }

    /// `~/Downloads/Novagram Desktop/ChatExport_<yyyy-MM-dd>/`, suffixed when it exists.
    private static func makeExportFolder() throws -> URL {
        let fm = FileManager.default
        guard let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw ChatExportError.writeFailed("Downloads folder unavailable")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let base = downloads
            .appendingPathComponent("Novagram Desktop")
            .appendingPathComponent("ChatExport_\(formatter.string(from: Date()))")

        var candidate = base
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = URL(fileURLWithPath: base.path + " (\(suffix))")
            suffix += 1
        }
        try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
        return candidate
    }

    // MARK: - JSON

    private static func buildJSON(payload: Payload) throws -> Data {
        var root: [String: Any] = [
            "name": payload.chatTitle,
            "type": payload.chatType,
            "id": payload.chatId
        ]
        root["messages"] = payload.messages.map { serialize(message: $0, accountPeerId: payload.accountPeerId) }

        do {
            return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw ChatExportError.writeFailed("JSON encoding failed: \(error.localizedDescription)")
        }
    }

    private static func serialize(message: Message, accountPeerId: PeerId) -> [String: Any] {
        var item: [String: Any] = [
            "id": Int(message.id.id),
            "type": message.media.contains(where: { $0 is TelegramMediaAction }) ? "service" : "message",
            "date": isoDate(message.timestamp),
            "date_unixtime": "\(message.timestamp)",
            "text": message.text,
            // stage 2 fills this with the structured runs; the key is always present
            // so downstream readers can rely on it
            "text_entities": [] as [Any]
        ]

        if let author = message.author {
            item["from"] = author.displayTitle
            item["from_id"] = peerIdString(author.id)
        }

        for attribute in message.attributes {
            if let reply = attribute as? ReplyMessageAttribute {
                item["reply_to_message_id"] = Int(reply.messageId.id)
            }
            if let edited = attribute as? EditedMessageAttribute, !edited.isHidden {
                item["edited"] = isoDate(edited.date)
                item["edited_unixtime"] = "\(edited.date)"
            }
        }

        if let forward = message.forwardInfo {
            if let source = forward.author {
                item["forwarded_from"] = source.displayTitle
                item["forwarded_from_id"] = peerIdString(source.id)
            } else if let signature = forward.authorSignature {
                item["forwarded_from"] = signature
            }
        }

        return item
    }

    /// Matches the official export: local time, no timezone marker.
    private static func isoDate(_ timestamp: Int32) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    /// The official export prefixes ids by kind — `user123`, `channel456`.
    private static func peerIdString(_ peerId: PeerId) -> String {
        let raw = peerId.id._internalGetInt64Value()
        switch peerId.namespace {
        case Namespaces.Peer.CloudUser:
            return "user\(raw)"
        case Namespaces.Peer.CloudChannel:
            return "channel\(raw)"
        case Namespaces.Peer.CloudGroup:
            return "chat\(raw)"
        default:
            return "\(raw)"
        }
    }
}
