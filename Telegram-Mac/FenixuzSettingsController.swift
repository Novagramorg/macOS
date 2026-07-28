//
//  FenixuzSettingsController.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Fenixuz/ProMessager/Sources/FenixSettingsController.swift
//
//  Mac uchun Settings → Fenixuz ekrani. iOS dagi 5 ta section'ni qaytaradi:
//    INTERFACE  — hide folders, stories panel, mutual badge
//    CHAT       — deleted messages, jump-to-first, ghost mode, camera picker
//    MESSAGES   — text style*, auto-text*, auto-translate*, translate button, translation language*
//    VOICE→TEXT — STT enable, recognition language
//    PROTECTION — block foreign numbers, block APK files
//
//  *: sub-controller'lar iOS'da ItemListController orqali ochiladi. Mac uchun ular
//  Wave 5 ga ko'chirilgan — hozir "Coming soon" alert chiqaradi va qiymat
//  UserDefaults'ga yozilmaydi. Settings panel'i o'zi ko'rinadi, toggle'lar
//  ishlaydi va shu UserDefaults'ga yoziladi (consumer kod hozircha o'qimaydi —
//  iOS'da `FenixSettingsChanged` notification orqali o'qiladi; Mac consumerlar
//  kelajakdagi waves'da ulanadi).
//
//  Storage convention (iOS bilan bir xil):
//    UserDefaults(suiteName: "pro_messager")
//      "hide_folders" Bool, "show_stories" Bool (default true),
//      "show_mutual_contact_symbol" Bool (default true),
//      "show_deleted_messages" Bool, "show_view_first_message" Bool,
//      "show_ghost_mode_button" Bool, "long_press_camera_selection" Bool (default true),
//      "show_translate_messages" Bool (default true),
//      "stt_enabled" Bool (default true), "stt_language" String (default "en-US"),
//      "block_foreign_users" Bool, "block_apk_files" Bool
//

import Cocoa
import TGUIKit
import TelegramCore
import Localization
import SwiftSignalKit
import Postbox
import FenixuzCore

// MARK: - Storage facade

private let fenixuzDefaults = UserDefaults(suiteName: "pro_messager")

private enum FenixuzDefaultsKey {
    static let hideFolders                = "hide_folders"
    static let showStories                = "show_stories"
    static let showMutualContactSymbol    = "show_mutual_contact_symbol"
    static let showDeletedMessages        = "show_deleted_messages"
    static let showViewFirstMessage       = "show_view_first_message"
    static let showGhostMode              = "show_ghost_mode_button"
    static let ghostModeActive            = "is_ghost_mode_active"
    static let longPressCameraSelection   = "long_press_camera_selection"
    static let showTranslateMessages      = "show_translate_messages"
    static let textStyle                  = "text_style"
    static let autoTextEnabled            = "auto_text_enabled"
    static let autoTranslateEnabled       = "auto_translate_enabled"
    static let sttEnabled                 = "stt_enabled"
    static let sttLanguage                = "stt_language"
    static let blockForeignUsers          = "block_foreign_users"
}

private struct FenixuzSettingsState: Equatable {
    var hideFolders: Bool
    var showStories: Bool
    var showMutualContactSymbol: Bool
    var showDeletedMessages: Bool
    var showViewFirstMessage: Bool
    var showGhostMode: Bool
    var ghostModeActive: Bool
    var longPressCameraSelection: Bool
    var showTranslateMessages: Bool
    var textStyle: String
    var autoTextEnabled: Bool
    var autoTranslateEnabled: Bool
    var sttEnabled: Bool
    var sttLanguage: String
    var blockForeignUsers: Bool
    // Feature #46: derived from the keychain (source of truth), NOT fenixuzDefaults.
    var chatLockMasterEnabled: Bool
    // NovagramProxy opt-in — derived from FenixuzAutoProxyManager (owns the "pro_messager" key).
    var novagramProxyEnabled: Bool

