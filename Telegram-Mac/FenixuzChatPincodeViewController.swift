//
//  FenixuzChatPincodeViewController.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Fenixuz/ChatLock/Sources/ChatPincodeViewController.swift
//
//  4-digit pincode entry sheet. Three modes:
//    - .set    — user picks a new pincode (asks twice — confirm)
//    - .verify — gate before unlocking a chat
//    - .remove — verify before deleting the pincode
//
//  Mac AppKit port. Differences vs iOS:
//    - Uses a ModalViewController (centered sheet) instead of full-screen modal.
//    - Number pad uses TextButton instances laid out manually (no UIButton).
//    - Shake animation is a CAKeyframeAnimation on the dots row layer.
//    - No per-chat biometric prompt — Mac side is keyboard+mouse first; the iOS
//      per-chat biometric block is intentionally omitted. The ONLY biometric use
//      is the master "Reset Chat Lock" escape hatch, which uses
//      LAContext.deviceOwnerAuthentication (Touch ID OR the Mac login password).
//
//  Callers wire pin gate via the helpers at the bottom of this file:
//    FenixuzChatPincode.presentSet(for: window, onSuccess: { code in ... })
//    FenixuzChatPincode.presentVerify(for: window, verify: { ... }, onSuccess: { ... })
//    FenixuzChatPincode.presentRemove(for: window, verify: { ... }, onSuccess: { ... })
//    FenixuzChatPincode.presentMasterRecovery(for: window, onSuccess: { ... })

import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import FenixuzCore
import LocalAuthentication

public enum FenixuzChatPincodeMode {
    case set(onSuccess: (String) -> Void)
    // onForgot: when non-nil a "Forgot pincode?" link appears that invokes it
    // (master-pincode recovery). Default nil keeps existing call sites unchanged.
    case verify(onVerify: (String) -> Bool, onSuccess: () -> Void, onForgot: (() -> Void)? = nil)
    case remove(onVerify: (String) -> Bool, onSuccess: () -> Void)
}

// MARK: - Pincode view (NSView, hosts the actual UI)

private final class PincodeView: NSView {
    let titleLabel: TextView = TextView()
    let subtitleLabel: TextView = TextView()
    let dotsContainer: NSView = NSView()
    private(set) var dotViews: [NSView] = []
    let padContainer: NSView = NSView()
    let closeButton: ImageButton = ImageButton()
    let forgotButton: TextButton = TextButton()

    private let isDark: Bool

    init(isDark: Bool) {
        self.isDark = isDark
        super.init(frame: .zero)

        self.wantsLayer = true
        self.layer?.backgroundColor = (isDark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)).cgColor

        // Close button — render a simple X glyph.
        if let xImage = PincodeView.makeCloseIcon(isDark: isDark) {
            closeButton.set(image: xImage, for: .Normal)
        }
        closeButton.autohighlight = false
        closeButton.scaleOnClick = true
        closeButton.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
        addSubview(closeButton)

        // Title.
        titleLabel.isSelectable = false
        addSubview(titleLabel)

        // Subtitle.
        subtitleLabel.isSelectable = false
        addSubview(subtitleLabel)

        // Dots.
        addSubview(dotsContainer)
        for _ in 0..<4 {
            let dot = NSView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 8
            dot.layer?.borderWidth = 2
            dotsContainer.addSubview(dot)
            dotViews.append(dot)
        }

        addSubview(padContainer)

        // "Forgot pincode?" / "Reset Chat Lock" link — hidden until wired by the controller.
        forgotButton.isHidden = true
        addSubview(forgotButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func makeCloseIcon(isDark: Bool) -> CGImage? {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        let strokeColor = isDark ? NSColor(white: 1, alpha: 0.45) : NSColor(white: 0, alpha: 0.35)
        strokeColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 6, y: 6))
        path.line(to: NSPoint(x: 16, y: 16))
        path.move(to: NSPoint(x: 16, y: 6))
        path.line(to: NSPoint(x: 6, y: 16))
        path.stroke()
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height

