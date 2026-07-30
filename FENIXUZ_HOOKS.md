# Fenixuz hooks in Telegram-Mac (macOS native fork)

Source-of-truth index for every line of Fenixuz code that lives outside Fenixuz-prefixed files (`Telegram-Mac/Fenixuz*.swift`). Each entry: the exact file + region modified, the hook code, why it lives outside a Fenixuz module.

On every `git pull upstream master`, this file is used to re-apply hooks if upstream code moved. **Fenixuz hooks always win** against upstream changes; surrounding upstream code is taken as-is.

Companion to `submodules/Fenixuz/HOOKS.md` in the iOS fork. iOS uses Bazel + module submodules; macOS uses Xcode + single-target compilation, so every Fenixuz file is directly in `Telegram-Mac/`.

> Last verified: 2026-05-21 — initial inventory created when porting the iOS Apple §3.1.1 IAP gate to macOS.

---

## App Store IAP gate (Apple guideline 3.1.1) — May 2026 rejection fix

**Context.** Apple Submission ID `d5a06920-6b5f-4167-b7fb-46c80b156aa8` rejected the iOS Fenixuz fork in May 2026 under §3.1.1 because the reviewer reached `BotCheckoutController` from `@PremiumBot` and could pay 269 990 UZS for an Annual Premium Subscription — i.e. a digital subscription via fiat card, bypassing IAP. The same flow exists on macOS (`PaymentsCheckoutController` reached via `t.me/$slug`, Web App `web_app_open_invoice`, or chat keyboard payment button). Plus every StoreKit-backed Premium / Stars / Gift purchase on macOS would fail server-side anyway: Telegram's server only honours receipts from the official client bundle. So on this fork we block both paths and direct the user to the official Telegram for macOS (Mac App Store ID `747648890`).

**Files added (not hooks — Fenixuz-owned):**
- `Telegram-Mac/FenixuzAppStoreIAP.swift` — `shouldBlock(invoice:)`, `shouldBlock(currency:hasSubscriptionPeriod:)`, `shouldBlockIAP`, `presentBlockedAlert(on:Window)`. Uses TGUIKit `verifyAlert` + `NSWorkspace.shared.open` for the Mac App Store deep link.
- `Telegram-Mac/FenixuzL10n.swift` — `iap_block_title`, `iap_block_message`, `iap_block_open_app_store`, `iap_block_cancel` (en/uz/ru).

**Detection rules:**
- **Invoice gate** (`shouldBlock(invoice:)`): `currency.uppercased() != "XTR"` AND `subscriptionPeriod != nil`. Stars stay allowed at the invoice surface; one-off non-subscription bot invoices for physical goods continue to work.
- **StoreKit gate** (`shouldBlockIAP`): unconditional `true`. Every Premium / Stars / Gift / Subscription / Restore goes through StoreKit on Mac via `InAppPurchaseManager.buyProduct(...)` and `restorePurchases(...)`. None of those receipts are honoured by Telegram's server.

---

### `Telegram-Mac/InAppLinks.swift` (line ~1313)

**Hook in `case let .invoice(_, context, slug):` of `execute(inapp:afterComplete:)`, inside the `fetchBotPaymentInvoice` next-block, BEFORE the `if invoice.currency == XTR` branching.**

```swift
// Fenixuz: Apple 3.1.1 — t.me/$slug deep-link orqali fiat-card Premium obuna sotib olishni bloklaymiz.
if FenixuzAppStoreIAP.shouldBlock(invoice: invoice) {
    FenixuzAppStoreIAP.presentBlockedAlert(on: getWindow(context))
    return
}
```

Reason: covers the deep-link path (`https://t.me/$slug` resolved to an invoice). `getWindow(context)` returns the active `Window` (TGUIKit).

---

### `Telegram-Mac/WebpageModalController.swift` (line ~1875)

**Hook inside the `web_app_open_invoice` handler, in the `if let window = self?.window` block, BEFORE the `if invoice.currency == XTR` branching.**

```swift
// Fenixuz: Apple 3.1.1 — Web App ichidan ochilgan fiat-card Premium obunani bloklaymiz.
if FenixuzAppStoreIAP.shouldBlock(invoice: invoice) {
    FenixuzAppStoreIAP.presentBlockedAlert(on: window)
    self?.sendEvent(name: "invoice_closed", data: "{\"slug\": \"\(slug)\", \"status\": \"cancelled\"}")
    return
}
```

Reason: Web Apps (`web_app_open_invoice`) can trigger Premium subscription invoices independently of the slug deep-link path. We also send `invoice_closed: cancelled` so the WebApp JS learns the flow ended (matches existing cancellation semantics).

---

### `Telegram-Mac/ChatInterfaceInteraction.swift` (line ~826)

**Hook in `case .payment:` of the chat keyboard-button handler, inside the `if let receiptMessageId = receiptMessageId { ... } else { ... }` else-branch, BEFORE the `else if invoice.currency == XTR` branch.**

```swift
// Fenixuz: Apple 3.1.1 — chat-ichi bot keyboard tugmasi orqali @PremiumBot fiat-card obuna yo'lini bloklaymiz.
if FenixuzAppStoreIAP.shouldBlock(invoice: invoice) {
    FenixuzAppStoreIAP.presentBlockedAlert(on: strongSelf.context.window)
} else if invoice.currency == XTR {
    showModal(...)
} else {
    showModal(...)
}
```

Reason: this is the exact path the May 2026 iOS reviewer used — tapping `@PremiumBot`'s invoice message in chat would otherwise present `PaymentsCheckoutController` modally.

---

### `Telegram-Mac/PremiumBoardingController.swift` (lines ~1672 + ~1765)

Two hooks: the `buyAppStore` closure (Subscribe path) and the `restore()` method (Restore Purchases path).