    static func load() -> FenixuzSettingsState {
        let d = fenixuzDefaults
        return FenixuzSettingsState(
            hideFolders: d?.bool(forKey: FenixuzDefaultsKey.hideFolders) ?? false,
            showStories: d?.object(forKey: FenixuzDefaultsKey.showStories) as? Bool ?? true,
            showMutualContactSymbol: d?.object(forKey: FenixuzDefaultsKey.showMutualContactSymbol) as? Bool ?? true,
            showDeletedMessages: d?.bool(forKey: FenixuzDefaultsKey.showDeletedMessages) ?? false,
            showViewFirstMessage: d?.bool(forKey: FenixuzDefaultsKey.showViewFirstMessage) ?? false,
            showGhostMode: d?.bool(forKey: FenixuzDefaultsKey.showGhostMode) ?? false,
            ghostModeActive: d?.bool(forKey: FenixuzDefaultsKey.ghostModeActive) ?? false,
            longPressCameraSelection: d?.object(forKey: FenixuzDefaultsKey.longPressCameraSelection) as? Bool ?? true,
            showTranslateMessages: d?.object(forKey: FenixuzDefaultsKey.showTranslateMessages) as? Bool ?? true,
            textStyle: d?.string(forKey: FenixuzDefaultsKey.textStyle) ?? "none",
            autoTextEnabled: d?.bool(forKey: FenixuzDefaultsKey.autoTextEnabled) ?? false,
            autoTranslateEnabled: d?.bool(forKey: FenixuzDefaultsKey.autoTranslateEnabled) ?? false,
            sttEnabled: d?.object(forKey: FenixuzDefaultsKey.sttEnabled) as? Bool ?? true,
            sttLanguage: d?.string(forKey: FenixuzDefaultsKey.sttLanguage) ?? "en-US",
            blockForeignUsers: d?.bool(forKey: FenixuzDefaultsKey.blockForeignUsers) ?? false,
            chatLockMasterEnabled: FenixuzChatPincodeManager.shared.isMasterEnabled(),
            novagramProxyEnabled: FenixuzAutoProxyManager.shared.isEnabled
        )
    }
}

// MARK: - Arguments

private final class FenixuzSettingsArguments {
    let context: AccountContext
    let updateBool: (String, Bool) -> Void
    let pickSTTLanguage: () -> Void
    let openSubController: (String) -> Void   // "text_style" | "auto_text" | "auto_translate" | "translate_language"
    let updateChatLockMaster: (Bool) -> Void  // #46: bespoke ON→set-master / OFF→confirm+wipe flow
    let updateNovagramProxy: (Bool) -> Void   // NovagramProxy opt-in → probe + enable/disable

    init(
        context: AccountContext,
        updateBool: @escaping (String, Bool) -> Void,
        pickSTTLanguage: @escaping () -> Void,
        openSubController: @escaping (String) -> Void,
        updateChatLockMaster: @escaping (Bool) -> Void,
        updateNovagramProxy: @escaping (Bool) -> Void
    ) {
        self.context = context
        self.updateBool = updateBool
        self.pickSTTLanguage = pickSTTLanguage
        self.openSubController = openSubController
        self.updateChatLockMaster = updateChatLockMaster
        self.updateNovagramProxy = updateNovagramProxy
    }
}

// MARK: - Entries

private enum FenixuzEntryId: Hashable {
    case section(Int)
    case header(Int)
    case topTips
    case topAbout
    case topBots
    case interfaceHideFolders, interfaceStories, interfaceMutual, interfaceFooter
    case chatDeleted, chatFirstMessage, chatGhostActive, chatGhost, chatCamera, chatFooter
    case messagingTextStyle, messagingAutoText, messagingAutoTranslate, messagingTranslateToggle, messagingTranslateLang, messagingFooter
    case sttEnabled, sttLanguage
    case protectionChatLock, protectionProxy, protectionForeign, protectionFooter
}

// iOS 1:1 — har bir row uchun rangli kvadrat ikonka (FenixuzIconColor + SF Symbol).
private func fenixuzSettingsRowIcon(_ id: FenixuzEntryId) -> CGImage? {
    let map: (String, FenixuzIconColor)?
    switch id {
    case .topAbout:                 map = ("info.circle.fill", .blue)
    case .topBots:                  map = ("bolt.fill", .teal)
    case .topTips:                  map = ("sparkles", .gold)
    case .interfaceHideFolders:     map = ("folder.badge.minus", .lightBlue)
    case .interfaceStories:         map = ("circle.dashed", .violet)
    case .interfaceMutual:          map = ("person.2.fill", .blue)
    case .chatDeleted:              map = ("trash.fill", .red)
    case .chatFirstMessage:         map = ("arrow.up.to.line", .blue)
    case .chatGhostActive:          map = ("eye.slash.fill", .gray)
    case .chatGhost:                map = ("eye.slash", .gray)
    case .chatCamera:               map = ("camera.rotate.fill", .orange)
    case .messagingTextStyle:       map = ("textformat", .purple)
    case .messagingAutoText:        map = ("text.append", .teal)
    case .messagingAutoTranslate:   map = ("globe", .pink)
    case .messagingTranslateToggle: map = ("character.bubble.fill", .pink)
    case .messagingTranslateLang:   map = ("character.book.closed.fill", .lightBlue)
    case .sttEnabled:               map = ("mic.fill", .red)
    case .sttLanguage:              map = ("globe", .blue)
    case .protectionChatLock:       map = ("lock.shield.fill", .green)
    case .protectionProxy:          map = ("network.badge.shield.half.filled", .green)
    case .protectionForeign:        map = ("person.crop.circle.badge.xmark", .orange)
    default:                        map = nil
    }
    guard let (symbol, color) = map else { return nil }
    return fenixuzSettingsIcon(systemName: symbol, color: color)
}

