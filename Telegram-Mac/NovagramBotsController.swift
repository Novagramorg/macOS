//
//  NovagramBotsController.swift
//  Telegram-Mac
//
//  Novagram Bots — macOS port.
//
//  One entry in NovagramPro settings (FenixuzSettingsController) pushes this
//  TableViewController. Bots are grouped into 4 categories sourced from
//  novagram_bots.json (bundled resource — copy of the canonical JSON at
//  /Users/codingtech/Documents/Telegram/novagram_bots.json).
//
//  On tap each bot row resolves the @username via the existing
//  resolveUsername(username:context:) API (InAppLinks.swift:178) and opens
//  the chat with ChatAdditionController.
//

import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Localization
import FenixuzCore
import Postbox

// MARK: - JSON Codable models

private struct BotsManifest: Codable {
    let categories: [CategoryManifest]

    struct CategoryManifest: Codable {
        let id: String
        let title: LocalString
        let bots: [BotManifest]
    }

    struct LocalString: Codable {
        let en: String
        let uz: String
        let ru: String
    }

    struct BotManifest: Codable {
        let id: String
        let username: String
        let name: String
        let icon: String
        let emoji: String
        let color: String
        let help: LocalString
    }
}

// MARK: - Internal view-model types (Equatable for diff)

private struct BotDef: Equatable {
    let id: String
    let username: String
    let name: String
    let icon: String      // SF Symbol name
    let emoji: String     // fallback glyph when the SF Symbol is unavailable on this macOS
    let hexColor: String  // "#RRGGBB"
    let help: String      // localized for current language
}

private struct CategoryDef: Equatable {
    let id: String
    let title: String
    let bots: [BotDef]
}

// MARK: - Icon rendering

private func novagramBotIcon(systemName: String, emoji: String, hexColor: String) -> CGImage? {
    let size = NSSize(width: 30, height: 30)
    let bgColor = nsColorFromHex(hexColor)

    var whiteSymbol: NSImage?
    if #available(macOS 11.0, *),
       let base = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let symbol = base.withSymbolConfiguration(cfg) ?? base
        let sw = min(symbol.size.width, 20)
        let sh = min(symbol.size.height, 20)
        let s = NSImage(size: NSSize(width: sw, height: sh))
        s.lockFocus()
        symbol.draw(in: NSRect(x: 0, y: 0, width: sw, height: sh))
        NSColor.white.set()
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: sw, height: sh)).fill()
        s.unlockFocus()
        whiteSymbol = s
    }

    let image = NSImage(size: size)
    image.lockFocus()
    let bg = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 7, yRadius: 7)
    bgColor.setFill()
    bg.fill()
    if let ws = whiteSymbol {
        let rect = NSRect(
            x: (size.width - ws.size.width) / 2,
            y: (size.height - ws.size.height) / 2,
            width: ws.size.width,
            height: ws.size.height
        )
        ws.draw(in: rect)
    } else if !emoji.isEmpty {
        // SF Symbol bu macOS versiyasida yo'q — JSON'dagi emoji glyph'ga tushamiz.
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17)]
        let str = emoji as NSString
        let b = str.size(withAttributes: attrs)
        str.draw(at: NSPoint(x: (size.width - b.width) / 2, y: (size.height - b.height) / 2), withAttributes: attrs)
    }
    image.unlockFocus()
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

private func nsColorFromHex(_ hex: String) -> NSColor {
    let stripped = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard stripped.count == 6,
          let r = UInt8(stripped.prefix(2), radix: 16),
          let g = UInt8(stripped.dropFirst(2).prefix(2), radix: 16),
          let b = UInt8(stripped.dropFirst(4).prefix(2), radix: 16) else {
        return .systemBlue
    }
    return NSColor(
        red: CGFloat(r) / 255,
        green: CGFloat(g) / 255,
        blue: CGFloat(b) / 255,
        alpha: 1.0
    )
}

// MARK: - Arguments

private final class NovagramBotsArguments {
    let context: AccountContext
    let openBot: (String) -> Void   // username without @

    init(context: AccountContext, openBot: @escaping (String) -> Void) {
        self.context = context
        self.openBot = openBot
    }
}

// MARK: - Table entries

private enum NovagramBotsEntry: Comparable, Identifiable {
    case section(Int)
    case header(Int, String)
    case botRow(Int, BotDef, GeneralViewType)

    var stableId: AnyHashable {
        switch self {
        case let .section(i):        return "nbs_sec_\(i)"
        case let .header(i, _):      return "nbs_hdr_\(i)"
        case let .botRow(_, b, _):   return "nbs_bot_\(b.id)"
        }
    }
    var id: AnyHashable { stableId }

