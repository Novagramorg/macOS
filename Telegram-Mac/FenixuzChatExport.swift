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

                if format == .html || format == .both {
                    let html = buildHTML(payload: payload)
                    let url = folder.appendingPathComponent("messages.html")
                    guard let data = html.data(using: .utf8) else {
                        throw ChatExportError.writeFailed("HTML encoding failed")
                    }
                    try data.write(to: url)
                    written.append(url)
                }

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

    /// Human-readable destination, shown in the settings sheet.
    static var destinationDescription: String {
        return "Downloads/Novagram Desktop"
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

    // MARK: - HTML

    /// Emits a single self-contained `messages.html`. The class names follow the
    /// official export so the markup reads the same, but the stylesheet is ours and
    /// is inlined — no `css/`, `js/` or `images/` folder to ship. Media stages will
    /// add the asset folders when there is actually something to link to.
    private static func buildHTML(payload: Payload) -> String {
        var rows: [String] = []
        var previousSender: String?

        for message in payload.messages {
            let senderKey = message.author.map { peerIdString($0.id) } ?? "service"
            let isJoined = senderKey == previousSender
            previousSender = senderKey
            rows.append(htmlRow(for: message, joined: isJoined))
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>\(escape(payload.chatTitle))</title>
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        <div class="page_wrap">
        <div class="page_header"><div class="text bold">\(escape(payload.chatTitle))</div></div>
        <div class="history">
        \(rows.joined(separator: "\n"))
        </div>
        </div>
        </body>
        </html>
        """
    }

    private static func htmlRow(for message: Message, joined: Bool) -> String {
        let isService = message.media.contains(where: { $0 is TelegramMediaAction })
        let time = timeOnly(message.timestamp)
        let fullDate = isoDate(message.timestamp)

        if isService {
            return #"<div class="message service" id="message\#(message.id.id)"><div class="body details">\#(escape(message.text))</div></div>"#
        }

        let name = message.author?.displayTitle ?? ""
        var head = ""
        if !joined {
            let initials = escape(String(name.prefix(2)).uppercased())
            let bucket = (abs(name.hashValue) % 8) + 1
            head = #"<div class="pull_left userpic_wrap"><div class="userpic userpic\#(bucket)"><div class="initials">\#(initials)</div></div></div>"#
        }

        var body = #"<div class="pull_right date details" title="\#(escape(fullDate))">\#(escape(time))</div>"#
        if !joined, !name.isEmpty {
            body += #"<div class="from_name">\#(escape(name))</div>"#
        }
        if let reply = message.attributes.compactMap({ $0 as? ReplyMessageAttribute }).first {
            body += #"<div class="reply_to details">In reply to message \#(reply.messageId.id)</div>"#
        }
        if !message.text.isEmpty {
            body += #"<div class="text">\#(escapeMultiline(message.text))</div>"#
        }

        let classes = joined ? "message default clearfix joined" : "message default clearfix"
        return #"<div class="\#(classes)" id="message\#(message.id.id)">\#(head)<div class="body">\#(body)</div></div>"#
    }

    private static let stylesheet = """
    body { margin: 0; padding: 0; background: #0f1620; color: #e6ebf1;
           font: 14px/1.45 -apple-system, "SF Pro Text", Helvetica, Arial, sans-serif; }
    .page_wrap { max-width: 720px; margin: 0 auto; padding: 24px 16px 48px; }
    .page_header { padding: 12px 0 20px; font-size: 20px; }
    .bold { font-weight: 600; }
    .details { color: #7d8b99; font-size: 12px; }
    .clearfix::after { content: ""; display: table; clear: both; }
    .pull_left { float: left; }
    .pull_right { float: right; }
    .message { padding: 8px 12px; margin-bottom: 4px; border-radius: 12px; background: #17212b; }
    .message.joined { margin-top: -2px; }
    .message.service { background: none; text-align: center; padding: 10px 0; }
    .message.service .body { display: inline-block; background: #17212b;
                             border-radius: 12px; padding: 4px 12px; }
    .userpic_wrap { margin-right: 10px; }
    .userpic { width: 36px; height: 36px; border-radius: 50%; display: flex;
               align-items: center; justify-content: center; }
    .initials { font-size: 13px; font-weight: 600; color: #fff; }
    .userpic1 { background: #e17076; } .userpic2 { background: #7bc862; }
    .userpic3 { background: #e5ca77; } .userpic4 { background: #65aadd; }
    .userpic5 { background: #a695e7; } .userpic6 { background: #ee7aae; }
    .userpic7 { background: #6ec9cb; } .userpic8 { background: #faa774; }
    .from_name { color: #6ab3f3; font-weight: 600; margin-bottom: 2px; }
    .reply_to { border-left: 2px solid #6ab3f3; padding-left: 8px; margin: 4px 0; }
    .text { white-space: pre-wrap; word-wrap: break-word; }
    .date { margin-left: 10px; }
    """

    private static func timeOnly(_ timestamp: Int32) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func escape(_ value: String) -> String {
        var out = value
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out
    }

    /// `.text` keeps newlines via `white-space: pre-wrap`, so only the entities escape.
    private static func escapeMultiline(_ value: String) -> String {
        return escape(value)
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