private enum FenixuzEntry: Comparable, Identifiable {
    case section(Int)
    case header(Int, FenixuzEntryId, String)
    case toggle(Int, FenixuzEntryId, String, String?, Bool, GeneralViewType, String /* defaultsKey */)
    case chatLockToggle(Int, FenixuzEntryId, String, String?, Bool, GeneralViewType)
    case novagramProxyToggle(Int, FenixuzEntryId, String, String?, Bool, GeneralViewType)
    case disclosurePlaceholder(Int, FenixuzEntryId, String, String, GeneralViewType, String /* subKey */)
    case disclosureSTTLanguage(Int, FenixuzEntryId, String, String, GeneralViewType)
    case footer(Int, FenixuzEntryId, String)

    var stableId: AnyHashable {
        switch self {
        case let .section(id):                       return FenixuzEntryId.section(id)
        case let .header(_, id, _):                  return id
        case let .toggle(_, id, _, _, _, _, _):      return id
        case let .chatLockToggle(_, id, _, _, _, _): return id
        case let .novagramProxyToggle(_, id, _, _, _, _): return id
        case let .disclosurePlaceholder(_, id, _, _, _, _): return id
        case let .disclosureSTTLanguage(_, id, _, _, _): return id
        case let .footer(_, id, _):                  return id
        }
    }

    var sortIndex: Int {
        switch self {
        case let .section(id): return id * 1000
        case let .header(idx, _, _): return idx
        case let .toggle(idx, _, _, _, _, _, _): return idx
        case let .chatLockToggle(idx, _, _, _, _, _): return idx
        case let .novagramProxyToggle(idx, _, _, _, _, _): return idx
        case let .disclosurePlaceholder(idx, _, _, _, _, _): return idx
        case let .disclosureSTTLanguage(idx, _, _, _, _): return idx
        case let .footer(idx, _, _): return idx
        }
    }

    static func < (lhs: FenixuzEntry, rhs: FenixuzEntry) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    static func == (lhs: FenixuzEntry, rhs: FenixuzEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.section(l), .section(r)): return l == r
        case let (.header(l1, l2, l3), .header(r1, r2, r3)): return l1 == r1 && l2 == r2 && l3 == r3
        case let (.toggle(l1, l2, l3, l4, l5, l6, l7), .toggle(r1, r2, r3, r4, r5, r6, r7)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6 && l7 == r7
        case let (.chatLockToggle(l1, l2, l3, l4, l5, l6), .chatLockToggle(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6
        case let (.novagramProxyToggle(l1, l2, l3, l4, l5, l6), .novagramProxyToggle(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6
        case let (.disclosurePlaceholder(l1, l2, l3, l4, l5, l6), .disclosurePlaceholder(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6
        case let (.disclosureSTTLanguage(l1, l2, l3, l4, l5), .disclosureSTTLanguage(r1, r2, r3, r4, r5)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5
        case let (.footer(l1, l2, l3), .footer(r1, r2, r3)): return l1 == r1 && l2 == r2 && l3 == r3
        default: return false
        }
    }

    func item(_ arguments: FenixuzSettingsArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        case let .header(_, _, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textTopItem)
        case let .toggle(_, entryId, title, subtitle, value, viewType, key):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: fenixuzSettingsRowIcon(entryId),
                description: subtitle,
                type: .switchable(value),
                viewType: viewType,
                action: {
                    arguments.updateBool(key, !value)
                }
            )
        case let .chatLockToggle(_, entryId, title, subtitle, value, viewType):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: fenixuzSettingsRowIcon(entryId),
                description: subtitle,
                type: .switchable(value),
                viewType: viewType,
                action: {
                    arguments.updateChatLockMaster(!value)
                },
                // The row's true value comes from the keychain and only flips on sheet success.
                // Without autoswitch:false the switch optimistically snaps ON on tap and, if the
                // user dismisses the Set-Pincode sheet with X, never reconciles back to OFF.
                autoswitch: false
            )
        case let .novagramProxyToggle(_, entryId, title, subtitle, value, viewType):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: fenixuzSettingsRowIcon(entryId),
                description: subtitle,
                type: .switchable(value),
                viewType: viewType,
                action: {
                    arguments.updateNovagramProxy(!value)
                }
            )
        case let .disclosurePlaceholder(_, entryId, title, label, viewType, subKey):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: fenixuzSettingsRowIcon(entryId),
                type: .nextContext(label),
                viewType: viewType,
                action: {
                    arguments.openSubController(subKey)
                }
            )
        case let .disclosureSTTLanguage(_, entryId, title, label, viewType):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: fenixuzSettingsRowIcon(entryId),
                type: .nextContext(label),
                viewType: viewType,
                action: {
                    arguments.pickSTTLanguage()
                }
            )
        case let .footer(_, _, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textBottomItem)
        }
    }
}