        // Close button — top-right.
        closeButton.frame = NSRect(x: w - 12 - 28, y: h - 12 - 28, width: 28, height: 28)

        // Title — center, top quarter.
        let titleSize = titleLabel.frame.size
        titleLabel.setFrameOrigin(NSPoint(x: (w - titleSize.width) / 2, y: h - 64 - titleSize.height))

        // Subtitle — below title.
        let subSize = subtitleLabel.frame.size
        subtitleLabel.setFrameOrigin(NSPoint(x: (w - subSize.width) / 2, y: titleLabel.frame.minY - 8 - subSize.height))

        // Dots — below subtitle.
        let dotSize: CGFloat = 16
        let dotSpacing: CGFloat = 18
        let dotsWidth = CGFloat(dotViews.count) * dotSize + CGFloat(dotViews.count - 1) * dotSpacing
        dotsContainer.frame = NSRect(x: (w - dotsWidth) / 2, y: subtitleLabel.frame.minY - 36 - dotSize, width: dotsWidth, height: dotSize)
        for (i, dot) in dotViews.enumerated() {
            dot.frame = NSRect(x: CGFloat(i) * (dotSize + dotSpacing), y: 0, width: dotSize, height: dotSize)
        }

        // Pad — centered, raised to leave a bottom band for the forgot/reset link.
        let padWidth: CGFloat = 240
        let padHeight: CGFloat = 4 * 56 + 3 * 10
        padContainer.frame = NSRect(x: (w - padWidth) / 2, y: 52, width: padWidth, height: padHeight)

        // Forgot / Reset link — bottom band, centered under the pad.
        let forgotSize = forgotButton.frame.size
        forgotButton.setFrameOrigin(NSPoint(x: (w - forgotSize.width) / 2, y: 16))
    }
}

// MARK: - Controller

final class FenixuzChatPincodeViewController: ModalViewController {

    private let mode: FenixuzChatPincodeMode
    // When true this is the master-pincode recovery screen ("Forgot pincode?"),
    // which shows a distinct title/subtitle and a device-owner "Reset" escape hatch.
    private let isMasterRecovery: Bool

    private var enteredCode: String = ""
    private var firstCode: String = ""
    private var isConfirming: Bool = false
    // Wrong-entry counter (verify/master). After 4 we surface recovery — never a lockout.
    private var failedAttempts = 0

    private var pincodeView: PincodeView!

