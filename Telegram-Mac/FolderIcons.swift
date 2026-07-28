//
//  FolderIcons.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 06/04/2020.
//  Copyright © 2020 Telegram. All rights reserved.
//

import Cocoa

enum FolderIconState {
    case sidebar
    case sidebarActive
    case preview
    case settings
    var color: NSColor {
        switch self {
        case .sidebar:
            return NSColor.white.withAlphaComponent(0.5)
        case .sidebarActive:
            // Novagram: official Telegram 12.9 tints the selected folder with the
            // accent colour, not plain white — it is the only coloured element in
            // the rail and is what makes the current folder readable at a glance.
            return theme.colors.accent
        case .preview:
            return theme.colors.grayIcon
        case .settings:
            return theme.colors.grayIcon
        }
    }
}

let allSidebarFolderIcons: [FolderIcon] = [FolderIcon(emoticon: .emoji("🐱")),
                                           FolderIcon(emoticon: .emoji("📕")),
                                           FolderIcon(emoticon: .emoji("💰")),
                                           FolderIcon(emoticon: .emoji("📸")),
                                           FolderIcon(emoticon: .emoji("🎮")),
                                           FolderIcon(emoticon: .emoji("🏡")),
                                           FolderIcon(emoticon: .emoji("💡")),
                                           FolderIcon(emoticon: .emoji("👍")),
                                           FolderIcon(emoticon: .emoji("🔒")),
                                           FolderIcon(emoticon: .emoji("❤️")),
                                           FolderIcon(emoticon: .emoji("➕")),
                                           FolderIcon(emoticon: .emoji("🎵")),
                                           FolderIcon(emoticon: .emoji("🎨")),
                                           FolderIcon(emoticon: .emoji("✈️")),
                                           FolderIcon(emoticon: .emoji("⚽️")),
                                           FolderIcon(emoticon: .emoji("⭐")),
                                           FolderIcon(emoticon: .emoji("🎓")),
                                           FolderIcon(emoticon: .emoji("🛫")),
                                           FolderIcon(emoticon: .emoji("👨‍💼")),
                                           FolderIcon(emoticon: .emoji("👤")),
                                           FolderIcon(emoticon: .emoji("👥")),
                                           // FolderIcon(emoticon: .emoji("📢")),
                                           FolderIcon(emoticon: .emoji("💬")),
                                           FolderIcon(emoticon: .emoji("✅")),
                                           FolderIcon(emoticon: .emoji("☑️")),
                                           FolderIcon(emoticon: .emoji("🤖")),
                                           FolderIcon(emoticon: .emoji("🗂"))]

enum FolderEmoticon {
    case emoji(String)
    case allChats
    case groups
    case read
    case personal
    case unmuted
    case unread
    case channels
    case bots
    case folder

    var emoji: String? {
        switch self {
        case let .emoji(emoji):
            return emoji
        case .allChats: return "💬"
        case .personal: return "👤"
        case .groups: return "👥"
        case .read: return "✅"
        case .unmuted: return "🔔"
        case .unread: return "☑️"
        case .channels: return "📢"
        case .bots: return "🤖"
        case .folder: return "🗂"
        }
    }