**Hook 1 — inside `buyAppStore = { ... }`, BEFORE the `canPurchasePremium` chain (around line 1668):**

```swift
// Fenixuz: Apple 3.1.1 — StoreKit Premium subscription fork'da sotilmaydi.
// Telegram serveri rasmiy bo'lmagan client receiptlarini qabul qilmaydi.
if FenixuzAppStoreIAP.shouldBlockIAP {
    lockModal.close()
    needToShow = false
    FenixuzAppStoreIAP.presentBlockedAlert(on: context.window)
    return
}
```

**Hook 2 — at the top of `func restore()`, BEFORE `context.inAppPurchaseManager.restorePurchases(...)`:**

```swift
// Fenixuz: Apple 3.1.1 — restorePurchases bu fork uchun hech qachon Premium qaytarmaydi
// (StoreKit receipt'lar Telegram serverida invalid). Foydalanuvchini rasmiy clientga yo'naltirsin.
if FenixuzAppStoreIAP.shouldBlockIAP {
    FenixuzAppStoreIAP.presentBlockedAlert(on: context.window)
    return
}
```

Reason: the Premium Boarding screen still renders (view-only — features list, prices). The Subscribe and Restore buttons end at the alert. `lockModal.close()` is called explicitly so the brief "preparing purchase" modal doesn't linger behind the alert.

---

### `Telegram-Mac/GiveawayModalController.swift` (line ~1342)

**Hook BEFORE the `canPurchasePremium` chain that funnels into `inAppPurchaseManager.buyProduct(...)`:**

```swift
// Fenixuz: Apple 3.1.1 — StoreKit Giveaway purchase fork'da bloklanadi.
if FenixuzAppStoreIAP.shouldBlockIAP {
    lockModal.close()
    needToShow = false
    FenixuzAppStoreIAP.presentBlockedAlert(on: context.window)
    return
}
```

Reason: Channel boost / giveaway flows route through StoreKit Premium subscriptions; the receipt would fail server-side. Same `lockModal.close()` + `needToShow = false` pattern as PremiumBoardingController.

---

### `Telegram-Mac/PremiumGiftController.swift` (line ~611)

**Hook inside `buyAppStore = { ... }`, BEFORE the `canPurchasePremium` chain.**

```swift
// Fenixuz: Apple 3.1.1 — StoreKit Premium gift fork'da bloklanadi.
if FenixuzAppStoreIAP.shouldBlockIAP {
    lockModal.close()
    needToShow = false
    FenixuzAppStoreIAP.presentBlockedAlert(on: context.window)
    return
}
```

Reason: gifting Premium to another user routes through StoreKit subscriptions. Same alert flow.

---

### `Telegram-Mac/PremiumGiftingController.swift` (line ~802)

**Hook inside the `buyAppStore = { ... }` closure, BEFORE the `canPurchasePremium` chain.**

```swift
// Fenixuz: Apple 3.1.1 — StoreKit Premium gift code fork'da bloklanadi.
if FenixuzAppStoreIAP.shouldBlockIAP {
    lockModal.close()
    needToShow = false
    FenixuzAppStoreIAP.presentBlockedAlert(on: context.window)
    return
}
```

Reason: multi-recipient gift-code flow routes through StoreKit Premium. Same alert flow.

---

### `Telegram-Mac/PreviewStarGiftController.swift` (line ~1167)

**Hook inside `buyAppStore: (PremiumGiftProduct) -> Void = { premiumProduct in ... }`, BEFORE the `canPurchasePremium` chain.**

```swift
// Fenixuz: Apple 3.1.1 — StoreKit Premium gift (preview) fork'da bloklanadi.
if FenixuzAppStoreIAP.shouldBlockIAP {
    lockModal.close()
    needToShow = false
    FenixuzAppStoreIAP.presentBlockedAlert(on: context.window)
    return
}
```

Reason: gift preview screen also routes through StoreKit. Same alert flow.

---

### `Telegram-Mac/Star_ListScreen.swift` (line ~1395)

**Hook BEFORE the `canPurchasePremium` chain — the Stars top-up funnel.**

```swift
// Fenixuz: Apple 3.1.1 — StoreKit Stars top-up fork'da bloklanadi.
// Stars (XTR) Apple Review tomonidan tasdiqlanadi, lekin bizning fork
// StoreKit transaksiyalarini Telegram serverida nikqachon submit qila olmaydi.
if FenixuzAppStoreIAP.shouldBlockIAP {
    lockModal.close()
    needToShow = false
    FenixuzAppStoreIAP.presentBlockedAlert(on: window)
    return
}
```

Note: uses `window` (the `var window: Window` defined at line 1231), not `context.window`. The Stars list screen creates a `bestWindow(context, getController?())` derivation because it can be presented standalone from contexts that don't have a parent window in `context`.

Reason: Stars top-up goes through `inAppPurchaseManager.buyProduct(...)` with `.stars` or `.starsGift` purpose. Even though Stars themselves are Apple-approved (XTR currency), the StoreKit transaction itself can't be redeemed on Telegram's server for this fork. Block all of them.

---

## Liquid Glass (macOS 26)

**Context.** macOS 26 "Tahoe" ships `NSGlassEffectView` / `NSGlassEffectContainerView` (AppKit, gated `if #available(macOS 26, *)`) as the native way to render Apple's Liquid Glass material. This fork adds a Settings-gated Liquid Glass mode for the folders sidebar, the navigation bar, and modal backgrounds, falling back to the existing `NSVisualEffectView`-based blur (`VisualEffect`) on macOS < 26 or when the user has the setting off. Because `InAppSettings` depends on `TGUIKit` (not the reverse — see `packages/InAppSettings/Package.swift`), `TGUIKit` cannot read `BaseApplicationSettings.liquidGlassEnabled` directly; the setting is bridged into TGUIKit through a module-global flag, mirroring the existing `PresentationTheme.swift` theme bridge (`_theme` / `presentation` / `updateTheme(_:)`).

