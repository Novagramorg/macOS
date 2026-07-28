//
//  LiquidGlass.swift
//  TGUIKit
//
//  Liquid Glass (macOS 26) support.
//
//  TGUIKit cannot import InAppSettings (InAppSettings depends on TGUIKit, so
//  the reverse import would be a cycle). This file mirrors the existing
//  theme bridge in PresentationTheme.swift (`_theme` / `presentation` /
//  `updateTheme(_:)`) with a matching module-global flag: the app pushes
//  `BaseApplicationSettings.liquidGlassEnabled` into TGUIKit via
//  `updateLiquidGlassEnabled(_:)` from SharedAccountContext, and every glass
//  surface in TGUIKit reads it back through `isLiquidGlassAvailable`.
//

import AppKit

// MARK: - Global flag bridge

private var _liquidGlassEnabled: Bool = false

/// The user's Liquid Glass setting, as last pushed from `BaseApplicationSettings`.
/// Does not account for OS availability — use `isLiquidGlassAvailable` when
/// deciding whether to actually construct glass-backed views.
public var liquidGlassEnabled: Bool {
    return _liquidGlassEnabled
}

/// Called from `SharedAccountContext` whenever `BaseApplicationSettings` changes.
public func updateLiquidGlassEnabled(_ value: Bool) {
    assertOnMainThread()
    _liquidGlassEnabled = value
}

/// True only when both the OS supports `NSGlassEffectView` (macOS 26+) AND
/// the user has Liquid Glass enabled in Settings. This is the single check
/// every glass-consuming view in the app should use.
public var isLiquidGlassAvailable: Bool {
    if #available(macOS 26, *) {
        return _liquidGlassEnabled
    }
    return false
}

// MARK: - LiquidGlassView

/// Thin AppKit wrapper over `NSGlassEffectView` (macOS 26+ only). Subclasses
/// TGUIKit's `View` so it participates in the `AppearanceViewProtocol`
/// fan-out like any other view in the app.
///
/// Every access to the underlying `NSGlassEffectView` is behind
/// `if #available(macOS 26, *)`; on older systems this view stays a fully
/// inert, transparent placeholder (no crash, no visual output).
open class LiquidGlassView: View {

    /// Mirrors `NSGlassEffectView.Style`, declared independently so the type is
    /// usable pre-macOS 26 (the real enum only exists in the macOS 26 SDK).
    public enum Style {
        /// `NSGlassEffectViewStyleRegular` — the denser, more opaque glass.
        case regular
        /// `NSGlassEffectViewStyleClear` — thinner, lets more of the backdrop
        /// through. This is what makes 12.9's surfaces read as "soft glass"
        /// rather than a flat blur panel.
        case clear
    }

    public var cornerRadius: CGFloat = 0 {
        didSet {
            applyCornerRadius()
        }
    }

    public var style: Style = .regular {
        didSet {
            applyStyle()
        }
    }

    public var glassTintColor: NSColor? {
        didSet {
            applyTintColor()
        }
    }

    public var contentView: NSView? {
        didSet {
            applyContentView()
        }
    }

    /// Type-erased as `NSView?` (rather than `NSGlassEffectView?`) so this
    /// stored property's declared type is available pre-macOS 26; the real
    /// `NSGlassEffectView`-specific API is only touched behind `@available`.
    private var glassSubview: NSView?

    @available(macOS 26, *)
    private var glassBacking: NSGlassEffectView? {
        return glassSubview as? NSGlassEffectView
    }

    public override init() {
        super.init()
        setup()
    }

    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: bounds)
            self.addSubview(glass)
            self.glassSubview = glass
            applyCornerRadius()
            applyStyle()
            applyTintColor()
            applyContentView()
        }
    }

    private func applyCornerRadius() {
        if #available(macOS 26, *) {
            glassBacking?.cornerRadius = cornerRadius
        }
    }

    private func applyStyle() {
        if #available(macOS 26, *) {
            switch style {
            case .regular:
                glassBacking?.style = .regular
            case .clear:
                glassBacking?.style = .clear
            }
        }
    }

    private func applyTintColor() {
        if #available(macOS 26, *) {
            glassBacking?.tintColor = glassTintColor
        }
    }

    private func applyContentView() {
        if #available(macOS 26, *) {
            glassBacking?.contentView = contentView
        }
    }

    open override func layout() {
        super.layout()
        glassSubview?.frame = bounds
    }
}

// MARK: - GlassContainerView

/// Thin AppKit wrapper over `NSGlassEffectContainerView` (macOS 26+ only).
/// Groups sibling `LiquidGlassView`s so the system can merge/batch them when
/// they sit close together (per Apple's guidance this both looks better —
/// adjacent glass panes visually fuse — and renders more efficiently).
///
/// On older systems this degrades to a plain transparent passthrough `View`
/// that simply hosts whatever was added via `addGlass(_:)`.
open class GlassContainerView: View {