    var sortIndex: Int {
        switch self {
        case let .section(i):        return i
        case let .header(i, _):      return i
        case let .botRow(i, _, _):   return i
        }
    }

    static func < (lhs: NovagramBotsEntry, rhs: NovagramBotsEntry) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    static func == (lhs: NovagramBotsEntry, rhs: NovagramBotsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.section(a), .section(b)):
            return a == b
        case let (.header(ai, at), .header(bi, bt)):
            return ai == bi && at == bt
        case let (.botRow(ai, ab, av), .botRow(bi, bb, bv)):
            return ai == bi && ab == bb && av == bv
        default:
            return false
        }
    }

    func item(_ arguments: NovagramBotsArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)

        case let .header(_, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textTopItem)

        case let .botRow(_, bot, viewType):
            let icon = novagramBotIcon(systemName: bot.icon, emoji: bot.emoji, hexColor: bot.hexColor)
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: bot.name,
                icon: icon,
                description: bot.help,
                type: .next,
                viewType: viewType,
                action: {
                    arguments.openBot(bot.username)
                }
            )
        }
    }
}

// MARK: - Entry builder

private func novagramBotsEntries(categories: [CategoryDef]) -> [NovagramBotsEntry] {
    var entries: [NovagramBotsEntry] = []
    var idx = 0

    for category in categories {
        entries.append(.section(idx)); idx += 1
        entries.append(.header(idx, category.title)); idx += 1

        let bots = category.bots
        for (bi, bot) in bots.enumerated() {
            let viewType: GeneralViewType
            if bots.count == 1 {
                viewType = .singleItem
            } else if bi == 0 {
                viewType = .firstItem
            } else if bi == bots.count - 1 {
                viewType = .lastItem
            } else {
                viewType = .innerItem
            }
            entries.append(.botRow(idx, bot, viewType)); idx += 1
        }
    }
    entries.append(.section(idx))
    return entries
}

// MARK: - Transition

private func prepareBotsTransition(
    left: [AppearanceWrapperEntry<NovagramBotsEntry>],
    right: [AppearanceWrapperEntry<NovagramBotsEntry>],
    arguments: NovagramBotsArguments,
    initialSize: NSSize
) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry in
        entry.entry.item(arguments, initialSize: initialSize)
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

// MARK: - Controller

class NovagramBotsController: TableViewController {

    private let disposable = MetaDisposable()

    override var defaultBarTitle: String {
        return FenixuzL10n.current.bots_screenTitle
    }

    override var removeAfterDisapper: Bool {
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let context = self.context
        let window = context.window

        // open bot: resolve @username, then push ChatAdditionController.
        // Reuses resolveUsername(username:context:) from InAppLinks.swift:178.
        let arguments = NovagramBotsArguments(
            context: context,
            openBot: { [weak self] username in
                guard let self = self else { return }
                _ = showModalProgress(
                    signal: resolveUsername(username: username, context: context),
                    for: window
                ).start(next: { [weak self] peer in
                    guard let peer = peer else { return }
                    self?.navigationController?.push(
                        ChatAdditionController(
                            context: context,
                            chatLocation: .peer(peer.id),
                            initialAction: nil
                        )
                    )
                })
            }
        )

        let initialSize = self.atomicSize
        let previousEntries = Atomic<[AppearanceWrapperEntry<NovagramBotsEntry>]>(value: [])

        let signal = appearanceSignal
            |> map { appearance -> TableUpdateTransition in
                let lang = appCurrentLanguage.languageCode
                let cats = NovagramBotsController.loadCategories(languageCode: lang)
                let entries = novagramBotsEntries(categories: cats)
                    .map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let previous = previousEntries.swap(entries)
                return prepareBotsTransition(
                    left: previous, right: entries,
                    arguments: arguments,
                    initialSize: initialSize.modify { $0 }
                )
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

    // MARK: - JSON loading

    private static func loadCategories(languageCode: String) -> [CategoryDef] {
        guard let url = Bundle.main.url(forResource: "novagram_bots", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        guard let manifest = try? JSONDecoder().decode(BotsManifest.self, from: data) else {
            return []
        }
        return manifest.categories.map { cat in
            CategoryDef(
                id: cat.id,
                title: pick(cat.title, lang: languageCode),
                bots: cat.bots.map { bot in
                    BotDef(
                        id: bot.id,
                        username: bot.username,
                        name: bot.name,
                        icon: bot.icon,
                        emoji: bot.emoji,
                        hexColor: bot.color,
                        help: pick(bot.help, lang: languageCode)
                    )
                }
            )
        }
    }

    private static func pick(_ ls: BotsManifest.LocalString, lang: String) -> String {
        switch lang {
        case "uz": return ls.uz
        case "ru": return ls.ru
        default:   return ls.en
        }
    }
}
