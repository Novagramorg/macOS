//
//  FenixuzGhostMode.swift
//  Telegram-Mac
//
//  iOS portasi:
//    submodules/Fenixuz/.../TelegramCore/Sources/Fenixuz/FenixuzGhostMode.swift
//    + ChatListController ghost navbar button.
//
//  Ghost mode — xabarlarni o'qiganingni (read receipt), yozayotganingni (typing)
//  va onlayn holatingni (last-seen) serverga bildirmaslik. Holat `pro_messager`
//  suite'idagi `is_ghost_mode_active` kalitida saqlanadi (iOS bilan bir xil
//  kalit, shuning uchun bir xil sozlama-do'koni). UI shu helper orqali toggle
//  qiladi; suppression hook'lari `isActive`ni o'qiydi.
//
//  Demo emas — har bir foydalanuvchi uchun ishlaydi.
//

import Foundation

public enum FenixuzGhostMode {
    private static let suiteName = "pro_messager"
    private static let activeKey = "is_ghost_mode_active"
    private static let buttonKey = "show_ghost_mode_button"

    /// Ghost holati o'zgarganda yuboriladi (toolbar tugmasi + suppression hook'lari eshitadi).
    public static let didChangeNotification = Notification.Name("FenixuzGhostModeDidChange")

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    /// Ghost rejimi yoniqmi — haqiqiy holat. Suppression hook'lari shuni o'qiydi.
    public static var isActive: Bool {
        get { defaults?.bool(forKey: activeKey) ?? false }
        set {
            guard newValue != isActive else { return }
            defaults?.set(newValue, forKey: activeKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
            // Settings paneli ham eshitadi (toggle/tugma holati yangilanadi).
            NotificationCenter.default.post(name: Notification.Name("FenixSettingsChanged"), object: nil)
        }
    }

    /// Chatlar ro'yxati tepasidagi tezkor Ghost tugmasi ko'rinadimi
    /// (Settings → FenixuzPro → "Ghost mode button" toggle'i bilan boshqariladi).
    public static var isButtonVisible: Bool {
        defaults?.bool(forKey: buttonKey) ?? false
    }

    @discardableResult
    public static func toggle() -> Bool {
        isActive.toggle()
        return isActive
    }
}
