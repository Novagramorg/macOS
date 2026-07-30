//
//  FenixuzChatExportSettings.swift
//  Telegram
//
//  Novagram: the "Chat export settings" sheet shown before an export starts.
//
//  Stage 2 scope — format picker (HTML / JSON / Both) and the destination path.
//  The media checkboxes and the size slider from the official sheet are left out
//  on purpose: media download lands in stage 3, and showing switches that do
//  nothing would be lying to the user. See EXPORT_PLAN.md.
//

import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import FenixuzCore

private struct ChatExportSettingsState: Equatable {
    var format: ChatExportFormat = .html
}

private let _id_format_html = InputDataIdentifier("chat_export_html")
private let _id_format_json = InputDataIdentifier("chat_export_json")
private let _id_format_both = InputDataIdentifier("chat_export_both")

private func entries(_ state: ChatExportSettingsState, arguments: ChatExportArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0
    let l10n = FenixuzL10n.current

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(l10n.chatExport_formatHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_format_html, data: InputDataGeneralData(name: l10n.chatExport_formatHTML, color: theme.colors.text, icon: nil, type: .selectable(state.format == .html), viewType: .firstItem, action: arguments.selectHTML)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_format_json, data: InputDataGeneralData(name: l10n.chatExport_formatJSON, color: theme.colors.text, icon: nil, type: .selectable(state.format == .json), viewType: .innerItem, action: arguments.selectJSON)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_format_both, data: InputDataGeneralData(name: l10n.chatExport_formatBoth, color: theme.colors.text, icon: nil, type: .selectable(state.format == .both), viewType: .lastItem, action: arguments.selectBoth)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(l10n.chatExport_pathHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(FenixuzChatExport.destinationDescription), data: .init(color: theme.colors.text, viewType: .singleItem)))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(l10n.chatExport_mediaNote), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

private final class ChatExportArguments {
    let selectHTML: () -> Void
    let selectJSON: () -> Void
    let selectBoth: () -> Void
    init(selectHTML: @escaping () -> Void, selectJSON: @escaping () -> Void, selectBoth: @escaping () -> Void) {
        self.selectHTML = selectHTML
        self.selectJSON = selectJSON
        self.selectBoth = selectBoth
    }
}

/// Presents the sheet; `onExport` fires with the chosen format when the user confirms.
func FenixuzChatExportSettingsController(context: AccountContext, onExport: @escaping (ChatExportFormat) -> Void) -> InputDataModalController {

    let statePromise = ValuePromise(ChatExportSettingsState(), ignoreRepeated: true)
    let stateValue = Atomic(value: ChatExportSettingsState())
    let updateState: ((ChatExportSettingsState) -> ChatExportSettingsState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let arguments = ChatExportArguments(selectHTML: {
        updateState { current in var current = current; current.format = .html; return current }
    }, selectJSON: {
        updateState { current in var current = current; current.format = .json; return current }
    }, selectBoth: {
        updateState { current in var current = current; current.format = .both; return current }
    })

    let signal = statePromise.get() |> map { state in
        return entries(state, arguments: arguments)
    }

    let controller = InputDataController(
        dataSignal: signal |> map { InputDataSignalValue(entries: $0, animated: true) },
        title: FenixuzL10n.current.chatExport_settingsTitle,
        removeAfterDisappear: true,
        hasDone: false,
        identifier: "chat-export-settings"
    )

    var close: (() -> Void)?

    let interactions = ModalInteractions(acceptTitle: FenixuzL10n.current.chatExport_action, accept: {
        let format = stateValue.with { $0.format }
        close?()
        onExport(format)
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: interactions, size: NSSize(width: 340, height: 300))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
