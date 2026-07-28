//
//  DockControl.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 25.01.2024.
//  Copyright © 2024 Telegram. All rights reserved.
//

import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import InAppSettings
import Dock

// MARK: - Fenixuz local app icons
// Bizning brend iconlar. Rasmiy Telegram server iconlari (@macos_app_icons) o'rniga
// app bundle'dagi Assets.xcassets/FenixuzAppIcons/*.dataset dan o'qiladi. Hammasi Free —
// premium gate yo'q.

struct FenixuzAppIcon: Equatable {
    let name: String        // DockSettings.iconSelected uchun kalit
    let assetName: String   // NSDataAsset nomi (preview + .icns manbasi)
    let isDefault: Bool     // default = custom icon tozalanadi (bundle AppIcon ishlatiladi)
}

enum FenixuzAppIcons {
    static let defaultName = "Default"

    static let all: [FenixuzAppIcon] = [
        .init(name: "Default", assetName: "FenixuzIcon_RedWhite", isDefault: true),
        .init(name: "GreenWhite", assetName: "FenixuzIcon_GreenWhite", isDefault: false),
        .init(name: "WhiteRed", assetName: "FenixuzIcon_WhiteRed", isDefault: false),
        .init(name: "WhiteGreen", assetName: "FenixuzIcon_WhiteGreen", isDefault: false),
        .init(name: "RedDark", assetName: "FenixuzIcon_RedDark", isDefault: false),
        .init(name: "GreenDark", assetName: "FenixuzIcon_GreenDark", isDefault: false),
        .init(name: "WhiteBlue", assetName: "FenixuzIcon_WhiteBlue", isDefault: false),
        .init(name: "WhiteGraphite", assetName: "FenixuzIcon_WhiteGraphite", isDefault: false)
    ]

    static func icon(forSelected selected: String?) -> FenixuzAppIcon {
        if let selected, let match = all.first(where: { $0.name == selected }) {
            return match
        }
        return all[0]
    }

    static func previewImage(_ icon: FenixuzAppIcon) -> NSImage? {
        guard let asset = NSDataAsset(name: icon.assetName) else { return nil }
        return NSImage(data: asset.data)
    }

    private static var cacheDir: String {
        let dir = NSTemporaryDirectory() + "FenixuzAppIcons"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    // .icns ni diskka yozib yo'lini qaytaradi. Default icon uchun nil — bu holda
    // setCustomAppIcon custom iconni tozalaydi va bundle AppIcon qaytadi.
    static func icnsPath(_ icon: FenixuzAppIcon) -> String? {
        if icon.isDefault { return nil }
        guard let asset = NSDataAsset(name: icon.assetName) else { return nil }
        let path = cacheDir + "/" + icon.assetName + ".icns"
        if !FileManager.default.fileExists(atPath: path) {
            try? asset.data.write(to: URL(fileURLWithPath: path))
        }
        return path
    }

    static func apply(_ icon: FenixuzAppIcon, silence: Bool = false) {
        Dock.setCustomAppIcon(path: icnsPath(icon), silence: silence)
    }
}

// MARK: - Launch re-apply

final class DockControl {

    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let update = MetaDisposable()

    init(_ engine: TelegramEngine, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.accountManager = accountManager
        reapplyOnLaunch()
    }

    // Custom app-icon picker olib tashlandi — har doim bundle Novagram AppIcon ishlatiladi.
    private func reapplyOnLaunch() {
        // Oldingi build qo'llagan custom iconni tozalaymiz (Icon\r resource fork'ni olib tashlaydi),
        // shunda eski icon tanlagan foydalanuvchilar ham launch'da bundle Novagram icon'ga qaytadi.
        Dock.setCustomAppIcon(path: nil, silence: true)
    }

    func clear() {
        update.dispose()
    }

    deinit {
        clear()
    }
}