    init(mode: FenixuzChatPincodeMode, isMasterRecovery: Bool = false) {
        self.mode = mode
        self.isMasterRecovery = isMasterRecovery
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 520))
        self.bar = .init(height: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var closable: Bool { return true }

    override func viewClass() -> AnyClass {
        return PincodeView.self
    }

    private var genericView: PincodeView {
        return self.view as! PincodeView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let isDark = presentation.colors.isDark
        self.pincodeView = self.genericView
        // Replace the auto-instantiated view with our isDark-aware one. We use
        // the same class so the cast above is safe.
        // Build the keypad subviews now that view is loaded.
        buildKeypad(isDark: isDark)

        // Close button action.
        genericView.closeButton.set(handler: { [weak self] _ in
            self?.close()
        }, for: .Click)

        // Forgot / Reset link — chat-verify recovery + master-recovery reset.
        let forgot = genericView.forgotButton
        forgot.set(font: .medium(.text), for: .Normal)
        forgot.set(color: presentation.colors.accent, for: .Normal)
        forgot.set(text: isMasterRecovery ? FenixuzL10n.current.chatLock_resetButton : FenixuzL10n.current.chatLock_forgot, for: .Normal)
        forgot.autohighlight = false
        forgot.scaleOnClick = true
        _ = forgot.sizeToFit()
        forgot.set(handler: { [weak self] _ in
            self?.forgotTapped()
        }, for: .Click)
        syncForgotVisibility()

        // Initial labels + dot colors.
        updateLabels()
        updateDots(animated: false)
        readyOnce()
    }

    private func buildKeypad(isDark: Bool) {
        let pad = genericView.padContainer
        let buttonSize: CGFloat = 56
        let spacing: CGFloat = 10
        let digits: [(String, Int?)] = [
            ("1", 1), ("2", 2), ("3", 3),
            ("4", 4), ("5", 5), ("6", 6),
            ("7", 7), ("8", 8), ("9", 9),
            ("", nil), ("0", 0), ("⌫", -1)
        ]
        for (i, (label, value)) in digits.enumerated() {
            if label.isEmpty { continue }
            let row = i / 3
            let col = i % 3
            let btn = TextButton()
            btn.layer?.cornerRadius = buttonSize / 2
            btn.set(font: .normal(.huge), for: .Normal)
            btn.set(color: isDark ? .white : .black, for: .Normal)
            btn.set(text: label, for: .Normal)
            if label != "⌫" {
                btn.layer?.backgroundColor = (isDark
                    ? NSColor(white: 1, alpha: 0.08)
                    : NSColor(white: 1, alpha: 0.95)).cgColor
                btn.set(background: isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 1, alpha: 0.95), for: .Normal)
                btn.set(background: isDark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0.92, alpha: 1), for: .Highlight)
            } else {
                btn.set(background: .clear, for: .Normal)
                btn.set(background: .clear, for: .Highlight)
            }
            btn.autohighlight = label != "⌫"
            btn.scaleOnClick = true
            btn.frame = NSRect(x: CGFloat(col) * (buttonSize + spacing),
                               y: pad.bounds.height - buttonSize - CGFloat(row) * (buttonSize + spacing),
                               width: buttonSize, height: buttonSize)
            // Use a tag to recover the action without capturing a strong ref.
            btn.set(handler: { [weak self] _ in
                guard let self = self else { return }
                if let digit = value, digit >= 0 {
                    self.append(digit)
                } else {
                    self.backspace()
                }
            }, for: .Click)
            pad.addSubview(btn)
        }
    }

    private func updateLabels() {
        let l10n = FenixuzL10n.current
        let isDark = presentation.colors.isDark
        let titleText: String
        let subtitleText: String
        switch mode {
        case .set:
            if isConfirming {
                titleText = l10n.pincode_set_confirmTitle
                subtitleText = l10n.pincode_set_confirmSubtitle
            } else {
                titleText = l10n.pincode_set_title
                subtitleText = l10n.pincode_set_subtitle
            }
        case .verify:
            if isMasterRecovery {
                titleText = l10n.chatLock_verifyMaster_title
                subtitleText = l10n.chatLock_verifyMaster_subtitle
            } else {
                titleText = l10n.pincode_verify_title
                subtitleText = l10n.pincode_verify_subtitle
            }
        case .remove:
            titleText = l10n.pincode_remove_title
            subtitleText = l10n.pincode_remove_subtitle
        }
        let titleColor: NSColor = isDark ? .white : .black
        let subColor: NSColor = isDark ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0, alpha: 0.5)
        let titleAttr = NSAttributedString.initialize(string: titleText, color: titleColor, font: .bold(24))
        let titleLayout = TextViewLayout(titleAttr, alignment: .center)
        titleLayout.measure(width: 320)
        genericView.titleLabel.update(titleLayout)
        let subAttr = NSAttributedString.initialize(string: subtitleText, color: subColor, font: .normal(14))
        let subLayout = TextViewLayout(subAttr, alignment: .center)
        subLayout.measure(width: 320)
        genericView.subtitleLabel.update(subLayout)
        genericView.needsLayout = true
    }

    private func updateDots(animated: Bool) {
        let accent = presentation.colors.accent
        let isDark = presentation.colors.isDark
        let emptyBorder = isDark ? NSColor(white: 1, alpha: 0.3) : NSColor(white: 0, alpha: 0.25)
        for (i, dot) in genericView.dotViews.enumerated() {
            let filled = i < enteredCode.count
            let block = {
                dot.layer?.backgroundColor = filled ? accent.cgColor : NSColor.clear.cgColor
                dot.layer?.borderColor = filled ? accent.cgColor : emptyBorder.cgColor
            }
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.15)
                block()
                CATransaction.commit()
            } else {
                block()
            }
        }
    }

    // MARK: - Input

    private func append(_ digit: Int) {
        guard enteredCode.count < 4 else { return }
        enteredCode.append(String(digit))
        updateDots(animated: true)
        if enteredCode.count == 4 {
            processCode()
        }
    }

    private func backspace() {
        guard !enteredCode.isEmpty else { return }
        enteredCode.removeLast()
        updateDots(animated: true)
    }

    private func processCode() {
        switch mode {
        case let .set(onSuccess):
            if !isConfirming {
                firstCode = enteredCode
                enteredCode = ""
                isConfirming = true
                updateLabels()
                updateDots(animated: true)
            } else if enteredCode == firstCode {
                let code = firstCode
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onSuccess(code)
                }
            } else {
                shakeAndReset(message: FenixuzL10n.current.pincode_error_mismatch)
            }

        case let .verify(onVerify, onSuccess, _):
            if onVerify(enteredCode) {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onSuccess()
                }
            } else {
                failedAttempts += 1
                shakeAndReset(message: FenixuzL10n.current.pincode_error_wrong)
                if failedAttempts >= 4 {
                    revealRecovery()
                }
            }

        case let .remove(onVerify, onSuccess):
            if onVerify(enteredCode) {
                close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onSuccess()
                }
            } else {
                shakeAndReset(message: FenixuzL10n.current.pincode_error_wrong)
            }
        }
    }

    private func shakeAndReset(message: String) {
        // Briefly recolor subtitle to indicate the error.
        let isDark = presentation.colors.isDark
        let errColor = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        let errAttr = NSAttributedString.initialize(string: message, color: errColor, font: .normal(14))
        let errLayout = TextViewLayout(errAttr, alignment: .center)
        errLayout.measure(width: 320)
        genericView.subtitleLabel.update(errLayout)
        genericView.needsLayout = true

        // Shake the dots row.
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.duration = 0.4
        anim.values = [-10, 10, -8, 8, -5, 5, 0]
        genericView.dotsContainer.layer?.add(anim, forKey: "shake")
        _ = isDark

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.enteredCode = ""
            self.isConfirming = false
            self.firstCode = ""
            self.updateLabels()
            self.updateDots(animated: true)
        }
    }

    // MARK: - Forgot / master recovery

    /// The optional master-recovery handler — present only in `.verify` mode.
    private var verifyOnForgot: (() -> Void)? {
        if case let .verify(_, _, onForgot) = mode {
            return onForgot
        }
        return nil
    }

    /// Chat verify: show "Forgot pincode?" immediately when a recovery handler exists.
    /// Master recovery: hide "Reset Chat Lock" until the user has struggled (4 wrong tries).
    private func syncForgotVisibility() {
        genericView.forgotButton.isHidden = isMasterRecovery ? (failedAttempts < 4) : (verifyOnForgot == nil)
        genericView.needsLayout = true
    }

    private func forgotTapped() {
        if isMasterRecovery {
            resetChatLockTapped()
        } else if let onForgot = verifyOnForgot {
            // Close this chat-verify sheet first so the master-recovery sheet
            // doesn't stack on top of an orphaned modal.
            close()
            onForgot()
        }
    }

    /// Escape hatch when the user has ALSO forgotten the master pincode. Chat Lock is a
    /// local privacy gate (messages live on Telegram's servers), so a device-owner-proven
    /// reset loses no data. Requires Touch ID / the Mac login password so a snooper can't
    /// just tap it.
    private func resetChatLockTapped() {
        guard let window = self.window else { return }
        let l = FenixuzL10n.current
        verifyAlert(for: window,
                    header: l.chatLock_resetConfirmTitle,
                    information: l.chatLock_resetConfirmMessage,
                    ok: l.chatLock_resetConfirmAction,
                    cancel: l.chatLock_cancel,
                    successHandler: { [weak self] _ in
            self?.authenticateThenReset()
        })
    }

    private func authenticateThenReset() {
        let proceed: () -> Void = { [weak self] in
            guard let self = self else { return }
            FenixuzChatPincodeManager.shared.disableChatLock()
            self.close()
            if case let .verify(_, onSuccess, _) = self.mode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onSuccess() }
            }
        }
        let ctx = LAContext()
        var authError: NSError?
        // deviceOwnerAuthentication = Touch ID with a Mac-password fallback.
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: FenixuzL10n.current.chatLock_resetReason) { ok, _ in
                DispatchQueue.main.async { if ok { proceed() } }
            }
        } else {
            // No passcode/Touch ID on this Mac — no security boundary to honor.
            proceed()
        }
    }

    /// After 4 wrong entries we never lock the owner out — we make recovery obvious instead.
    private func revealRecovery() {
        guard isMasterRecovery || verifyOnForgot != nil else { return }
        let isDark = presentation.colors.isDark
        let subColor: NSColor = isDark ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0, alpha: 0.5)
        let hintAttr = NSAttributedString.initialize(string: FenixuzL10n.current.chatLock_recoveryHint, color: subColor, font: .normal(14))
        let hintLayout = TextViewLayout(hintAttr, alignment: .center)
        hintLayout.measure(width: 320)
        genericView.subtitleLabel.update(hintLayout)
        genericView.needsLayout = true
        if isMasterRecovery {
            genericView.forgotButton.isHidden = false
        }
        guard !genericView.forgotButton.isHidden else { return }
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1.0, 1.12, 1.0]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.duration = 0.3
        genericView.forgotButton.layer?.add(pulse, forKey: "pulse")
    }
}

