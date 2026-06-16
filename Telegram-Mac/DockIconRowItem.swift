//
//  DockIconRowItem.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 24.01.2024.
//  Copyright © 2024 Telegram. All rights reserved.
//

import Foundation
import TGUIKit

struct DockIconData {
    let icon: FenixuzAppIcon
    let selected: Bool
    let frame: NSRect
}

final class DockIconRowItem: GeneralRowItem {
    let icons: [DockIconData]
    let context: AccountContext
    let callback: (FenixuzAppIcon) -> Void
    init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, context: AccountContext, dockIcons: [FenixuzAppIcon], selected: String?, action: @escaping (FenixuzAppIcon) -> Void, insets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)) {
        self.context = context
        self.callback = action

        // even grid: equal gaps between icons and equal padding around them
        let pad = DockIconRowItem.padding
        let stepX = DockIconRowItem.iconSize.width + DockIconRowItem.spacing
        let stepY = DockIconRowItem.iconSize.height + DockIconRowItem.spacing
        let perRow = Int(DockIconRowItem.rowCount)

        var icons: [DockIconData] = []
        for (i, icon) in dockIcons.enumerated() {
            let col = i % perRow
            let row = i / perRow
            let isSelected = (selected == icon.name) || (icon.isDefault && selected == nil)
            let frame = CGRect(origin: CGPoint(x: pad + CGFloat(col) * stepX, y: pad + CGFloat(row) * stepY), size: DockIconRowItem.iconSize)
            icons.append(DockIconData(icon: icon, selected: isSelected, frame: frame))
        }

        self.icons = icons

        super.init(initialSize, stableId: stableId, viewType: viewType, inset: insets)
    }

    override func viewClass() -> AnyClass {
        return DockIconRowView.self
    }

    var containerSize: NSSize {
        let perRow = DockIconRowItem.rowCount
        let rows = max(1, ceil(CGFloat(icons.count) / perRow))
        let width = perRow * DockIconRowItem.iconSize.width + (perRow - 1) * DockIconRowItem.spacing + DockIconRowItem.padding * 2
        let height = rows * DockIconRowItem.iconSize.height + (rows - 1) * DockIconRowItem.spacing + DockIconRowItem.padding * 2
        return NSSize(width: width, height: height)
    }

    static var iconSize: NSSize {
        return NSSize(width: 54, height: 54)
    }
    static var rowCount: CGFloat {
        return 4.0
    }
    static var spacing: CGFloat {
        return 12.0
    }
    static var padding: CGFloat {
        return 14.0
    }

    override var height: CGFloat {
        return containerSize.height + 40
    }
}

private final class DockIconView: Control {

    private let content = SimpleLayer()
    private let selected = SimpleLayer()

    private var item: DockIconData?
    private weak var rowItem: DockIconRowItem?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scaleOnClick = true
        content.frame = CGRect(origin: .zero, size: DockIconRowItem.iconSize)
        content.contentsGravity = .resizeAspect
        self.layer?.addSublayer(content)
        self.layer?.addSublayer(selected)

        selected.frame = NSRect(x: 0, y: 0, width: 4, height: 4)
        selected.cornerRadius = selected.frame.height / 2.0
        selected.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor

        set(handler: { [weak self] _ in
            if let rowItem = self?.rowItem, let item = self?.item {
                rowItem.callback(item.icon)
            }
        }, for: .Click)

        self.layer?.masksToBounds = false
    }

    override func layout() {
        super.layout()
        // center the selection dot in the gap just below the icon tile
        let dotInset = floor((DockIconRowItem.spacing - selected.frame.height) / 2)
        self.selected.frame = CGRect(origin: NSPoint(x: (frame.width - selected.frame.width) / 2, y: content.frame.maxY + dotInset), size: selected.frame.size)
    }

    func set(item: DockIconData, rowItem: DockIconRowItem, animated: Bool) {
        if self.item?.icon != item.icon {
            self.content.contents = FenixuzAppIcons.previewImage(item.icon)?._cgImage
            self.content.animateContents()
        }
        self.item = item
        self.rowItem = rowItem
        self.userInteractionEnabled = true
        self.selected.opacity = item.selected ? 1.0 : 0.0
        self.selected.animateOpacity()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class Container: NSVisualEffectView {
    override var isFlipped: Bool {
        return true
    }
}

final class DockIconRowView: GeneralContainableRowView {
    private let backgroundView = BackgroundView(frame: .zero)
    private let visualEffect = Container()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(visualEffect)

        visualEffect.wantsLayer = true
        visualEffect.state = .active
        visualEffect.blendingMode = .withinWindow
        visualEffect.autoresizingMask = []
        visualEffect.material = .light

        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.borderWidth = 1

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard let item = item as? DockIconRowItem else {
            return
        }
        backgroundView.frame = containerView.bounds
        visualEffect.frame = containerView.focus(item.containerSize)
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? DockIconRowItem else {
            return
        }

        while visualEffect.subviews.count > item.icons.count {
            visualEffect.subviews.last?.removeFromSuperview()
        }
        while visualEffect.subviews.count < item.icons.count {
            let iconView = DockIconView(frame: DockIconRowItem.iconSize.bounds)
            visualEffect.addSubview(iconView)
        }

        for (i, icon) in item.icons.enumerated() {
            let view = visualEffect.subviews[i] as! DockIconView
            view.set(item: icon, rowItem: item, animated: animated)
            view.frame = icon.frame
        }

        backgroundView.backgroundMode = theme.backgroundMode

        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        needsLayout = true
    }
}