    public var spacing: CGFloat = 0 {
        didSet {
            applySpacing()
        }
    }

    /// Holds every view added via `addGlass(_:)`. Becomes the `contentView`
    /// of the real `NSGlassEffectContainerView` on macOS 26+, or is added
    /// directly as our own subview as an inert passthrough otherwise.
    private let mergeContent = View()

    private var containerSubview: NSView?

    @available(macOS 26, *)
    private var glassContainer: NSGlassEffectContainerView? {
        return containerSubview as? NSGlassEffectContainerView
    }

    public override init() {
        super.init()
        setup()
    }

    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        if #available(macOS 26, *) {
            let container = NSGlassEffectContainerView(frame: bounds)
            container.contentView = mergeContent
            self.addSubview(container)
            self.containerSubview = container
            applySpacing()
        } else {
            self.addSubview(mergeContent)
        }
    }

    private func applySpacing() {
        if #available(macOS 26, *) {
            glassContainer?.spacing = spacing
        }
    }

    /// Adds a glass view as a merge-eligible descendant of this container.
    public func addGlass(_ view: LiquidGlassView) {
        mergeContent.addSubview(view)
    }

    open override func layout() {
        super.layout()
        containerSubview?.frame = bounds
        mergeContent.frame = bounds
    }
}

// MARK: - AdaptiveGlassEffectView

/// The single glass-backed surface the rest of the app wires into. Internally
/// swaps between a real `LiquidGlassView` (macOS 26+, Liquid Glass enabled in
/// Settings) and the legacy `VisualEffect` blur (`NSVisualEffectView`
/// subclass, unchanged) — decided at init and re-decided every time the
/// theme refreshes, since the Settings toggle calls `telegramUpdateTheme`
/// which fans `updateLocalizationAndTheme` out to every view in the app.
public final class AdaptiveGlassEffectView: View {

    public var legacyMaterial: NSVisualEffectView.Material = .ultraDark {
        didSet {
            legacy?.material = legacyMaterial
        }
    }
    public var legacyBlendingMode: NSVisualEffectView.BlendingMode = .withinWindow {
        didSet {
            legacy?.blendingMode = legacyBlendingMode
        }
    }
    public var legacyState: NSVisualEffectView.State = .active {
        didSet {
            legacy?.state = legacyState
        }
    }

    public var cornerRadius: CGFloat = 0 {
        didSet {
            glass?.cornerRadius = cornerRadius
            legacy?.layer?.cornerRadius = cornerRadius
        }
    }

    /// Defaults to `.clear` — the thinner glass 12.9 uses for its chrome. The
    /// legacy `NSVisualEffectView` backend has no equivalent, so this is a no-op
    /// when Liquid Glass is off.
    public var style: LiquidGlassView.Style = .clear {
        didSet {
            glass?.style = style
        }
    }

    public var glassTint: NSColor? {
        didSet {
            glass?.glassTintColor = glassTint
        }
    }

    private var glass: LiquidGlassView?
    private var legacy: VisualEffect?

    public init(legacyMaterial: NSVisualEffectView.Material = .ultraDark, blendingMode: NSVisualEffectView.BlendingMode = .withinWindow) {
        self.legacyMaterial = legacyMaterial
        self.legacyBlendingMode = blendingMode
        super.init()
        rebuildBackendIfNeeded()
    }

    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rebuildBackendIfNeeded()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Swaps backends only when the target backend doesn't already match
    /// `isLiquidGlassAvailable`, so repeated theme refreshes that don't
    /// change the setting are no-ops.
    private func rebuildBackendIfNeeded() {
        if isLiquidGlassAvailable {
            guard glass == nil else { return }
            legacy?.removeFromSuperview()
            legacy = nil

            let glassView = LiquidGlassView(frame: bounds)
            glassView.cornerRadius = cornerRadius
            glassView.style = style
            glassView.glassTintColor = glassTint
            self.addSubview(glassView)
            self.glass = glassView
        } else {
            guard legacy == nil else { return }
            glass?.removeFromSuperview()
            glass = nil

            let legacyView = VisualEffect(frame: bounds)
            legacyView.material = legacyMaterial
            legacyView.blendingMode = legacyBlendingMode
            legacyView.state = legacyState
            legacyView.layer?.cornerRadius = cornerRadius
            self.addSubview(legacyView)
            self.legacy = legacyView
        }
        needsLayout = true
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        rebuildBackendIfNeeded()
    }

    public override func layout() {
        super.layout()
        glass?.frame = bounds
        legacy?.frame = bounds
    }
}
