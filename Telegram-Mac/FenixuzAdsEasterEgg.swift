//
//  FenixuzAdsEasterEgg.swift
//  Telegram-Mac
//
//  iOS port: Feature #6 — hidden "Ads" toggle (NovagramPro Easter-egg).
//  iOS source: submodules/Fenixuz/ProMessager/Sources/FenixSettingsController.swift
//  (FenixAdsRevealGestureRecognizer + FenixAdsStrings) and the consumer hook in
//  submodules/TelegramUI/Sources/ChatHistoryListNode.swift.
//
//  Mac trigger: 10 quick clicks (≤0.7s apart) on the version row at the bottom
//  of Settings (AccountViewController) toggle a hidden "Show ads" switch row.
//  The switch writes the SAME key the iOS build uses, so semantics match 1:1:
//
//    UserDefaults(suiteName: "pro_messager")
//      "fenix_show_ads"             Bool, default true  — sponsored messages shown
//      "fenix_ads_section_revealed" Bool, default false — hidden row visible
//
//  Consumer: ChatController skips creating ChatAdData when showAds == false —
//  sponsored messages are never requested. Like on iOS the flag is read when a
//  chat opens, so already-open chats keep their state until reopened.
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization

final class FenixuzAdsGate {
    struct UIState: Equatable {
        var revealed: Bool
        var showAds: Bool
    }

    private static let defaults = UserDefaults(suiteName: "pro_messager")
    private static let showAdsKey = "fenix_show_ads"
    private static let revealedKey = "fenix_ads_section_revealed"

    // In-memory source of truth, seeded once from the persisted defaults. Every mutation
    // updates memory AND writes to defaults, but the UI is always driven from memory —
    // never from a re-read. A sandboxed suite's read can lag its own write (cfprefsd), so
    // re-reading right after set would report the stale value and leave the just-revealed
    // row hidden.
    private static var memoRevealed: Bool = defaults?.object(forKey: revealedKey) as? Bool ?? false
    private static var memoShowAds: Bool = defaults?.object(forKey: showAdsKey) as? Bool ?? true

    // Drives the Settings list rebuild (combined into AccountViewController's signal).
    static let uiState: ValuePromise<UIState> = ValuePromise(FenixuzAdsGate.currentState(), ignoreRepeated: true)

    private static func currentState() -> UIState {
        return UIState(revealed: memoRevealed, showAds: memoShowAds)
    }

    // Read once per chat open by ChatController (same semantics as the iOS hook
    // in ChatHistoryListNode init).
    static var showAds: Bool {
        return memoShowAds
    }

    static func setShowAds(_ value: Bool) {
        memoShowAds = value
        defaults?.set(value, forKey: showAdsKey)
        uiState.set(currentState())
    }

    // 10 quick clicks on the version row toggle the hidden row (iOS uses the
    // same count/window for taps on the NovagramPro page).
    private static let requiredClicks = 10
    private static let clickWindow: Double = 0.7
    private static var lastClickTimestamp: Double = 0
    private static var clickCount: Int = 0

    static func handleVersionClick(window: Window) {
        let timestamp = CACurrentMediaTime()
        if timestamp - lastClickTimestamp > clickWindow {
            clickCount = 0
        }
        lastClickTimestamp = timestamp
        clickCount += 1
        guard clickCount >= requiredClicks else { return }
        clickCount = 0

        memoRevealed.toggle()
        defaults?.set(memoRevealed, forKey: revealedKey)
        uiState.set(currentState())

        alert(for: window, info: FenixuzAdsStrings.revealedAlert(revealed: memoRevealed, langCode: appCurrentLanguage.languageCode))
    }
}

// Strings match the iOS FenixAdsStrings texts (en / uz / ru), kept local to the
// feature to avoid touching the shared FenixuzCore localization.
enum FenixuzAdsStrings {
    static func toggleTitle(langCode: String) -> String {
        switch langCode {
        case "uz": return "Reklamani ko'rsatish"
        case "ru": return "Показывать рекламу"
        default:   return "Show ads"
        }
    }

    static func toggleTip(langCode: String) -> String {
        switch langCode {
        case "uz": return "Yoqilsa — Telegram sponsorlik xabarlari ko'rsatiladi; o'chirilsa — yashiriladi"
        case "ru": return "Вкл — спонсорские сообщения Telegram показываются; выкл — скрыты"
        default:   return "On — Telegram sponsored messages shown; Off — suppressed"
        }
    }

    static func revealedAlert(revealed: Bool, langCode: String) -> String {
        if revealed {
            switch langCode {
            case "uz": return "Reklama bo'limi ochildi"
            case "ru": return "Раздел рекламы открыт"
            default:   return "Ads section shown"
            }
        } else {
            switch langCode {
            case "uz": return "Reklama bo'limi yashirildi"
            case "ru": return "Раздел рекламы скрыт"
            default:   return "Ads section hidden"
            }
        }
    }
}