private func fenixuzSettingsEntries(state: FenixuzSettingsState, l10n: FenixuzL10n) -> [FenixuzEntry] {
    var entries: [FenixuzEntry] = []
    var idx = 0

    func next() -> Int { idx += 1; return idx }
    var sectionId = 0

    // ─── FENIX PRO (top) ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.disclosurePlaceholder(next(), .topAbout, l10n.about_rowTitle, "", .firstItem, "about"))
    entries.append(.disclosurePlaceholder(next(), .topBots, l10n.bots_rowTitle, "", .lastItem, "bots"))

    // ─── INTERFACE ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(1), l10n.settings_section_interface))
    entries.append(.toggle(next(), .interfaceHideFolders, l10n.settings_interface_hideFolders_title, l10n.settings_interface_hideFolders_subtitle, state.hideFolders, .firstItem, FenixuzDefaultsKey.hideFolders))
    entries.append(.toggle(next(), .interfaceStories, l10n.settings_interface_stories_title, l10n.settings_interface_stories_subtitle, state.showStories, .innerItem, FenixuzDefaultsKey.showStories))
    entries.append(.toggle(next(), .interfaceMutual, l10n.settings_interface_mutualSymbol_title, l10n.settings_interface_mutualSymbol_subtitle, state.showMutualContactSymbol, .lastItem, FenixuzDefaultsKey.showMutualContactSymbol))
    entries.append(.footer(next(), .interfaceFooter, l10n.settings_interface_footer))

    // ─── CHAT ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(2), l10n.settings_section_chat))
    entries.append(.toggle(next(), .chatDeleted, l10n.settings_chat_deletedMessages_title, nil, state.showDeletedMessages, .firstItem, FenixuzDefaultsKey.showDeletedMessages))
    entries.append(.toggle(next(), .chatFirstMessage, l10n.settings_chat_firstMessage_title, nil, state.showViewFirstMessage, .innerItem, FenixuzDefaultsKey.showViewFirstMessage))
    entries.append(.toggle(next(), .chatGhostActive, l10n.settings_chat_ghostActive_title, l10n.settings_chat_ghostActive_subtitle, state.ghostModeActive, .innerItem, FenixuzDefaultsKey.ghostModeActive))
    entries.append(.toggle(next(), .chatGhost, l10n.settings_chat_ghost_title, nil, state.showGhostMode, .innerItem, FenixuzDefaultsKey.showGhostMode))
    entries.append(.toggle(next(), .chatCamera, l10n.settings_chat_camera_title, l10n.settings_chat_camera_subtitle, state.longPressCameraSelection, .lastItem, FenixuzDefaultsKey.longPressCameraSelection))
    entries.append(.footer(next(), .chatFooter, l10n.settings_chat_footer))

    // ─── MESSAGES ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(3), l10n.settings_section_messaging))
    entries.append(.disclosurePlaceholder(next(), .messagingTextStyle, l10n.settings_messaging_textStyle_title, l10n.textStyle_displayName(state.textStyle), .firstItem, "text_style"))
    let autoLabel = state.autoTextEnabled ? l10n.settings_state_enabled : l10n.settings_state_disabled
    entries.append(.disclosurePlaceholder(next(), .messagingAutoText, l10n.settings_messaging_autoText_title, autoLabel, .innerItem, "auto_text"))
    let trLabel = state.autoTranslateEnabled ? l10n.settings_state_enabled : l10n.settings_state_disabled
    entries.append(.disclosurePlaceholder(next(), .messagingAutoTranslate, l10n.settings_messaging_autoTranslate_title, trLabel, .innerItem, "auto_translate"))
    entries.append(.toggle(next(), .messagingTranslateToggle, l10n.settings_messaging_translateToggle_title, l10n.settings_messaging_translateToggle_subtitle, state.showTranslateMessages, .innerItem, FenixuzDefaultsKey.showTranslateMessages))
    entries.append(.disclosurePlaceholder(next(), .messagingTranslateLang, l10n.settings_messaging_translateLanguage_title, "", .lastItem, "translate_language"))
    entries.append(.footer(next(), .messagingFooter, l10n.settings_messaging_footer))

    // ─── VOICE → TEXT ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(4), l10n.settings_section_voice))
    entries.append(.toggle(next(), .sttEnabled, l10n.settings_voice_stt_title, l10n.settings_voice_stt_subtitle, state.sttEnabled, .firstItem, FenixuzDefaultsKey.sttEnabled))
    entries.append(.disclosureSTTLanguage(next(), .sttLanguage, l10n.settings_voice_sttLang_title, FenixuzL10n.sttLanguageName(for: state.sttLanguage), .lastItem))

    // ─── PROTECTION ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(5), l10n.settings_section_protection))
    entries.append(.chatLockToggle(next(), .protectionChatLock, l10n.chatLock_settingsTitle, l10n.chatLock_settingsSubtitle, state.chatLockMasterEnabled, .firstItem))
    entries.append(.novagramProxyToggle(next(), .protectionProxy, FenixuzAutoProxyStrings.toggleTitle(langCode: appCurrentLanguage.languageCode), FenixuzAutoProxyStrings.toggleTip(langCode: appCurrentLanguage.languageCode), state.novagramProxyEnabled, .innerItem))
    entries.append(.toggle(next(), .protectionForeign, l10n.settings_protection_foreign_title, l10n.settings_protection_foreign_subtitle, state.blockForeignUsers, .lastItem, FenixuzDefaultsKey.blockForeignUsers))
    entries.append(.footer(next(), .protectionFooter, l10n.settings_protection_footer))

    // trailing spacer
    entries.append(.section(sectionId))

    return entries
}

