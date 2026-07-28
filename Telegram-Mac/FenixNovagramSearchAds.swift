//
//  FenixNovagramSearchAds.swift
//  Telegram-Mac
//
//  Port of iOS submodules/Fenixuz/NovagramAds/Sources/FenixNovagramAds/FenixNovagramSearchAds.swift.
//  When the user types in global search we ask OUR backend (ads-api.vipads.uz, via the shared
//  NovagramAds SPM SDK) for a promoted channel matching the typed text; if there is one we show
//  it at the very top of the results — above Telegram's own sponsored row — with an
//  "ads by Novagram" trailing label. No ad (backend answers HTTP 404) or any error → nil, so
//  Telegram's own results show unchanged. `/api/search_ads/order/search/` is auth-optional, so
//  an anonymous client is enough — no login is wired into the app.
//
//  Mac differences vs iOS: App Store gate is compile-time `#if APP_STORE`; `AccountContext` is
//  an in-target class (no import). The consumer hook lives in SearchController.swift
//  (a new `.novagramAdPeer` search entry, prepended at row 0).
//

import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import NovagramAds

/// A channel promoted into global search by our own ads backend, already resolved to a
/// Telegram peer so it can be rendered and opened like any other search result.
struct FenixNovagramPromotedChannel: Equatable {
    let peer: EnginePeer
    let orderId: String
    let channelId: String
}

enum FenixNovagramSearchAds {
    // Ad serving authenticates with the X-API-Key — never the user JWT — since
    // NovagramAds 2.1.0. Mirrors iOS FenixNovagramSearchAds so both clients send the
    // same key (search_ads/order/search+click now require it, like chat ads).
    private static let client = SDKClient(
        configuration: SDKConfiguration(apiKey: FenixNovagramAdsConfig.apiKey)
    )

    /// Promoted channel for `query`, resolved to a Telegram peer, or `nil` if none. Emits `nil`
    /// first so the caller renders immediately, then the resolved channel once the backend
    /// answers and the peer is resolved.
    static func promotedChannel(context: AccountContext, query: String) -> Signal<FenixNovagramPromotedChannel?, NoError> {
        let tag = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tag.count >= 2 else {
            return .single(nil)
        }
        let viewerId = self.viewerId(context: context)

        let resolved = searchAd(tag: tag, viewerId: viewerId)
        |> mapToSignal { result -> Signal<FenixNovagramPromotedChannel?, NoError> in
            guard let result = result else {
                return .single(nil)
            }
            return context.engine.peers.resolvePeerByName(name: result.channelName, referrer: nil)
            |> mapToSignal { resolveResult -> Signal<FenixNovagramPromotedChannel?, NoError> in
                switch resolveResult {
                case .progress:
                    return .complete()
                case let .result(peer):
                    guard let peer = peer else {
                        return .single(nil)
                    }
                    return .single(FenixNovagramPromotedChannel(peer: peer, orderId: result.orderId.uuidString, channelId: result.channelId))
                }
            }
        }

        return .single(nil) |> then(resolved)
    }

    /// Report a tap on a promoted channel back to our backend. Fire-and-forget.
    static func reportClick(orderId: String, context: AccountContext) {
        guard let uuid = UUID(uuidString: orderId) else {
            return
        }
        let viewerId = self.viewerId(context: context)
        Task {
            _ = try? await client.searchAds.click(orderId: uuid, viewerId: viewerId)
        }
    }

    // MARK: - viewer id

    // Real Telegram user id in App Store builds; a throwaway random id in every dev/test build.
    // The backend caps each order to one view per viewer, so with a real id the ad shows once
    // and then never again — impossible to test. `#if APP_STORE` is false for local/dev builds
    // and true only for the actual App Store submission.
    private static func viewerId(context: AccountContext) -> String {
        #if APP_STORE
        return "\(context.account.peerId.id._internalGetInt64Value())"
        #else
        return "test-\(Int64.random(in: 100_000_000 ... 999_999_999))"
        #endif
    }

    // MARK: - SDK bridge (async -> Signal). 404 / any error -> no ad (nil).

    private static func searchAd(tag: String, viewerId: String) -> Signal<SDKSearchResult?, NoError> {
        return Signal { subscriber in
            let task = Task {
                let result = try? await client.searchAds.search(tag: tag, viewerId: viewerId)
                if Task.isCancelled {
                    return
                }
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
            return ActionDisposable {
                task.cancel()
            }
        }
    }
}
