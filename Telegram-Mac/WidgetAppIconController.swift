//
//  WidgetAppIconController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 12.09.2024.
//  Copyright © 2024 Telegram. All rights reserved.
//

import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Dock

final class WidgetAppIconContainer: View {

    private var item: DockIconRowItem?
    private let itemView: DockIconRowView = .init(frame: .zero)

    var selectIcon: ((FenixuzAppIcon) -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(itemView)
    }

    override func layout() {
        super.layout()
        itemView.frame = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(dockItems: [FenixuzAppIcon], settings: DockSettings, animated: Bool, context: AccountContext) {
        let item = DockIconRowItem(frame.size, stableId: 0, viewType: .modern(position: .single, insets: .init()), context: context, dockIcons: dockItems, selected: settings.iconSelected, action: { [weak self] icon in
            self?.selectIcon?(icon)
        }, insets: .init(left: 10))
        self.item = item
        itemView.set(item: item, animated: animated)
    }
}

final class WidgetAppIconController: TelegramGenericViewController<WidgetView<WidgetAppIconContainer>> {
    private let disposable = DisposableSet()
    override init(_ context: AccountContext) {
        super.init(context)
        self.bar = .init(height: 0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.genericView.dataView = WidgetAppIconContainer(frame: .zero)

        let context = self.context

        // Fenixuz: barcha iconlar Free — premium gate yo'q.
        self.genericView.dataView?.selectIcon = { icon in
            FenixuzAppIcons.apply(icon)
            _ = updateDockSettings(accountManager: context.sharedContext.accountManager, { settings in
                return settings.withUpdatedIcon(icon.isDefault ? nil : icon.name)
            }).startStandalone()
        }

        struct State: Equatable {
            var dockItems: [FenixuzAppIcon] = FenixuzAppIcons.all
            var shuffled: [FenixuzAppIcon] = []
            var settings: DockSettings = .defaultSettings

            mutating func shuffle() {
                if !dockItems.isEmpty {
                    self.shuffled = [dockItems[0]] + Array(dockItems.suffix(dockItems.count - 1).shuffled().prefix(min(7, dockItems.count - 1)))
                }
            }
        }

        let initialState = State()

        let statePromise = ValuePromise<State>(ignoreRepeated: true)
        let stateValue = Atomic(value: initialState)
        let updateState: ((State) -> State) -> Void = { f in
            statePromise.set(stateValue.modify(f))
        }

        disposable.add((dockSettings(accountManager: context.sharedContext.accountManager) |> deliverOnMainQueue).startStrict(next: { settings in
            updateState { current in
                var current = current
                current.dockItems = FenixuzAppIcons.all
                current.settings = settings
                if current.shuffled.isEmpty {
                    current.shuffle()
                }
                return current
            }
        }))

        disposable.add((statePromise.get() |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            self?.genericView.dataView?.update(dockItems: state.shuffled, settings: state.settings, animated: true, context: context)

            self?.genericView.update(.init(title: { strings().emptyChatAppIcon }, desc: { strings().emptyChatAppIconDesc }, descClick: {
                context.bindings.rootNavigation().push(AppAppearanceViewController(context: context))
            }, buttons: [.init(text: { strings().emptyChatAppIconShuffle }, selected: { false }, image: { theme.icons.widget_peers_favorite }, click: {
                updateState { current in
                    var current = current
                    current.shuffle()
                    return current
                }
            })]))

            self?.readyOnce()
        }))
    }

    deinit {
        disposable.dispose()
    }
}