// MARK: - Transition

private func prepareFenixuzTransition(left: [AppearanceWrapperEntry<FenixuzEntry>], right: [AppearanceWrapperEntry<FenixuzEntry>], arguments: FenixuzSettingsArguments, initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

// MARK: - Controller

class FenixuzSettingsController: TableViewController {

    private let disposable = MetaDisposable()
    private let statePromise = ValuePromise(FenixuzSettingsState.load(), ignoreRepeated: true)
    private let stateValue = Atomic(value: FenixuzSettingsState.load())

    override var defaultBarTitle: String {
        return FenixuzL10n.current.settings_title
    }

    override var removeAfterDisapper: Bool {
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let context = self.context
        let window = context.window

        let updateState: ((inout FenixuzSettingsState) -> Void) -> Void = { [weak self] mutate in
            guard let self = self else { return }
            let new = self.stateValue.modify { current in
                var s = current
                mutate(&s)
                return s
            }
            self.statePromise.set(new)
        }

        let arguments = FenixuzSettingsArguments(
            context: context,
            updateBool: { key, value in
                if key == FenixuzDefaultsKey.ghostModeActive {
                    FenixuzGhostMode.isActive = value
                } else {
                    fenixuzDefaults?.set(value, forKey: key)
                }
                updateState { state in
                    switch key {
                    case FenixuzDefaultsKey.hideFolders: state.hideFolders = value
                    case FenixuzDefaultsKey.showStories: state.showStories = value
                    case FenixuzDefaultsKey.showMutualContactSymbol: state.showMutualContactSymbol = value
                    case FenixuzDefaultsKey.showDeletedMessages: state.showDeletedMessages = value
                    case FenixuzDefaultsKey.showViewFirstMessage: state.showViewFirstMessage = value
                    case FenixuzDefaultsKey.showGhostMode: state.showGhostMode = value
                    case FenixuzDefaultsKey.ghostModeActive: state.ghostModeActive = value
                    case FenixuzDefaultsKey.longPressCameraSelection: state.longPressCameraSelection = value
                    case FenixuzDefaultsKey.showTranslateMessages: state.showTranslateMessages = value
                    case FenixuzDefaultsKey.sttEnabled: state.sttEnabled = value
                    case FenixuzDefaultsKey.blockForeignUsers: state.blockForeignUsers = value
                    default: break
                    }
                }
                NotificationCenter.default.post(name: NSNotification.Name("FenixSettingsChanged"), object: nil)
            },
            pickSTTLanguage: { [weak self] in
                guard let self = self else { return }
                let current = self.stateValue.with { $0.sttLanguage }
                self.presentSTTLanguagePicker(currentId: current, window: window) { newId in
                    fenixuzDefaults?.set(newId, forKey: FenixuzDefaultsKey.sttLanguage)
                    updateState { state in
                        state.sttLanguage = newId
                    }
                }
            },
            openSubController: { [weak self] subKey in
                // Wave 5 — AppKit ports of the iOS ItemListController screens.
                // Each push lands on a TableViewController that mirrors the iOS
                // controller for the same key.
                guard let self = self else { return }
                let nav = self.navigationController
                switch subKey {
                case "about":
                    nav?.push(FenixuzAboutController(context))
                case "bots":
                    nav?.push(NovagramBotsController(context))
                case "tips":
                    nav?.push(FenixuzTipsController(context))
                case "text_style":
                    nav?.push(FenixuzTextStyleController(context))
                case "auto_text":
                    nav?.push(FenixuzAutoTextController(context))
                case "auto_translate":
                    nav?.push(FenixuzAutoTranslateController(context))
                case "translate_language":
                    nav?.push(FenixuzTranslationLanguageController(context))
                default:
                    let l10n = FenixuzL10n.current
                    alert(for: window, header: l10n.sub_comingSoon_title, info: l10n.sub_comingSoon_message)
                }
            },
            updateChatLockMaster: { enable in
                // #46: master is keychain-backed; the row value comes from isMasterEnabled(),
                // so a cancelled setup reconciles back to OFF on the next state emit.
                if enable {
                    FenixuzChatPincode.presentSet(for: window) { code in
                        FenixuzChatPincodeManager.shared.setMasterPincode(code)
                        updateState { $0.chatLockMasterEnabled = true }
                    }
                } else {
                    // #46: require the master pincode to turn Chat Lock off (mirrors iOS/web) — a confirm-only
                    // OFF would let anyone with the unlocked app disable the gate and unlock every chat.
                    FenixuzChatPincode.presentVerify(for: window,
                        verify: { FenixuzChatPincodeManager.shared.verifyMaster($0) },
                        onSuccess: {
                            FenixuzChatPincodeManager.shared.disableChatLock()
                            updateState { $0.chatLockMasterEnabled = false }
                        })
                }
            },
            updateNovagramProxy: { enable in
                FenixuzAutoProxyManager.shared.setEnabled(enable, accountManager: context.sharedContext.accountManager)
                updateState { $0.novagramProxyEnabled = enable }
            }
        )

        let initialSize = self.atomicSize
        let previousEntries = Atomic<[AppearanceWrapperEntry<FenixuzEntry>]>(value: [])

        let signal = combineLatest(queue: prepareQueue, statePromise.get(), appearanceSignal)
            |> map { state, appearance -> TableUpdateTransition in
                let l10n = FenixuzL10n(languageCode: appCurrentLanguage.languageCode)
                let entries = fenixuzSettingsEntries(state: state, l10n: l10n)
                    .map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let previous = previousEntries.swap(entries)
                return prepareFenixuzTransition(left: previous, right: entries, arguments: arguments, initialSize: initialSize.modify { $0 })
            }
            |> deliverOnMainQueue

        disposable.set(signal.start(next: { [weak self] transition in
            self?.genericView.merge(with: transition)
            self?.readyOnce()
        }))
    }

    // STT language picker — minimal NSMenu (avoids pulling in extra ActionSheet machinery).
    private func presentSTTLanguagePicker(currentId: String, window: Window, apply: @escaping (String) -> Void) {
        let menu = ContextMenu()
        for (id, name) in FenixuzL10n.sttSupportedLanguages {
            let title = id == currentId ? "✓ \(name)" : "    \(name)"
            menu.addItem(ContextMenuItem(title, handler: {
                apply(id)
            }))
        }
        if let event = NSApp.currentEvent {
            ContextMenu.show(items: menu.contextItems, view: window.contentView ?? NSView(), event: event)
        }
    }

    deinit {
        disposable.dispose()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
}
