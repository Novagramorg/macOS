//
//  FenixuzAnalyticsController.swift
//  Telegram-Mac
//
//  Settings → Analytics page for the Novagram fork. Shows two live numbers from the
//  Novagram Statistics API (https://statistics.novagram.org):
//    • "Novagram users"  — downloads (one per device).
//    • "Active accounts" — devices currently holding at least one logged-in account.
//
//  Mirror of the iOS Analytics page, but native AppKit (TableViewController). The install +
//  active-presence tracking itself lives in FenixuzAnalyticsManager; this screen only renders
//  GET /v1/stats.
//

import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import FenixuzCore

// MARK: - Number formatting

private let fenixuzAnalyticsNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    return formatter
}()

private func fenixuzFormatCount(_ value: Int?) -> String {
    guard let value = value else {
        return "—"
    }
    return fenixuzAnalyticsNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

// MARK: - State

private struct FenixuzAnalyticsState: Equatable {
    var devices: Int?
    var accounts: Int?
    var loaded: Bool
    var failed: Bool
}

// MARK: - Entries

private enum FenixuzAnalyticsEntryId: Hashable {
    case section(Int)
    case header(Int)
    case devicesRow
    case devicesFooter
    case accountsRow
    case accountsFooter
}

private enum FenixuzAnalyticsEntry: Comparable, Identifiable {
    case section(Int)
    case header(Int, FenixuzAnalyticsEntryId, String)
    case valueRow(Int, FenixuzAnalyticsEntryId, String, CGImage?, String, GeneralViewType)
    case footer(Int, FenixuzAnalyticsEntryId, String)

    var stableId: AnyHashable {
        switch self {
        case let .section(id):              return FenixuzAnalyticsEntryId.section(id)
        case let .header(_, id, _):         return id
        case let .valueRow(_, id, _, _, _, _): return id
        case let .footer(_, id, _):         return id
        }
    }

    var sortIndex: Int {
        switch self {
        case let .section(id):              return id * 1000
        case let .header(idx, _, _):        return idx
        case let .valueRow(idx, _, _, _, _, _): return idx
        case let .footer(idx, _, _):        return idx
        }
    }

    static func < (lhs: FenixuzAnalyticsEntry, rhs: FenixuzAnalyticsEntry) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    static func == (lhs: FenixuzAnalyticsEntry, rhs: FenixuzAnalyticsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.section(l), .section(r)): return l == r
        case let (.header(l1, l2, l3), .header(r1, r2, r3)): return l1 == r1 && l2 == r2 && l3 == r3
        case let (.valueRow(l1, l2, l3, l4, l5, l6), .valueRow(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 === r4 && l5 == r5 && l6 == r6
        case let (.footer(l1, l2, l3), .footer(r1, r2, r3)): return l1 == r1 && l2 == r2 && l3 == r3
        default: return false
        }
    }

    func item(initialSize: NSSize) -> TableRowItem {
        switch self {
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        case let .header(_, _, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textTopItem)
        case let .valueRow(_, _, title, icon, value, viewType):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: icon,
                type: .context(value),
                viewType: viewType,
                action: {}
            )
        case let .footer(_, _, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textBottomItem)
        }
    }
}

private func fenixuzAnalyticsEntries(state: FenixuzAnalyticsState) -> [FenixuzAnalyticsEntry] {
    var entries: [FenixuzAnalyticsEntry] = []
    var idx = 0
    func next() -> Int { idx += 1; return idx }
    var sectionId = 0

    let devicesValue = state.failed ? "—" : fenixuzFormatCount(state.devices)
    let accountsValue = state.failed ? "—" : fenixuzFormatCount(state.accounts)

    // ─── NOVAGRAM USERS ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(1), "NOVAGRAM USERS"))
    entries.append(.valueRow(next(), .devicesRow, "Novagram users",
                             fenixuzSettingsIcon(systemName: "person.3.fill", color: .blue),
                             devicesValue, .singleItem))
    entries.append(.footer(next(), .devicesFooter, "Total number of devices that have installed Novagram."))

    // ─── ACTIVE ACCOUNTS ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(2), "ACTIVE ACCOUNTS"))
    entries.append(.valueRow(next(), .accountsRow, "Active accounts",
                             fenixuzSettingsIcon(systemName: "checkmark.seal.fill", color: .green),
                             accountsValue, .singleItem))
    entries.append(.footer(next(), .accountsFooter, "Devices that currently have at least one account logged in."))

    entries.append(.section(sectionId))

    return entries
}

// MARK: - Transition

private func prepareFenixuzAnalyticsTransition(left: [AppearanceWrapperEntry<FenixuzAnalyticsEntry>], right: [AppearanceWrapperEntry<FenixuzAnalyticsEntry>], initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(initialSize: initialSize)
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

// MARK: - Controller

final class FenixuzAnalyticsController: TableViewController {

    private let disposable = MetaDisposable()
    private let statsDisposable = MetaDisposable()
    private let statePromise = ValuePromise(FenixuzAnalyticsState(devices: nil, accounts: nil, loaded: false, failed: false), ignoreRepeated: true)
    private let stateValue = Atomic(value: FenixuzAnalyticsState(devices: nil, accounts: nil, loaded: false, failed: false))

    override var defaultBarTitle: String {
        return "Analytics"
    }

    private func updateState(_ mutate: (inout FenixuzAnalyticsState) -> Void) {
        let new = self.stateValue.modify { current in
            var s = current
            mutate(&s)
            return s
        }
        self.statePromise.set(new)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let initialSize = self.atomicSize
        let previousEntries = Atomic<[AppearanceWrapperEntry<FenixuzAnalyticsEntry>]>(value: [])

        let signal = combineLatest(queue: prepareQueue, statePromise.get(), appearanceSignal)
            |> map { state, appearance -> TableUpdateTransition in
                let entries = fenixuzAnalyticsEntries(state: state)
                    .map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let previous = previousEntries.swap(entries)
                return prepareFenixuzAnalyticsTransition(left: previous, right: entries, initialSize: initialSize.modify { $0 })
            }
            |> deliverOnMainQueue

        disposable.set(signal.start(next: { [weak self] transition in
            self?.genericView.merge(with: transition)
            self?.readyOnce()
        }))

        self.loadStats()
    }

    private func loadStats() {
        statsDisposable.set((FenixuzAnalyticsManager.shared.counts()
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self = self else { return }
            self.updateState { state in
                state.devices = result.devices
                state.accounts = result.accounts
                state.loaded = true
                state.failed = (result.devices == nil && result.accounts == nil)
            }
        }))
    }

    deinit {
        disposable.dispose()
        statsDisposable.dispose()
    }
}