// MARK: - Public helper namespace

public enum FenixuzChatPincode {
    public static func presentSet(for window: Window, onSuccess: @escaping (String) -> Void) {
        let controller = FenixuzChatPincodeViewController(mode: .set(onSuccess: onSuccess))
        showModal(with: controller, for: window)
    }

    public static func presentVerify(for window: Window,
                                     verify: @escaping (String) -> Bool,
                                     onSuccess: @escaping () -> Void,
                                     onForgot: (() -> Void)? = nil) {
        let controller = FenixuzChatPincodeViewController(mode: .verify(onVerify: verify, onSuccess: onSuccess, onForgot: onForgot))
        showModal(with: controller, for: window)
    }

    public static func presentRemove(for window: Window,
                                     verify: @escaping (String) -> Bool,
                                     onSuccess: @escaping () -> Void) {
        let controller = FenixuzChatPincodeViewController(mode: .remove(onVerify: verify, onSuccess: onSuccess))
        showModal(with: controller, for: window)
    }

    /// Master-pincode recovery sheet ("Enter master pincode" + device-owner Reset).
    public static func presentMasterRecovery(for window: Window,
                                             onSuccess: @escaping () -> Void) {
        let controller = FenixuzChatPincodeViewController(
            mode: .verify(onVerify: { FenixuzChatPincodeManager.shared.verifyMaster($0) },
                          onSuccess: onSuccess,
                          onForgot: nil),
            isMasterRecovery: true)
        showModal(with: controller, for: window)
    }

    /// Convenience: gate a chat-open call by the per-chat pincode (if any).
    /// If no pincode is set, `onUnlocked` runs immediately. Otherwise, the
    /// verify sheet is presented and `onUnlocked` only runs on correct entry.
    public static func gate(window: Window,
                            chatId: PeerId,
                            manager: FenixuzChatPincodeManager = .shared,
                            onUnlocked: @escaping () -> Void) {
        if !manager.isLocked(chatId) {
            onUnlocked()
            return
        }
        presentVerify(for: window,
                      verify: { code in manager.verify(code, for: chatId) },
                      onSuccess: onUnlocked)
    }
}
