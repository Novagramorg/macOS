//
//  FenixuzTipsController.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Fenixuz/Tips/Sources/FenixuzTipsScreen.swift
//
//  FenixPro feature'lari bo'yicha qisqa qo'llanma — 8 ta karta (rangli ikonka +
//  sarlavha + tavsif). iOS'da modal sheet; Mac'da FenixPro → "Imkoniyatlar"
//  qatoridan ochiladigan sahifa, hamda birinchi ishga tushirishda ko'rsatiladi.
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization
import FenixuzCore

// First-launch tracking — iOS bilan bir xil kalit (suite "pro_messager").
public enum FenixuzTips {
    private static let suite = "pro_messager"
    private static let shownKey = "fenixuz_tips_shown"

    public static var shouldShowOnFirstLaunch: Bool {
        !(UserDefaults(suiteName: suite)?.bool(forKey: shownKey) ?? false)
    }
    public static func markShown() {
        UserDefaults(suiteName: suite)?.set(true, forKey: shownKey)
    }
}

private struct TipDef {
    let symbol: String
    let color: FenixuzIconColor
    let title: String
    let body: String
}

private func fenixuzAllTips(_ l10n: FenixuzL10n) -> [TipDef] {
    return [
        TipDef(symbol: "eye.slash.fill",        color: .gray,   title: l10n.tips_ghost_title,         body: l10n.tips_ghost_body),
        TipDef(symbol: "mic.fill",              color: .red,    title: l10n.tips_stt_title,           body: l10n.tips_stt_body),
        TipDef(symbol: "person.2.fill",         color: .blue,   title: l10n.tips_multiAccount_title,  body: l10n.tips_multiAccount_body),
        TipDef(symbol: "clock.arrow.circlepath",color: .teal,   title: l10n.tips_editedHistory_title, body: l10n.tips_editedHistory_body),
        TipDef(symbol: "lock.fill",             color: .green,  title: l10n.tips_chatLock_title,      body: l10n.tips_chatLock_body),
        TipDef(symbol: "text.append",           color: .orange, title: l10n.tips_autoText_title,      body: l10n.tips_autoText_body),
        TipDef(symbol: "character.bubble.fill", color: .pink,   title: l10n.tips_translate_title,     body: l10n.tips_translate_body),
        TipDef(symbol: "flame.fill",            color: .gold,   title: l10n.tips_fenixHub_title,      body: l10n.tips_fenixHub_body),
    ]
}

private enum FenixuzTipsEntry: Comparable, Identifiable {
    case section(Int)
    case tipRow(Int, TipDef)
    case tipBody(Int, String)

    var stableId: AnyHashable {
        switch self {
        case let .section(i): return "section_\(i)"
        case let .tipRow(i, _): return "row_\(i)"
        case let .tipBody(i, _): return "body_\(i)"
        }
    }
    var id: AnyHashable { stableId }

    var sortIndex: Int {
        switch self {
        case let .section(i): return i * 1000
        case let .tipRow(i, _): return i * 1000 + 1
        case let .tipBody(i, _): return i * 1000 + 2
        }
    }

    static func < (lhs: FenixuzTipsEntry, rhs: FenixuzTipsEntry) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    static func == (lhs: FenixuzTipsEntry, rhs: FenixuzTipsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.section(l), .section(r)): return l == r
        case let (.tipRow(li, lt), .tipRow(ri, rt)): return li == ri && lt.title == rt.title && lt.symbol == rt.symbol
        case let (.tipBody(li, lb), .tipBody(ri, rb)): return li == ri && lb == rb
        default: return false
        }
    }

    func item(_ initialSize: NSSize) -> TableRowItem {
        switch self {
        case .section:
            return GeneralRowItem(initialSize, height: 16, stableId: stableId, viewType: .separator)
        case let .tipRow(_, tip):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: tip.title,
                icon: fenixuzSettingsIcon(systemName: tip.symbol, color: tip.color),
                type: .none,
                viewType: .singleItem
            )
        case let .tipBody(_, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textBottomItem)
        }
    }
}

private func fenixuzTipsEntries(l10n: FenixuzL10n) -> [FenixuzTipsEntry] {
    var entries: [FenixuzTipsEntry] = []
    for (i, tip) in fenixuzAllTips(l10n).enumerated() {
        entries.append(.section(i))
        entries.append(.tipRow(i, tip))
        entries.append(.tipBody(i, tip.body))
    }
    entries.append(.section(1000)) // trailing spacer
    return entries
}

private func prepareTipsTransition(left: [AppearanceWrapperEntry<FenixuzTipsEntry>], right: [AppearanceWrapperEntry<FenixuzTipsEntry>], initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(initialSize)
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

class FenixuzTipsController: TableViewController {

    private let disposable = MetaDisposable()

    override var defaultBarTitle: String {
        return FenixuzL10n.current.tips_screenTitle
    }

    override var removeAfterDisapper: Bool {
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let initialSize = self.atomicSize
        let previousEntries = Atomic<[AppearanceWrapperEntry<FenixuzTipsEntry>]>(value: [])

        let signal = appearanceSignal
            |> map { appearance -> TableUpdateTransition in
                let l10n = FenixuzL10n(languageCode: appCurrentLanguage.languageCode)
                let entries = fenixuzTipsEntries(l10n: l10n)
                    .map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let previous = previousEntries.swap(entries)
                return prepareTipsTransition(left: previous, right: entries, initialSize: initialSize.modify { $0 })
            }
            |> deliverOnMainQueue

        disposable.set(signal.start(next: { [weak self] transition in
            self?.genericView.merge(with: transition)
            self?.readyOnce()
        }))
    }

    deinit {
        disposable.dispose()
    }
}