**Files added (not hooks — Novagram/Fenixuz-owned):**
- `packages/TGUIKit/Sources/LiquidGlass.swift` — `liquidGlassEnabled` / `updateLiquidGlassEnabled(_:)` / `isLiquidGlassAvailable` global bridge, `LiquidGlassView` (thin `NSGlassEffectView` wrapper), `GlassContainerView` (thin `NSGlassEffectContainerView` wrapper), and `AdaptiveGlassEffectView` (the single glass/blur-swapping surface every wiring site below uses).
- `packages/FenixuzCore/Sources/FenixuzCore/FenixuzL10n.swift` — `glass_settingsTitle`, `glass_settingsSubtitle` (en/uz/ru) appended to the existing Fenixuz-owned localizer (no new file, string-only addition).

**Detection rule:** `isLiquidGlassAvailable` = `#available(macOS 26, *)` AND `BaseApplicationSettings.liquidGlassEnabled` (Settings toggle, defaults **on** on macOS 26+ and **off** below via `defaultLiquidGlassEnabled`). `AdaptiveGlassEffectView` re-evaluates this on every `updateLocalizationAndTheme` fan-out, so flipping the Settings row rebuilds every glass surface live through the existing `telegramUpdateTheme(theme.new(), animated: false)` refresh path.

---

### `packages/InAppSettings/Sources/InAppSettings/BaseApplicationSettings.swift` (additive field, ~14 constructor call sites)

**Additive stored property + default helper, following the exact shape of the existing `highQualityStories` field:**

```swift
public let liquidGlassEnabled: Bool

public static var defaultLiquidGlassEnabled: Bool {
    if #available(macOS 26, *) { return true } else { return false }
}
```

Wired into the designated `init(...)` (new trailing param), `init(from decoder:)` (`decodeIfPresent(Bool.self, forKey: "lqg") ?? defaultLiquidGlassEnabled`), `encode(to:)` (`encode(self.liquidGlassEnabled, forKey: "lqg")`), `==` (new equality check), `defaultSettings`, and a `, liquidGlassEnabled: self.liquidGlassEnabled` ripple append across all 12 pre-existing `withUpdated*`/`updateLiteMode` methods that reconstruct `BaseApplicationSettings(...)`. New mutator added mirroring `withUpdatedStoriesQuaility`:

```swift
public func withUpdatedLiquidGlass(_ liquidGlassEnabled: Bool) -> BaseApplicationSettings {
    return BaseApplicationSettings(handleInAppKeys: self.handleInAppKeys, sidebar: self.sidebar, showCallsTab: self.showCallsTab, latestArticles: self.latestArticles, predictEmoji: self.predictEmoji, bigEmoji: self.bigEmoji, statusBar: self.statusBar, translateChannels: self.translateChats, doNotTranslate: self.doNotTranslate, paywall: self.paywall, liteMode: self.liteMode, highQualityStories: self.highQualityStories, liquidGlassEnabled: liquidGlassEnabled)
}
```

Reason: `BaseApplicationSettings` is a `Codable` value the Settings UI drives; every mutator reconstructs the full object, so one new field always ripples across every existing mutator. Same shape as the pre-existing `highQualityStories` field addition — same class, same ripple pattern, same `"lqg"` two-letter coding-key convention.

---

### `Telegram-Mac/SharedAccountContext.swift` (line ~234)

**Hook inside the existing `baseAppSettings(accountManager:).start(next:{...})` subscription (already present for `statusBar`), right after `self._baseSettings.swap(settings)`.**

```swift
updateLiquidGlassEnabled(settings.liquidGlassEnabled) // Novagram: sync TGUIKit glass flag
```

Reason: the one and only place `BaseApplicationSettings` changes get pushed into TGUIKit's module-global flag (`packages/TGUIKit/Sources/LiquidGlass.swift`) — required because `InAppSettings` depends on `TGUIKit`, so `TGUIKit` cannot import `InAppSettings` to read the setting itself. `SharedAccountContext.swift` already imports `TGUIKit` for other reasons.

---

### `Telegram-Mac/GeneralSettingsViewController.swift` (Interface section, mirrors the `statusBar` row)

**Six small additions, each mirroring the existing `statusBar` switchable row:**

1. Enum case: `case liquidGlass(sectionId: Int, enabled: Bool, viewType: GeneralViewType)` (after `.statusBar`).
2. `stableId`: `case .liquidGlass: return 27` (next free slot after `.previewChatsInfo: return 26`).
3. `sortIndex`: `case let .liquidGlass(sectionId, _, _): return (sectionId * 1000) + stableId`.
4. `item(_:initialSize:)`:
   ```swift
   case let .liquidGlass(sectionId: _, enabled, viewType):
       return  GeneralInteractedRowItem(initialSize, stableId: stableId, name: FenixuzL10n.current.glass_settingsTitle, type: .switchable(enabled), viewType: viewType, action: {
           arguments.toggleLiquidGlass(!enabled)
       })
   ```
5. `generalSettingsEntries(...)`, right after the `.statusBar` append, OS-gated so pre-26 builds never show the row:
   ```swift
   if #available(macOS 26, *) { entries.append(.liquidGlass(sectionId: sectionId, enabled: baseSettings.liquidGlassEnabled, viewType: .innerItem)) }
   ```
6. `GeneralSettingsArguments`: new `toggleLiquidGlass: (Bool) -> Void` property + init param + assignment, and the `viewDidLoad()` writer:
   ```swift
   }, toggleLiquidGlass: { enable in
       _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, { $0.withUpdatedLiquidGlass(enable) }).start()
       telegramUpdateTheme(theme.new(), animated: false)
   }, toggleRTFEnabled: { enable in
   ```

