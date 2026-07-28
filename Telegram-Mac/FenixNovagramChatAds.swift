//
//  FenixNovagramChatAds.swift
//  Telegram-Mac
//
//  Port of iOS submodules/Fenixuz/NovagramAds/Sources/FenixNovagramAds/FenixNovagramChatAds.swift.
//  Telegram gates its own sponsored messages to the official api_id, so the channel
//  sponsored slot is always empty on this fork. Instead we fetch an ad from OUR backend
//  (ads-api.vipads.uz, via the shared NovagramAds SPM SDK) for the channel being viewed
//  and render it as a synthetic sponsored `Message` in the exact same slot.
//
//  Mac differences vs iOS:
//   - The chat ad source on Mac is `(fixed: Message?, opportunistic: [Message], version: Int)`
//     (see ChatController.swift `ChatAdData.allMessages`), not the iOS 4-tuple. `withInjectedAd`
//     wraps that source and sets `fixed` to our ad.
//   - App Store gate is the compile-time `#if APP_STORE` flag (iOS uses the runtime
//     `GlobalExperimentalSettings.isAppStoreBuild`).
//   - `AccountContext` is an in-target class here, so it is referenced without an import.
//
//  Hooks (ChatController.swift):
//   - `adMessages` source (~2919): `FenixNovagramChatAds.withInjectedAd(base:context:peerId:)`.
//   - `markAdAction` closure (~6365): `FenixNovagramChatAds.reportClickIfOurs(opaqueId:context:)`.
//

import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import NovagramAds

enum FenixNovagramChatAds {
    typealias AdState = (fixed: Message?, opportunistic: [Message], version: Int)

    // Ad serving authenticates with the X-API-Key — never the user JWT (that is
    // admin-panel only) — since NovagramAds 2.1.0. No token store; mirrors iOS
    // FenixNovagramChatAds so both clients send the same key.
    private static let client = SDKClient(
        configuration: SDKConfiguration(apiKey: FenixNovagramAdsConfig.apiKey)
    )

    /// Wrap the chat-history ad source so OUR channel ad fills the sponsored slot.
    /// Off-gate or non-channel → the base source is returned untouched.
    static func withInjectedAd(_ base: Signal<AdState, NoError>, context: AccountContext, peerId: PeerId) -> Signal<AdState, NoError> {
        guard FenixuzAdsGate.showAds, peerId.namespace == Namespaces.Peer.CloudChannel else {
            return base
        }
        // Emit nil first so `base` (and the whole chat-history transition it feeds) renders
        // immediately — the real ad arrives once our backend answers, never blocking the chat.
        let ourAd: Signal<Message?, NoError> = .single(nil) |> then(chatAdMessage(context: context, peerId: peerId))
        return combineLatest(base, ourAd)
        |> map { base, ourAd -> AdState in
            guard let ourAd = ourAd else {
                return base
            }
            return (fixed: ourAd, opportunistic: base.opportunistic, version: base.version &+ 1)
        }
    }

    /// Report a tap on one of our sponsored messages, if it is ours. Returns `true` when the
    /// tap was ours (and must NOT fall through to Telegram's `markAction`, which would POST
    /// our synthetic opaqueId to Telegram's ad server). The opaqueId we encode is
    /// `novagram:<orderId>`; anything else is a Telegram-origin ad we don't own.
    @discardableResult
    static func reportClickIfOurs(opaqueId: Data, context: AccountContext) -> Bool {
        guard let decoded = String(data: opaqueId, encoding: .utf8), decoded.hasPrefix("novagram:") else {
            return false
        }
        let orderIdString = String(decoded.dropFirst("novagram:".count))
        guard let orderId = UUID(uuidString: orderIdString) else {
            return false
        }
        let viewerId = self.viewerId(context: context)
        Task {
            _ = try? await client.chatAds.click(orderId: orderId, viewerId: viewerId)
        }
        return true
    }

    // MARK: - Our ad as a synthetic sponsored Message

