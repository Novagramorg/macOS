//
//  Auth_BotToken.swift
//  Telegram
//
//  Novagram fork — log in as a bot with a BotFather token.
//  Structural clone of Auth_PasswordEntry.swift (single field + Next), with the secure
//  field swapped for a plain monospaced one.
//

import Foundation
import TGUIKit
import AppKit
import TelegramCore
import TelegramMedia
import FenixuzCore

private final class Auth_BotTokenHeaderView: View {
    private let playerView: LottiePlayerView = LottiePlayerView()
    private let header: TextView = TextView()
    private let desc: TextView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(playerView)
        addSubview(header)
        addSubview(desc)
        header.userInteractionEnabled = false
        header.isSelectable = false

        desc.userInteractionEnabled = false
        desc.isSelectable = false

        updateLocalizationAndTheme(theme: theme)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme

        if let data = LocalAnimatedSticker.business_chatbot.data {
            self.playerView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("business_chatbot"), size: Auth_Insets.logoSize, backingScale: Int(System.backingScale), fitzModifier: nil, colors: []), playPolicy: .onceEnd))
        }

        let layout = TextViewLayout(.initialize(string: FenixuzL10n.current.botlogin_title, color: theme.colors.text, font: Auth_Insets.headerFont))
        layout.measure(width: frame.width)
        self.header.update(layout)

        let descAttr: NSAttributedString = .initialize(string: FenixuzL10n.current.botlogin_info, color: theme.colors.grayText, font: Auth_Insets.infoFont)

        let descLayout = TextViewLayout(descAttr, alignment: .center)
        // Wider wrap than the password screen: this caveat runs three lines, not one.
        descLayout.measure(width: frame.width - 40)
        self.desc.update(descLayout)

        self.layout()
    }

    override func layout() {
        super.layout()
        self.playerView.setFrameSize(Auth_Insets.logoSize)
        self.playerView.centerX(y: 0)
        self.header.centerX(y: self.playerView.frame.maxY + 20)
        self.desc.centerX(y: self.header.frame.maxY + 10)
    }

    var height: CGFloat {
        return self.desc.frame.maxY
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func playAnimation() {
        playerView.playAgain()
    }
}

// focusRingType is .none on the field (matching the other auth screens), so the container
// draws the focus state itself. Same responder-tracking trick the phone field uses.
private final class Auth_BotTokenField: NSTextField {
    var didUpdateResponder: (() -> Void)?

    var isFirstResponder: Bool = false
    override func becomeFirstResponder() -> Bool {
        isFirstResponder = true
        self.didUpdateResponder?()
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        isFirstResponder = false
        self.didUpdateResponder?()
        return super.resignFirstResponder()
    }
}

private final class Auth_BotTokenInputView: View, NSTextFieldDelegate {
    // Plain, not NSSecureTextField: a bot token is a machine credential the operator pastes
    // and proofreads. Masking would hide typos and offer irrelevant Keychain autofill.
    private let tokenField: Auth_BotTokenField = Auth_BotTokenField()
    private var takeError: (() -> Void)?
    private var invoke: (() -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(tokenField)
        tokenField.didUpdateResponder = { [weak self] in
            self?.updateBorder()
        }
        updateLocalizationAndTheme(theme: theme)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        background = theme.colors.grayBackground
        layer?.cornerRadius = 10

        tokenField.font = .code(.title)
        tokenField.textColor = theme.colors.text
        tokenField.drawsBackground = false
        tokenField.backgroundColor = .clear
        tokenField.focusRingType = .none
        tokenField.isBordered = false
        tokenField.isBezeled = false
        tokenField.usesSingleLineMode = true
        tokenField.delegate = self

        tokenField.placeholderAttributedString = .initialize(string: FenixuzL10n.current.botlogin_placeholder, color: theme.colors.grayText, font: .code(.text))

        updateBorder()
    }

    private func updateBorder() {
        layer?.borderWidth = .borderSize
        layer?.borderColor = tokenField.isFirstResponder ? FenixuzBrandColors.primary.cgColor : theme.colors.border.cgColor
        layer?.animateBorder()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            self.invoke?()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        self.takeError?()
    }

    func update(locked: Bool, invoke: @escaping () -> Void, takeError: @escaping () -> Void) {
        self.invoke = invoke
        self.takeError = takeError
        updateLocalizationAndTheme(theme: theme)
    }

    override func layout() {
        super.layout()
        tokenField.frame = NSRect(x: 10, y: 10, width: frame.width - 20, height: 18)
    }

    func updateLocked(_ locked: Bool) {
        self.tokenField.textView?.isEditable = !locked
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func firstResponder() -> NSResponder? {
        if window?.firstResponder == tokenField.textView {
            return tokenField.textView
        }
        return tokenField
    }

    // Pasted tokens routinely carry a trailing newline.
    var value: String {
        return self.tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        return self.tokenField.stringValue.isEmpty
    }

    func prefill(_ token: String) {
        self.tokenField.stringValue = token
        // Select all so a keystroke or ⌘V instantly replaces the guess.
        self.tokenField.currentEditor()?.selectAll(nil)
    }
}

final class Auth_BotTokenView: View {
    private let container: View = View()
    private let header: Auth_BotTokenHeaderView
    private let input: Auth_BotTokenInputView
    private let hint: TextView = TextView()
    private let error: LoginErrorStateView = LoginErrorStateView()
    private let nextView = Auth_NextView()
    private let help: TextButton = TextButton()
    private let cancel: TextButton = TextButton()

    private var locked: Bool = false

    private var takeNext: ((String) -> Void)?
    private var takeCancel: (() -> Void)?