Also added `import FenixuzCore` (for `FenixuzL10n.current.glass_settingsTitle`) — every other Fenixuz-touched file in `Telegram-Mac/` already does this.

Reason: `telegramUpdateTheme(theme.new(), animated: false)` is the existing app-wide theme-refresh call (same pattern already used by `LiteModeController.swift`) — it fans `updateLocalizationAndTheme` out to every view, which is what makes `AdaptiveGlassEffectView.rebuildBackendIfNeeded()` re-run live when the user flips the toggle.

---

### `packages/TGUIKit/Sources/NavigationBarView.swift` (`updateLocalizationAndTheme` + `layout()`)

**Hook: lazily create/tear down a glass backing behind the nav bar's `leftView`/`centerView`/`rightView`, driven by `isLiquidGlassAvailable`.**

```swift
private var glassView: AdaptiveGlassEffectView?
...
override public func updateLocalizationAndTheme(theme: PresentationTheme) {
    super.updateLocalizationAndTheme(theme: theme)
    bottomBorder.backgroundColor = presentation.colors.border
    if isLiquidGlassAvailable {
        let glass: AdaptiveGlassEffectView
        if let existing = self.glassView {
            glass = existing
        } else {
            glass = AdaptiveGlassEffectView(legacyMaterial: .headerView, blendingMode: .withinWindow)
            self.addSubview(glass, positioned: .below, relativeTo: nil)
            self.glassView = glass
        }
        backgroundColor = .clear
    } else {
        self.glassView?.removeFromSuperview()
        self.glassView = nil
        backgroundColor = presentation.colors.background
    }
}
```

`layout()` gets one new first line: `self.glassView?.frame = bounds`. `leftView`/`centerView`/`rightView` layout and the bottom border are unchanged.

Reason: `.headerView` is `NSVisualEffectMaterialHeaderView` (macOS 10.14+) — Apple's own "material used in various in-line header or footer views (e.g., by NSTableView)", the correct semantic legacy fallback material for a navigation bar.

---

### `packages/TGUIKit/Sources/Modal.swift` (line ~523, ~552-557)

**Declaration + creation of the modal's optional glass/blur background; consumption sites unchanged.**

```swift
private let visualEffectView: AdaptiveGlassEffectView?
...
if controller.isVisualEffectBackground {
    let v = AdaptiveGlassEffectView(legacyMaterial: .ultraDark, blendingMode: .withinWindow)
    v.wantsLayer = true
    self.visualEffectView = v
} else {
    self.visualEffectView = nil
}
```