    private static func chatAdMessage(context: AccountContext, peerId: PeerId) -> Signal<Message?, NoError> {
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> mapToSignal { peer -> Signal<Message?, NoError> in
            guard let peer = peer, case let .channel(channel) = peer, case .broadcast = channel.info else {
                return .single(nil)
            }
            // Which channel to ask the backend for an ad. App Store builds use the channel's
            // own username. Dev/test builds force the one channel that currently has an active
            // order ("Kunuz") so the slot is visible in ANY opened channel while testing the
            // fetch/render/click pipeline. TEMPORARY — remove the #else once real per-channel
            // orders exist and the backend matches usernames (case-insensitive).
            let channelName: String
            #if APP_STORE
            guard let addressName = channel.addressName, !addressName.isEmpty else {
                return .single(nil)
            }
            // The backend matches channel_name case-sensitively and stores usernames
            // lowercased, while Telegram returns the canonical case (e.g. "Kunuz").
            channelName = addressName.lowercased()
            #else
            channelName = "kunuz"
            #endif
            let authorPeer = peer._asPeer()
            let viewerId = self.viewerId(context: context)
            return fetchAd(channelName: channelName, viewerId: viewerId)
            |> map { ad -> Message? in
                guard let ad = ad else {
                    return nil
                }
                return makeMessage(ad: ad, peerId: peerId, channelPeer: authorPeer)
            }
        }
    }

    // MARK: - viewer id

    // Real Telegram user id in App Store builds; a throwaway random id in every dev/test
    // build (the backend caps each order to a few views per viewer, so a real id would show
    // the ad a few times then never again while testing).
    private static func viewerId(context: AccountContext) -> String {
        #if APP_STORE
        return "\(context.account.peerId.id._internalGetInt64Value())"
        #else
        return "test-\(Int64.random(in: 100_000_000 ... 999_999_999))"
        #endif
    }

    // MARK: - Fetch (async -> Signal). 404 / any error -> no ad (nil).

    private static func fetchAd(channelName: String, viewerId: String) -> Signal<SDKChatAdSearch?, NoError> {
        return Signal { subscriber in
            let task = Task {
                let ad = try? await client.chatAds.search(channelName: channelName, viewerId: viewerId)
                if Task.isCancelled {
                    return
                }
                subscriber.putNext(ad)
                subscriber.putCompletion()
            }
            return ActionDisposable {
                task.cancel()
            }
        }
    }

    // MARK: - SDKChatAdSearch -> Telegram sponsored Message

    // Mirrors AdMessages.swift's CachedMessage -> Message so the ad renders through
    // Telegram's own sponsored-message UI unchanged.
    private static func makeMessage(ad: SDKChatAdSearch, peerId: PeerId, channelPeer: Peer) -> Message? {
        var attributes: [MessageAttribute] = []

        // Render the ad's media (if any) as sponsored-message media. Real sponsored
        // messages carry a TelegramMediaImage (photo) or TelegramMediaFile (video) in
        // Message.media, and the ad bubble renders exactly those two — a
        // TelegramMediaWebFile is NOT shown in the sponsored layout. The backend
        // returns a plain HTTP mediaUrl; HttpReferenceMediaResource fetches it over
        // HTTPS by URL (cloud reference not needed).
        var messageMedia: [Media] = []
        if let mediaUrl = ad.mediaUrl {
            // The backend returns media as a HOST-RELATIVE path ("/media/…"), so
            // absoluteString alone is unfetchable — prepend the API host. The
            // /media/ path is public (served via CDN, no X-API-Key needed).
            let absoluteMediaURL = mediaUrl.host != nil
                ? mediaUrl.absoluteString
                : "https://ads-api.vipads.uz" + mediaUrl.absoluteString
            let mediaIdValue = Int64(bitPattern: UInt64(truncatingIfNeeded: absoluteMediaURL.hashValue))
            // We don't know the real pixel size; a 16:9 default reserves a sane
            // bubble slot and the media just fits into it.
            let dimensions = PixelDimensions(width: 1280, height: 720)

            if ad.mediaType == "VIDEO" {
                // Video ad: a TelegramMediaFile with a .Video attribute makes the ad
                // bubble play it inline. HttpReferenceMediaResource can only download
                // the whole file (no byte-range streaming), which is fine for a short
                // ad clip — it shows a solid placeholder until the download finishes,
                // then plays (autoplay depends on the user's autoplayVideo setting;
                // otherwise tap-to-play).
                let file = TelegramMediaFile(
                    fileId: MediaId(namespace: Namespaces.Media.CloudFile, id: mediaIdValue),
                    partialReference: nil,
                    resource: HttpReferenceMediaResource(url: absoluteMediaURL, size: nil),
                    previewRepresentations: [],
                    videoThumbnails: [],
                    videoCover: nil,
                    immediateThumbnailData: nil,
                    mimeType: "video/mp4",
                    size: nil,
                    attributes: [
                        .Video(duration: 0, size: dimensions, flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil),
                        .FileName(fileName: "ad.mp4")
                    ],
                    alternativeRepresentations: []
                )
                messageMedia.append(file)
            } else {
                // Image ad (default): TelegramMediaImage, the type real sponsored
                // photos use — the ad bubble renders it inline.
                let representation = TelegramMediaImageRepresentation(
                    dimensions: dimensions,
                    resource: HttpReferenceMediaResource(url: absoluteMediaURL, size: nil),
                    progressiveSizes: [],
                    immediateThumbnailData: nil
                )
                messageMedia.append(TelegramMediaImage(
                    imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: mediaIdValue),
                    representations: [representation],
                    immediateThumbnailData: nil,
                    reference: nil,
                    partialReference: nil,
                    flags: []
                ))
            }
        }

