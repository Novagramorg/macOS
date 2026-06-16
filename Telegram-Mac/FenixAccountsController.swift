//
//  FenixAccountsController.swift
//  Telegram
//
//  Fenixuz: "All Accounts" screen — lists every logged-in account, switch on tap.
//  AppKit analogue of the iOS FenixAccountsController. Opened from Settings → Accounts.
//

import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit

private final class FenixAccountsArguments {
    let context: AccountContext
    let switchAccount: (AccountWithInfo) -> Void
    let openInWindow: (AccountWithInfo) -> Void
    let logoutAccount: (AccountWithInfo) -> Void
    let addAccount: () -> Void
    init(context: AccountContext, switchAccount: @escaping (AccountWithInfo) -> Void, openInWindow: @escaping (AccountWithInfo) -> Void, logoutAccount: @escaping (AccountWithInfo) -> Void, addAccount: @escaping () -> Void) {
        self.context = context
        self.switchAccount = switchAccount
        self.openInWindow = openInWindow
        self.logoutAccount = logoutAccount
        self.addAccount = addAccount
    }
}

private let _id_add_account = InputDataIdentifier("fenix_add_account")
private func _id_account(_ id: AccountRecordId) -> InputDataIdentifier {
    return InputDataIdentifier("fenix_account_\(id.int64)")
}

private struct FenixAccountTuple: Equatable {
    let account: AccountWithInfo
    let isPrimary: Bool
    let viewType: GeneralViewType
}

private func fenixAccountsEntries(primary: AccountRecordId?, accounts: [AccountWithInfo], arguments: FenixAccountsArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("ACCOUNTS (\(accounts.count))"), data: InputDataGeneralTextData(viewType: .textTopItem)))
    index += 1

    for (i, account) in accounts.enumerated() {
        let isPrimary = account.account.id == primary

        let viewType: GeneralViewType
        if accounts.count == 1 {
            viewType = .singleItem
        } else if i == 0 {
            viewType = .firstItem
        } else if i == accounts.count - 1 {
            viewType = .lastItem
        } else {
            viewType = .innerItem
        }

        let tuple = FenixAccountTuple(account: account, isPrimary: isPrimary, viewType: viewType)

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_account(account.account.id), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: account.peer, account: account.account, context: nil, stableId: stableId, height: 48, photoSize: NSSize(width: 36, height: 36), titleStyle: ControlStyle(font: .medium(.title), foregroundColor: theme.colors.text, highlightColor: theme.colors.underSelectedColor), status: isPrimary ? "Current" : nil, borderType: [.Right], inset: NSEdgeInsets(left: 12, right: 12), viewType: viewType, action: {
                if !isPrimary {
                    arguments.switchAccount(account)
                }
            }, contextMenuItems: {
                var items: [ContextMenuItem] = []
                items.append(ContextMenuItem(strings().accountOpenInWindow, handler: {
                    arguments.openInWindow(account)
                }, itemImage: MenuAnimation.menu_open_profile.value))
                items.append(ContextSeparatorItem())
                items.append(ContextMenuItem(strings().accountSettingsDeleteAccount, handler: {
                    arguments.logoutAccount(account)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                return .single(items)
            }, alwaysHighlight: true, badgeNode: GlobalBadgeNode(account.account, sharedContext: arguments.context.sharedContext, getColor: { _ in theme.colors.accent }, sync: false), highlightVerified: true)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add_account, data: InputDataGeneralData(name: strings().accountSettingsAddAccount, color: theme.colors.accent, icon: nil, type: .none, viewType: .singleItem, action: arguments.addAccount)))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    return entries
}

func FenixAccountsController(context: AccountContext) -> InputDataController {

    let arguments = FenixAccountsArguments(context: context, switchAccount: { account in
        context.sharedContext.switchToAccount(id: account.account.id, action: nil)
    }, openInWindow: { account in
        context.sharedContext.openAccount(id: account.account.id)
    }, logoutAccount: { account in
        verifyAlert_button(for: context.window, information: strings().accountConfirmLogoutText, successHandler: { _ in
            _ = logoutFromAccount(id: account.account.id, accountManager: context.sharedContext.accountManager, alreadyLoggedOutRemotely: false).start()
        })
    }, addAccount: {
        let testingEnvironment = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        context.sharedContext.beginNewAuth(testingEnvironment: testingEnvironment)
    })

    let signal = context.sharedContext.activeAccountsWithInfo |> deliverOnMainQueue |> map { value -> [InputDataEntry] in
        return fenixAccountsEntries(primary: value.primary, accounts: value.accounts, arguments: arguments)
    }

    let controller = InputDataController(dataSignal: signal |> map { InputDataSignalValue(entries: $0) }, title: "All Accounts", hasDone: false)

    return controller
}