Reason: every consumption site (`background = visualEffectView`, `.frame`, `.layer?.animateAlpha`, `.autoresizingMask`, `.addSubview`) only needs `NSView`-level surface, so `AdaptiveGlassEffectView` (an `NSView` subclass via TGUIKit's `View`) drops in without touching any of those call sites.

---

### `Telegram-Mac/LeftSidebarController.swift` (`LeftSidebarView`, line ~106-167)

**`visualEffectView: NSVisualEffectView` → `glassView: AdaptiveGlassEffectView`; material/blendingMode/state now passed to the initializer instead of set as three separate lines.**

```swift
private let glassView: AdaptiveGlassEffectView
required init(frame frameRect: NSRect) {
    self.glassView = AdaptiveGlassEffectView(legacyMaterial: .ultraDark, blendingMode: .behindWindow)
    super.init(frame: frameRect)
    addSubview(self.glassView)
    ...
}
```

`updateLocalizationAndTheme`: `self.visualEffectView.isHidden = theme.colors.isDark` → `self.glassView.isHidden = theme.colors.isDark`. `layout()`: `self.visualEffectView.frame = bounds` → `self.glassView.frame = bounds`.

Reason: the folders sidebar was the first `NSVisualEffectView` consumer in the fork and the reference implementation for the wiring pattern used above; `updateLocalizationAndTheme(theme: theme)` already runs at the end of `init(frame:)`, so the very first layout pass already decides the correct glass/legacy backend.

---

### `Telegram-Mac/ChatTitleBarView.swift` (`Constants`, `glassCapsule`, `updateGlassCapsule()`, `layout()`, `updateLocalizationAndTheme`)

**Hook: a rounded Liquid Glass capsule behind the chat title area, so the title becomes a floating island and the call/search buttons sit outside it — matching official Telegram 12.9.**

```swift
private enum Constants {
    static let glassCapsuleVerticalInset: CGFloat = 6
    static let glassCapsuleCornerRadius: CGFloat = 18
    static let glassCapsuleTrailingGap: CGFloat = 12
}

private var glassCapsule: AdaptiveGlassEffectView?

private func updateGlassCapsule() {
    if isLiquidGlassAvailable {
        if glassCapsule == nil {
            let capsule = AdaptiveGlassEffectView(legacyMaterial: .headerView, blendingMode: .withinWindow)
            addSubview(capsule, positioned: .below, relativeTo: nil)
            glassCapsule = capsule
        }
    } else {
        glassCapsule?.removeFromSuperview()
        glassCapsule = nil
    }
    needsLayout = true
}
```

`layout()` gets one new block after the `photoContainer`/`searchButton`/`callButton` positioning (it must run *after*, because the capsule's right edge is derived from whichever trailing button is visible). `updateLocalizationAndTheme` gets one new line: `updateGlassCapsule()`.

Reason: 12.9's Liquid Glass look is not only a material change — the title area is inset and rounded while the trailing buttons stay outside the island. Deriving `rightEdge` from `callButton`/`searchButton` frames rather than a constant keeps the capsule correct when either button is hidden (`callButton.isHidden` is the common case in saved-messages / bot chats).

---

### `Telegram-Mac/MainViewController.swift` (`chatIndex`, `settingsIndex`, `showFilterTooltip()`)

**Fix: tab indices were off by one after the fork removed the Tasks tab, so selecting a chat folder opened Settings.**

```swift
// Fenixuz: Tasks tab was removed, so every tab after calls shifted down by one.
// Tab order is now: contacts(0), calls(1, optional), chats, settings.
var chatIndex: Int {
    if showCallTabs { return 2 } else { return 1 }      // was 3 / 2
}
var settingsIndex: Int {
    if showCallTabs { return 3 } else { return 2 }      // was 4 / 3
}
```

`showFilterTooltip()` had the same stale literal (`showCallTabs ? 3 : 2`) and now uses `chatIndex`.

Reason: tabs are added as contacts(0), calls(1), chats(2), settings(3) — four tabs. `updateTabsIfNeeded()` was already corrected for the Tasks removal (it walks an incrementing index), but these three literals were missed, so `showChatList()` → `select(index: 3)` landed on Settings. Every other caller (13 sites in `ApplicationContext.swift`) goes through these two properties and was fixed by the same change.

---

### `packages/TGUIKit/Sources/AppMenuController.swift` (`Menu` view init, line ~108-150)

**`visualView: NSVisualEffectView` → `AdaptiveGlassEffectView`, plus a glass-aware corner radius.**

```swift
private let visualView: AdaptiveGlassEffectView
...
self.visualView = AdaptiveGlassEffectView(legacyMaterial: .popover, blendingMode: .behindWindow)
super.init(frame: frameRect)
self.visualView.frame = frameRect.size.bounds
...
self.visualView.legacyState = .active        // was visualView.state
let radius: CGFloat = isLiquidGlassAvailable ? 14 : 10
self.layer?.cornerRadius = radius
self.visualView.cornerRadius = radius        // was visualView.layer?.cornerRadius = 10
```

`blendingMode` moves from a separate assignment into the initializer; `.state` becomes `.legacyState`. Note the `frame` assignment must come **after** `super.init` (it is a method call on `self`).

Reason: context menus are one of the most visible glass surfaces in 12.9 (the attach menu especially). `.popover` is `NSVisualEffectMaterialPopover`, the correct semantic legacy fallback for a menu.

---

### `Telegram-Mac/PeersListController.swift` (`updateLocalizationAndTheme`, line ~1560)

**Rounded floating panel for the chat list when Liquid Glass is on.**

```swift
let listCornerRadius: CGFloat = isLiquidGlassAvailable ? 12 : 0
self.containerView.layer?.cornerRadius = listCornerRadius
self.containerView.layer?.masksToBounds = listCornerRadius > 0
self.backgroundView.layer?.cornerRadius = listCornerRadius
self.backgroundView.layer?.masksToBounds = listCornerRadius > 0
self.borderView.isHidden = listCornerRadius > 0
```

Reason: 12.9 renders the chat list as a rounded island instead of a flush column; the 1px divider is redundant once the panel has its own rounded edge. `0` radius restores the exact upstream look when the setting is off.

---

### `Telegram-Mac/LeftSidebarController.swift` (`updateLocalizationAndTheme`, line ~145)

**Second hook in this file (the first is the `glassView` swap above): keep glass visible on dark themes and round the rail.**

```swift
if isLiquidGlassAvailable {
    self.borderView.isHidden = true
    self.glassView.isHidden = false
    self.glassView.cornerRadius = 12
    self.backgroundColor = .clear
} else {
    self.borderView.isHidden = !theme.colors.isDark      // upstream
    self.glassView.isHidden = theme.colors.isDark        // upstream
    self.glassView.cornerRadius = 0
}
```

Reason: upstream hid the blur whenever `theme.colors.isDark` — a legacy `NSVisualEffectView` trade-off, since a dark blur over a dark background added nothing. That line meant the folders rail showed **no glass at all** for dark-theme users, which is every user of this fork by default. Real Liquid Glass is designed to render on dark too, and 12.9 does exactly that.

---

### `Telegram-Mac/ChatInputView.swift` (`updateLocalizationAndTheme`, line ~366)

**Rounded composer, no hairline separator, when Liquid Glass is on.**

```swift
let composerCornerRadius: CGFloat = isLiquidGlassAvailable ? 16 : 0
contentView.layer?.cornerRadius = composerCornerRadius
contentView.layer?.masksToBounds = composerCornerRadius > 0
_ts.isHidden = isLiquidGlassAvailable
```

Reason: 12.9's composer is a rounded floating bar; `_ts` is the top hairline separator, which is visually wrong once the bar has its own rounded edge.

---

### `Telegram-Mac/ApplicationContext.swift` (`applyLeftSidebarVisibility`, line ~769)

**Reverted a fork-only gate: the chat-folder rail is now shown on every tab, not just Chats.**

```swift
// before (fork):
let shouldShow = leftSidebarController != nil && leftController.isChatListSelected
// after:
let shouldShow = leftSidebarController != nil
```

Reason: verified against official Telegram 12.9 — the folder rail is **fixed chrome**, visible on Contacts, Calls, Chats and Settings alike (confirmed from screenshots of all four tabs). The fork had gated it on `isChatListSelected`, calling the other tabs a "leak"; the actual effect was the rail flickering in and out on every tab switch. Tapping a folder from any tab switches to Chats with that filter applied — that path is `navigateToChatListFilter` → `showChatList()` → `select(index: chatIndex)`, which only works correctly with the `chatIndex` fix documented above.

`MainViewController.isChatListSelected` is left in place — it is now unused by this call site but is cheap and may be wanted again.

---

### `packages/TGUIKit/Sources/LiquidGlass.swift` — `style` (Fenixuz-owned file, listed for completeness)

**Added `LiquidGlassView.Style` (`.regular` / `.clear`) mirroring `NSGlassEffectView.Style`, plumbed through `AdaptiveGlassEffectView.style`, defaulting to `.clear`.**

Reason: found by analysing the official 12.9 binary. `NSGlassEffectView` exposes four properties — `contentView`, `cornerRadius`, `tintColor`, `style` — and we were only setting two. Left at the default `.regular`, the glass renders dense and flat; `.clear` is the thin variant that lets the backdrop through, which is what makes 12.9's chrome read as soft glass. The legacy `NSVisualEffectView` backend has no equivalent, so the property is a no-op when Liquid Glass is off.

**Binary-derived map of where 12.9 puts glass** (from mangled symbols in `/Applications/Telegram.app`), useful for the remaining work:
`glassInputView`, `glassTableBackgroundView`, `searchGlass`, `glassButtons`, `keyboardGlass`, `accountGlass`, `liquidGlassBackgroundView`, `glassInset`, `glassTouchEffect`, `glassTextEffect`, `_intendedGlassTint`, `_glassContentTint`.
Classes present upstream but not in this fork: `GlassContentView`, `GlassTouchEffect`, `LegacyGlassEffectContainerView`, `FlippedGlassEffectContainerView`, protocol `GlassEffectContainer`.

---

### `Telegram-Mac/ChatController.swift` (chat ⋯ menu, `chatExportDisposable`, `runChatExport`)

**Hook: an `Export chat history` entry in the chat context menu, plus the method it calls.**

```swift
// declaration, next to deleteChatDisposable
private let chatExportDisposable: MetaDisposable = MetaDisposable()

// menu, inside `case let .peer(peerId):` after the Jump-to-First-Message hook
items.append(ContextMenuItem(FenixuzL10n.current.chatExport_menuTitle, handler: { [weak self] in
    self?.runChatExport(peerId: peerId)
}, itemImage: MenuAnimation.menu_save_as.value))

// two methods, next to setLocation
private func runChatExport(peerId: PeerId)                                  // shows the settings sheet
private func performChatExport(peerId: PeerId, format: ChatExportFormat)    // runs it
```

`runChatExport` presents `FenixuzChatExportSettingsController` (format picker); on confirm it
hands the chosen format to `performChatExport`, which wraps
`FenixuzChatExport.export(context:peerId:format:)` in `showModalProgress` and reports through
`showModalText` — success shows the message count and total size with a `Show my data` button
that reveals the folder in Finder; `.noMessages` and `.writeFailed` get their own localized text.

Reason: the export itself lives in the Fenixuz-owned `FenixuzChatExport.swift`; only the menu
entry and the thin caller touch upstream code, which keeps the merge surface to three small
insertions. Strings go through `FenixuzL10n` (en/uz/ru) — never `Locale.current`.

Related Fenixuz-owned files: `Telegram-Mac/FenixuzChatExport.swift` (collector + JSON/HTML
writers), `Telegram-Mac/FenixuzChatExportSettings.swift` (the format sheet),
`packages/FenixuzCore/Sources/FenixuzCore/FenixuzL10n.swift` (`chatExport_*` keys).
Format spec and roadmap: `EXPORT_PLAN.md`; reference exports: `_export-reference/` (gitignored).

---

## Bot token login (2026-07-29)

Log in as a bot with a BotFather token, via MTProto `auth.importBotAuthorization`. Port of the
iOS fork's feature (`submodules/Fenixuz/BotTokenLogin/` + `TelegramCore/Sources/FenixuzBotAuthorization.swift`).

### ⚠️ This is the fork's FIRST source patch inside the `telegram-ios` submodule

Read this before any upstream pull or `git submodule update`.

Every other hook in this document lives in a file the parent repo tracks. This one does not.
`submodules/telegram-ios/submodules/TelegramCore/Sources/FenixuzBotAuthorization.swift` is a
**new file inside a git submodule** that is pinned to a commit of `overtake/Telegram-iOS`, a
repo we cannot push to. The parent repo does not see the file, and **`git submodule update`
deletes it without warning.**

Why it cannot live in the app target: the four completion helpers it reuses are `internal` to
the TelegramCore module —

| Symbol | Location |
|---|---|
| `switchToAuthorizedAccount(transaction:account:isSupportUser:)` | `TelegramCore/Sources/Authorization.swift:18` |
| `storeFutureLoginToken(accountManager:token:)` | `TelegramCore/Sources/Authorization.swift:84` |
| `initializedAppSettingsAfterLogin(transaction:appVersion:syncContacts:)` | `TelegramCore/Sources/State/InitializeAccountAfterLogin.swift:6` |
| `TelegramUser(user: Api.User)` | `TelegramCore/Sources/ApiUtils/TelegramUser.swift:49` |

Reimplementing them app-side is possible (`AccountManagerModifier`'s methods are public) but was
rejected: it forks the account-record logic away from upstream with no compile-time link, so a
future upstream change that adds a required `AccountRecord` attribute would be picked up by the
phone-login path automatically and silently produce a malformed record for bot logins only.

**Survival mechanism.** The real copy is tracked in the parent repo at
`fork-patches/telegramcore/FenixuzBotAuthorization.swift`, and
`fork-patches/apply-telegramcore-patches.sh` copies it back into the submodule. The script is
idempotent and verifies with `diff`. **Run it after every fresh clone and after every
`git submodule update`.**

No registration is needed for the file itself: `submodules/telegram-ios/submodules/TelegramCore/Package.swift:48`
declares `path: "Sources"` with no `sources:` array, so SwiftPM globs the directory.

### `Telegram-Mac/AuthController.swift` — 5 hooks

1. **`State` struct** — after `lockAfterLogin`, two additive fields:
   ```swift
   var botTokenAvailable: Bool = false
   var botTokenError: ImportBotAuthorizationError?
   ```
   Modelled as a plain flag like the QR screen, *not* a new `UnauthorizedAccountStateContents`
   case — that enum is `PostboxCoding`, so a new case would mean encode/decode changes inside
   the vendored TelegramCore.

2. **Child controller** — `private let bot_token_c: Auth_BotTokenController` declared next to
   `word_c`, instantiated in `init` with the same `NSRect(x: 0, y: 0, width: 380, height: 300)`.

3. **`updateState(_:refreshToken:updateState:)`** — a new leading branch before the QR check:
   `if state.botTokenAvailable { controller = bot_token_c; bot_token_c.update(...) } else if state.tokenAvailable, state.qrEnabled { … }`.
   `takeCancel` clears the flag, which falls through to the phone screen on the next pass.

4. **Phone-entry call site** — `phone_number_c.update(...)` gains a `takeBotToken:` closure that
   sets `botTokenAvailable = true`.

5. **`index(of:)` + `updateLocalizationAndTheme`** — `bot_token_c` returns `1` (same slot as the
   QR screen: an alternate entry point off the phone step that keeps the chrome Back button
   hidden, since `updateBack` hides Back at `index <= 2`), and gets a theme-refresh call.

Plus one new private method, `loginWithBotToken(_:updateState:)`, modelled on `sendCode`:
20s timeout, `verifyAlert_button(loginConnectionError*)` on network failure with a recursive
Try Again, and `lockAfterLogin = true` on success so the screen freezes rather than bouncing
back to phone entry while `AppDelegate` swaps in the authorized context.

### `Telegram-Mac/Auth_Token.swift` — 6 hooks (the PRIMARY entry point)

The QR screen — not the phone screen — is where the auth flow actually starts:
`AuthController`'s `initialState` is `State(..., tokenAvailable: true, ..., qrEnabled: true)`, so
`updateState` routes to `token_c` on launch. An entry point only on the phone screen is one
screen too deep and effectively undiscoverable (this was found in device testing, 2026-07-30).

`botTokenButton: TextButton` + `fileprivate var takeBotToken` + a `botTokenEnabled` computed flag
(`#if APP_STORE` → `false`); `addSubview` (gated) + click handler in `init`; styling in `measure()`
(`Auth_Insets.infoFontBold`, `FenixuzBrandColors.primary`, `FenixuzL10n.current.botlogin_entry_button`);
`layout()` grows the container by `betweenError + botTokenButton.frame.height` and places the link at
`cancelButton.frame.maxY + Auth_Insets.betweenError`; `update(_:cancel:takeBotToken:)` gained a
**defaulted-nil** third parameter — nil only from the `updateLocalizationAndTheme` refresh path, which
must not clear an already-set handler.

Brand green, deliberately: the upstream `cancelButton` above it is `theme.colors.accent` (blue), so the
two footer links read as separate affordances rather than one wrapped row.

Cancelling out of the bot screen clears `botTokenAvailable` only — `tokenAvailable` stays true, so the
user lands back on the QR screen they came from.

### ⚠️ `AuthController.swift` `AuthView.layout()` — pre-existing bug fixed here (2026-07-30)

Not a bot-token hook; a fork bug the bot-token link exposed. The layout loop stretches every subview
to the full window height and centers it — that is meant for the step controllers' views, and chrome
is excluded by identity check. **`novagramProxyButton` was missing from that exclusion list**, so it
was resized to the full window height; `centerX(y: 12)` then only moved its origin, never restoring
its height.

Because `addView(_:)` inserts step views with `positioned: .below, relativeTo: self.back`, the proxy
button sits **above** the step content. The result was an invisible ~100pt-wide, full-height hit area
running down the centre of the auth window, swallowing clicks on anything centred beneath it —
the new bot-token link **and** the upstream "Log in by phone number" link (whose middle had been
dead for as long as the NovagramProxy button has existed).

Fix: add `subview != novagramProxyButton` to the exclusion list. Nothing removed — the button keeps
its handler and its `centerX(y: 12)` position; only its hit area returns to its natural size.

### `Telegram-Mac/Auth_PhoneNumber.swift` — 5 hooks (secondary entry point)

`botTokenButton: TextButton` + `takeBotToken` closure + a `botTokenEnabled` computed flag
(`#if APP_STORE` → `false`); `addSubview` + click handler in `init`; styling in
`updateLocalizationAndTheme` (`Auth_Insets.infoFont`, `FenixuzBrandColors.primary`,
`FenixuzL10n.current.botlogin_entry_button`); `layout()` grows the container by
`betweenHeader + botTokenButton.frame.height` and anchors the link at
`nextView.frame.maxY + Auth_Insets.betweenHeader`; both `update(...)` overloads gain a
`takeBotToken:` parameter.

The anchor is stable while `nextView.isHidden`, because `nextView` and `qrButton` share one y
and one 36pt height and are mutually exclusive — so the link never moves as the user types.
Unlike QR it is **not** gated on `qrEnabled`; bot login needs no server capability.

### Fenixuz-owned surfaces (not hooks)

- `Telegram-Mac/Auth_BotToken.swift` — the AppKit screen (4 types), a structural clone of
  `Auth_PasswordEntry.swift` with the secure field swapped for a plain monospaced one.
  Registered in `Telegram.xcodeproj/project.pbxproj` in the usual four places.
- `packages/FenixuzCore/Sources/FenixuzCore/FenixuzL10n.swift` — eight `botlogin_*` strings (en/uz/ru).

### Known v1 limitation — do not treat as a bug

After a successful bot login the **chat list will be empty or near-empty**. `messages.getDialogs`,
`messages.getHistory`, `messages.getPeerDialogs` and `messages.getDialogFilters` are all marked
"Only users can use this method" and return `BOT_METHOD_INVALID`. Making chats render is Phase 2:
on iOS it needed a second core file (`FenixuzBotSession.swift`) plus hooks in five more upstream
TelegramCore files. Not started here.

---

## Hook inventory summary (this fork)

| File | Hook count | Purpose |
|---|---|---|
| `Telegram-Mac/InAppLinks.swift` | 1 | t.me/$slug invoice gate (§3.1.1) |
| `Telegram-Mac/WebpageModalController.swift` | 1 | Web App invoice gate (§3.1.1) |
| `Telegram-Mac/ChatInterfaceInteraction.swift` | 1 | Chat keyboard payment gate (§3.1.1) |
| `Telegram-Mac/PremiumBoardingController.swift` | 2 | Subscribe + Restore gates (§3.1.1) |
| `Telegram-Mac/GiveawayModalController.swift` | 1 | Giveaway StoreKit gate (§3.1.1) |
| `Telegram-Mac/PremiumGiftController.swift` | 1 | Premium gift StoreKit gate (§3.1.1) |
| `Telegram-Mac/PremiumGiftingController.swift` | 1 | Premium gift-code StoreKit gate (§3.1.1) |
| `Telegram-Mac/PreviewStarGiftController.swift` | 1 | Premium gift preview StoreKit gate (§3.1.1) |
| `Telegram-Mac/Star_ListScreen.swift` | 1 | Stars top-up StoreKit gate (§3.1.1) |
| `packages/InAppSettings/Sources/InAppSettings/BaseApplicationSettings.swift` | 1 | `liquidGlassEnabled` additive field + ripple (Liquid Glass) |
| `Telegram-Mac/SharedAccountContext.swift` | 1 | TGUIKit glass-flag bridge (Liquid Glass) |
| `Telegram-Mac/GeneralSettingsViewController.swift` | 1 | Liquid Glass toggle row (Interface section) |
| `packages/TGUIKit/Sources/NavigationBarView.swift` | 1 | Glass backing behind nav bar (Liquid Glass) |
| `packages/TGUIKit/Sources/Modal.swift` | 1 | Glass modal background (Liquid Glass) |
| `Telegram-Mac/LeftSidebarController.swift` | 2 | Glass folders sidebar + dark-theme glass fix & rounded rail |
| `Telegram-Mac/ChatTitleBarView.swift` | 1 | Glass capsule behind chat title (Liquid Glass, 12.9 parity) |
| `Telegram-Mac/MainViewController.swift` | 1 | Tab index fix after Tasks-tab removal (folder → Settings bug) |
| `packages/TGUIKit/Sources/AppMenuController.swift` | 1 | Glass context menu + rounder corners (12.9 parity) |
| `Telegram-Mac/PeersListController.swift` | 2 | Rounded floating chat-list panel + 8pt inset (12.9 parity) |
| `Telegram-Mac/ChatInputView.swift` | 1 | Rounded composer, no top hairline (12.9 parity) |
| `Telegram-Mac/ApplicationContext.swift` | 1 | Folder rail fixed on all tabs (12.9 parity) |
| `Telegram-Mac/ChatController.swift` | 3 | Export chat history menu entry + disposable + caller |
| `Telegram-Mac/AuthController.swift` | 5 | Bot-token login: state fields, child controller, updateState branch, phone call site, index/theme |
| `Telegram-Mac/Auth_PhoneNumber.swift` | 5 | Bot-token login: footer link, closure, styling, layout, both `update(...)` signatures |
| `submodules/telegram-ios/…/TelegramCore/Sources/FenixuzBotAuthorization.swift` | new file | Bot-token login RPC — ⚠️ **inside the git submodule**, restored by `fork-patches/apply-telegramcore-patches.sh` |

**Total Telegram-owned files with hooks: 24. Total hook insertions: 37**, plus one new source file inside the `telegram-ios` submodule (the fork's first — see the Bot token login section). Every Fenixuz-owned code surface (`FenixuzAppStoreIAP.swift`, `FenixuzL10n.swift`, `FenixuzDemoCodeFetcher.swift`, the Fenixuz Settings controllers, the Tasks tab, `packages/TGUIKit/Sources/LiquidGlass.swift`, etc.) lives in `Telegram-Mac/Fenixuz*.swift` or a Novagram/Fenixuz-owned package file and is the source of truth for these features.

---

## Pull conflict workflow (manual, AI-assisted)

Whenever `git pull upstream master` is run for the TelegramSwift fork:

1. Checkpoint: `git tag pre-pull-checkpoint-$(date +%Y%m%d-%H%M)` + `git branch backup-before-merge-$(date +%Y%m%d)`.
2. `git pull upstream master --no-rebase`.
3. If merge conflicts surface in any of the files listed above, do NOT auto-resolve. Open this file, locate the hook block, re-apply manually at the new line position. Surrounding upstream code wins for everything else.
4. Build via `xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram -configuration Debug -derivedDataPath /tmp/tgmac-dd build CODE_SIGN_STYLE=Automatic` — must succeed. Then launch the app and verify the IAP alert still appears on Subscribe (Premium / Stars / Gift).

Never merge upstream changes without re-applying hooks. If a hook is silently dropped, Apple will re-reject the next submission.

---

## Adding a new hook

1. Put 100% of the logic into `Telegram-Mac/Fenixuz<Feature>.swift`.
2. Keep the Telegram-side hook to 1–8 lines: a single function call OR a tiny accessor method.
3. Append a new section to this file documenting the exact hook code and reason.
4. Commit the FENIXUZ_HOOKS.md update in the same commit as the hook itself.

If a hook grows beyond ~10 lines, refactor — move state into a `Telegram-Mac/Fenixuz*.swift` file and expose a single delegate-style call site.