    required init(frame frameRect: NSRect) {
        header = Auth_BotTokenHeaderView(frame: frameRect.size.bounds)
        input = Auth_BotTokenInputView(frame: NSRect(x: 0, y: 0, width: 280, height: 40))
        super.init(frame: frameRect)
        container.addSubview(header)
        container.addSubview(input)
        container.addSubview(hint)
        container.addSubview(error)
        container.addSubview(nextView)
        container.addSubview(help)
        container.addSubview(cancel)

        hint.userInteractionEnabled = false
        hint.isSelectable = false

        addSubview(container)

        nextView.set(handler: { [weak self] _ in
            self?.invoke()
        }, for: .Click)

        // The docs page, not t.me/botfather — it never dead-ends someone without a client.
        help.set(handler: { _ in
            execute(inapp: .external(link: "https://core.telegram.org/bots#how-do-i-create-a-bot", false))
        }, for: .Click)

        cancel.set(handler: { [weak self] _ in
            self?.takeCancel?()
        }, for: .Click)

        help.scaleOnClick = true
        cancel.scaleOnClick = true

        updateLocalizationAndTheme(theme: theme)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        nextView.updateLocalizationAndTheme(theme: theme)

        let hintLayout = TextViewLayout(.initialize(string: FenixuzL10n.current.botlogin_hint, color: theme.colors.grayText, font: Auth_Insets.infoFont), alignment: .center)
        hintLayout.measure(width: frame.width - 40)
        hint.update(hintLayout)

        for button in [help, cancel] {
            button.set(font: Auth_Insets.infoFont, for: .Normal)
            button.set(color: theme.colors.accent, for: .Normal)
        }
        help.set(text: FenixuzL10n.current.botlogin_help, for: .Normal)
        cancel.set(text: strings().navigationCancel, for: .Normal)
        _ = help.sizeToFit()
        _ = cancel.sizeToFit()

        needsLayout = true
    }

    override func layout() {
        super.layout()
        container.setFrameSize(NSSize(width: frame.width, height: header.height + Auth_Insets.betweenHeader + input.frame.height + Auth_Insets.betweenNextView + Auth_Insets.nextHeight + Auth_Insets.betweenHeader + help.frame.height + 10 + cancel.frame.height))

        header.setFrameSize(NSSize(width: frame.width, height: header.height))
        header.centerX(y: 0)
        input.centerX(y: header.frame.maxY + Auth_Insets.betweenHeader)
        // hint and error share one slot and are mutually exclusive, so the stack never jumps.
        hint.centerX(y: input.frame.maxY + Auth_Insets.betweenError)
        error.centerX(y: input.frame.maxY + Auth_Insets.betweenError)
        nextView.centerX(y: input.frame.maxY + Auth_Insets.betweenNextView)
        help.centerX(y: nextView.frame.maxY + Auth_Insets.betweenHeader)
        cancel.centerX(y: help.frame.maxY + 10)
        container.center()
    }

    func invoke() {
        if !self.input.value.isEmpty, !locked {
            self.takeNext?(self.input.value)
        }
    }

    func firstResponder() -> NSResponder? {
        return input.firstResponder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(locked: Bool, error: ImportBotAuthorizationError?, takeNext: @escaping (String) -> Void, takeError: @escaping () -> Void, takeCancel: @escaping () -> Void) {
        self.input.update(locked: locked, invoke: { [weak self] in
            self?.invoke()
        }, takeError: takeError)
        self.takeNext = takeNext
        self.takeCancel = takeCancel
        self.locked = locked
        nextView.updateLocked(locked)
        self.input.updateLocked(locked)
        help.userInteractionEnabled = !locked
        cancel.userInteractionEnabled = !locked

        if let error = error {
            let text: String
            switch error {
            case .invalidToken:
                text = FenixuzL10n.current.botlogin_error_invalid
            case .limitExceeded:
                text = strings().loginFloodWait
            case .generic:
                text = FenixuzL10n.current.botlogin_error_generic
            }
            self.error.state.set(.error(text))
            self.hint.isHidden = true
            self.input.shake(beep: true)
        } else {
            self.error.state.set(.normal)
            self.hint.isHidden = false
        }
        needsLayout = true
    }

    // Lenient shape check for the one-shot clipboard prefill. Deliberately NOT a login
    // gate — the server is authoritative on token validity and no official regex exists.
    private static func looksLikeToken(_ candidate: String) -> Bool {
        let parts = candidate.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return false
        }
        let id = parts[0], secret = parts[1]
        guard id.count >= 5, id.allSatisfy({ $0.isNumber }) else {
            return false
        }
        guard secret.count >= 20 else {
            return false
        }
        return secret.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    // One read on appear — macOS has no paste-privacy banner, so a repeating changeCount
    // timer would buy nothing.
    func prefillFromPasteboardIfNeeded() {
        guard input.isEmpty else {
            return
        }
        guard let candidate = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), Auth_BotTokenView.looksLikeToken(candidate) else {
            return
        }
        input.prefill(candidate)
    }

    func playAnimation() {
        header.playAnimation()
    }
}

final class Auth_BotTokenController: GenericViewController<Auth_BotTokenView> {

    private var didPrefill: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }

    func update(locked: Bool, error: ImportBotAuthorizationError?, takeNext: @escaping (String) -> Void, takeError: @escaping () -> Void, takeCancel: @escaping () -> Void) {
        self.genericView.update(locked: locked, error: error, takeNext: takeNext, takeError: takeError, takeCancel: takeCancel)
    }

    override func firstResponder() -> NSResponder? {
        return genericView.firstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if animated {
            genericView.playAnimation()
        }
        if !didPrefill {
            didPrefill = true
            genericView.prefillFromPasteboardIfNeeded()
        }
    }
}