        // Encode the orderId so reportClickIfOurs(opaqueId:) can recover it on tap.
        let opaqueId = "novagram:\(ad.orderId.uuidString)".data(using: .utf8) ?? Data()
        attributes.append(AdMessageAttribute(
            opaqueId: opaqueId,
            messageType: .sponsored,
            url: ad.link,
            buttonText: "OPEN",
            sponsorInfo: nil,
            additionalInfo: nil,
            canReport: false,
            hasContentMedia: !messageMedia.isEmpty,
            minDisplayDuration: nil,
            maxDisplayDuration: nil
        ))

        var messagePeers = SimpleDictionary<PeerId, Peer>()
        messagePeers[channelPeer.id] = channelPeer

        let author: Peer = TelegramChannel(
            id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(1)),
            accessHash: nil,
            title: "Reklama",
            username: nil,
            photo: [],
            creationDate: 0,
            version: 0,
            participationStatus: .left,
            info: .broadcast(TelegramChannelBroadcastInfo(flags: [])),
            flags: [],
            restrictionInfo: nil,
            adminRights: nil,
            bannedRights: nil,
            defaultBannedRights: nil,
            usernames: [],
            storiesHidden: nil,
            nameColor: .blue,
            backgroundEmojiId: nil,
            profileColor: nil,
            profileBackgroundEmojiId: nil,
            emojiStatus: nil,
            approximateBoostLevel: nil,
            subscriptionUntilDate: nil,
            verificationIconFileId: nil,
            sendPaidMessageStars: nil,
            linkedMonoforumId: nil
        )
        messagePeers[author.id] = author

        let messageHash = (ad.text.hashValue &+ 31 &* peerId.hashValue) &* 31 &+ author.id.hashValue
        let messageStableVersion = UInt32(bitPattern: Int32(truncatingIfNeeded: messageHash))

        return Message(
            stableId: 0,
            stableVersion: messageStableVersion,
            id: MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: 0),
            globallyUniqueId: nil,
            groupingKey: nil,
            groupInfo: nil,
            threadId: nil,
            timestamp: Int32.max - 1,
            flags: [.Incoming],
            tags: [],
            globalTags: [],
            localTags: [],
            customTags: [],
            forwardInfo: nil,
            author: author,
            text: ad.text,
            attributes: attributes,
            media: messageMedia,
            peers: messagePeers,
            associatedMessages: SimpleDictionary<MessageId, Message>(),
            associatedMessageIds: [],
            associatedMedia: [:],
            associatedThreadInfo: nil,
            associatedStories: [:]
        )
    }
}
