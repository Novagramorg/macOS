//
//  FenixuzAboutController.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Fenixuz/ProMessager/Sources/FenixAboutController.swift
//
//  "About FenixPro" — FenixPro nima ekanini va qaysi qo'shimcha vositalarni
//  beradi shuni tushuntiruvchi read-only sahifa. Tips (qo'llanma)dan farqli —
//  bu mahsulotning o'zini ta'riflaydi. FenixPro → "About FenixPro" qatoridan.
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization
import FenixuzCore

private struct AboutFeature {
    let symbol: String
    let color: FenixuzIconColor
    let title: String
    let body: String
}

private func fenixuzAboutFeatures(_ l10n: FenixuzL10n) -> [AboutFeature] {
    return [
        AboutFeature(symbol: "eye.slash.fill",         color: .gray,   title: l10n.about_ghost_title,         body: l10n.about_ghost_body),
        AboutFeature(symbol: "person.2.fill",          color: .blue,   title: l10n.about_multiAccount_title,  body: l10n.about_multiAccount_body),
        AboutFeature(symbol: "qrcode",                 color: .violet, title: l10n.about_qrLogin_title,       body: l10n.about_qrLogin_body),
        AboutFeature(symbol: "clock.arrow.circlepath", color: .teal,   title: l10n.about_editedHistory_title, body: l10n.about_editedHistory_body),
        AboutFeature(symbol: "mic.fill",               color: .red,    title: l10n.about_stt_title,           body: l10n.about_stt_body),
        AboutFeature(symbol: "lock.fill",              color: .green,  title: l10n.about_chatLock_title,      body: l10n.about_chatLock_body),
        AboutFeature(symbol: "text.append",            color: .orange, title: l10n.about_messaging_title,     body: l10n.about_messaging_body),
    ]
}

private enum FenixuzAboutEntry: Comparable, Identifiable {
    case section(Int)
    case header(Int, String, String)        // sortIndex, key, text
    case text(Int, String, String)          // sortIndex, key, text
    case featureRow(Int, String, AboutFeature)

    var stableId: AnyHashable {
        switch self {
        case let .section(i):         return "section_\(i)"
        case let .header(_, k, _):    return k
        case let .text(_, k, _):      return k
        case let .featureRow(_, k, _):return k
        }
    }
    var id: AnyHashable { stableId }

    var sortIndex: Int {
        switch self {
        case let .section(i):         return i
        case let .header(i, _, _):    return i
        case let .text(i, _, _):      return i
        case let .featureRow(i, _, _):return i
        }
    }

    static func < (lhs: FenixuzAboutEntry, rhs: FenixuzAboutEntry) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    static func == (lhs: FenixuzAboutEntry, rhs: FenixuzAboutEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.section(a), .section(b)): return a == b
        case let (.header(ai, ak, at), .header(bi, bk, bt)): return ai == bi && ak == bk && at == bt
        case let (.text(ai, ak, at), .text(bi, bk, bt)): return ai == bi && ak == bk && at == bt
        case let (.featureRow(ai, ak, af), .featureRow(bi, bk, bf)):
            return ai == bi && ak == bk && af.title == bf.title && af.symbol == bf.symbol
        default: return false
        }
    }

    func item(_ initialSize: NSSize) -> TableRowItem {
        switch self {
        case .section:
            return GeneralRowItem(initialSize, height: 16, stableId: stableId, viewType: .separator)
        case let .header(_, _, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textTopItem)
        case let .text(_, _, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textBottomItem)
        case let .featureRow(_, _, feature):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: feature.title,
                icon: fenixuzSettingsIcon(systemName: feature.symbol, color: feature.color),
                type: .none,
                viewType: .singleItem
            )
        }
    }
}

private func fenixuzAboutEntries(_ l10n: FenixuzL10n) -> [FenixuzAboutEntry] {
    var entries: [FenixuzAboutEntry] = []
    var idx = 0
    func n() -> Int { idx += 1; return idx }

    entries.append(.section(n()))
    entries.append(.header(n(), "introH", l10n.about_introHeader))
    entries.append(.text(n(), "introB", l10n.about_introBody))

    entries.append(.section(n()))
    entries.append(.header(n(), "featH", l10n.about_featuresHeader))

    for (i, feature) in fenixuzAboutFeatures(l10n).enumerated() {
        entries.append(.section(n()))
        entries.append(.featureRow(n(), "feat_\(i)", feature))
        entries.append(.text(n(), "featB_\(i)", feature.body))
    }

    entries.append(.section(n()))
    entries.append(.text(n(), "footer", l10n.about_footer))
    entries.append(.section(n()))

    return entries
}

private func prepareAboutTransition(left: [AppearanceWrapperEntry<FenixuzAboutEntry>], right: [AppearanceWrapperEntry<FenixuzAboutEntry>], initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(initialSize)
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

class FenixuzAboutController: TableViewController {

    private let disposable = MetaDisposable()

    override var defaultBarTitle: String {
        return FenixuzL10n.current.about_screenTitle
    }

    override var removeAfterDisapper: Bool {
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let initialSize = self.atomicSize
        let previousEntries = Atomic<[AppearanceWrapperEntry<FenixuzAboutEntry>]>(value: [])

        let signal = appearanceSignal
            |> map { appearance -> TableUpdateTransition in
                let l10n = FenixuzL10n(languageCode: appCurrentLanguage.languageCode)
                let entries = fenixuzAboutEntries(l10n)
                    .map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let previous = previousEntries.swap(entries)
                return prepareAboutTransition(left: previous, right: entries, initialSize: initialSize.modify { $0 })
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