    var drawable: MenuAnimation {
        switch self {
        case .allChats:
            return .menu_folder_all_chats
        case .groups:
            return .menu_folder_group
        case .read:
            return .menu_folder_read
        case .unread:
            return .menu_folder_unread
        case .personal:
            return .menu_folder_personal
        case .unmuted:
            return .menu_unmuted
        case .channels:
            return .menu_channel
        case .bots:
            return .menu_folder_bot
        case .folder:
            return .menu_folder_folder
        case let .emoji(emoji):
            switch emoji {
            case "👤":
                return .menu_folder_personal
            case "👥":
                return .menu_folder_group
            case "📢":
                return .menu_channel
            case "💬":
                return .menu_folder_all_chats
            case "✅":
                return .menu_folder_read
            case "☑️":
                return .menu_folder_unread
            case "🔔":
                return .menu_unmuted
            case "🗂":
                return .menu_folder_folder
            case "🤖":
                return .menu_folder_bot
            case "🐶", "🐱":
                return .menu_folder_animal
            case "📕":
                return .menu_folder_book
            case "💰":
                return .menu_folder_coin
            case "📸":
                return .menu_folder_flash
            case "🎮":
                return .menu_folder_game
            case "🏡":
                return .menu_folder_home
            case "💡":
                return .menu_folder_lamp
            case "👍":
                return .menu_folder_like
            case "🔒":
                return .menu_folder_lock
            case "❤️":
                return .menu_folder_love
            case "➕":
                return .menu_folder_math
            case "🎵":
                return .menu_folder_music
            case "🎨":
                return .menu_folder_paint
            case "✈️":
                return .menu_folder_plane
            case "⚽️":
                return .menu_folder_sport
            case "⭐":
                return .menu_folder_star
            case "🎓":
                return .menu_folder_student
            case "🛫":
                return .menu_folder_telegram
            case "👨‍💼":
                return .menu_folder_work
            default:
                return .menu_folder_folder
            }
        }
    }

    var iconName: String {
        switch self {
        case .allChats:
            return "Icon_Sidebar_AllChats"
        case .groups:
            return "Icon_Sidebar_Group"
        case .read:
            return "Icon_Sidebar_Read"
        case .unread:
            return "Icon_Sidebar_Unread"
        case .personal:
            return "Icon_Sidebar_Personal"
        case .unmuted:
            return "Icon_Sidebar_Unmuted"
        case .channels:
            return "Icon_Sidebar_Channel"
        case .bots:
            return "Icon_Sidebar_Bot"
        case .folder:
            return "Icon_Sidebar_Folder"
        case let .emoji(emoji):
            switch emoji {
            case "👤":
                return "Icon_Sidebar_Personal"
            case "👥":
                return "Icon_Sidebar_Group"
            case "📢":
                return "Icon_Sidebar_Channel"
            case "💬":
                return "Icon_Sidebar_AllChats"
            case "✅":
                return "Icon_Sidebar_Read"
            case "☑️":
                return "Icon_Sidebar_Unread"
            case "🔔":
                return "Icon_Sidebar_Unmuted"
            case "🗂":
                return "Icon_Sidebar_Folder"
            case "🤖":
                return "Icon_Sidebar_Bot"
            case "🐶", "🐱":
                return "Icon_Sidebar_Animal"
            case "📕":
                return "Icon_Sidebar_Book"
            case "💰":
                return "Icon_Sidebar_Coin"
            case "📸":
                return "Icon_Sidebar_Flash"
            case "🎮":
                return "Icon_Sidebar_Game"
            case "🏡":
                return "Icon_Sidebar_Home"
            case "💡":
                return "Icon_Sidebar_Lamp"
            case "👍":
                return "Icon_Sidebar_Like"
            case "🔒":
                return "Icon_Sidebar_Lock"
            case "❤️":
                return "Icon_Sidebar_Love"
            case "➕":
                return "Icon_Sidebar_Math"
            case "🎵":
                return "Icon_Sidebar_Music"
            case "🎨":
                return "Icon_Sidebar_Paint"
            case "✈️":
                return "Icon_Sidebar_Plane"
            case "⚽️":
                return "Icon_Sidebar_Sport"
            case "⭐":
                return "Icon_Sidebar_Star"
            case "🎓":
                return "Icon_Sidebar_Student"
            case "🛫":
                return "Icon_Sidebar_Telegram"
            case "👨‍💼":
                return "Icon_Sidebar_Work"
            case "🍷":
                return "Icon_Sidebar_Wine"
            case "🎭":
                return "Icon_Sidebar_Mask"
            default:
                return "Icon_Sidebar_Folder"
            }
        }
    }
}

final class FolderIcon {
    let emoticon: FolderEmoticon

    init(emoticon: FolderEmoticon) {
        self.emoticon = emoticon
    }

    func icon(for state: FolderIconState) -> CGImage {
        return NSImage(named: self.emoticon.iconName)!.precomposed(state.color, flipVertical: state == .preview)
    }

}
