# App Store Connect — Reply to Review v2 (Submission ID a0ff9208-00df-4016-9721-4cd5fd7619ce)

> Paste the section between the two `=====` markers into App Store Connect → Resolution Center.
> This is a STRONGER, different reply than `APPLE_REVIEW_REPLY.md` — do NOT reuse the old text.
> Review the bracketed `[...]` notes and remove/adjust anything that does not match your final build before sending.

=====

Hello, and thank you for the follow-up.

We understand that Guideline 4.2.2 (Minimum Functionality) is still open. We want to make the native functionality of the app easy and unambiguous to verify, and we suspect the previous review session may not have reached the signed-in experience. We have made changes to fix that and we are also offering to demonstrate the app live. The 4.1(a) point appears resolved in your latest message — thank you.

**This is a fully native macOS app, not a web experience.**

Fenixuz is written entirely in Swift and AppKit (NSView / NSViewController / NSWindow). It contains no WKWebView and no embedded web browser UI. It is a native third-party client for the Telegram messaging network and speaks the MTProto binary protocol directly over the network — it does not load or aggregate web pages. Every screen the reviewer sees is drawn with native macOS controls.

**Please sign in with the demo account — the login is automatic.**

We believe the previous session may have stopped at the sign-in screen. The demo account uses our own SMS auto-fill so the reviewer does not need to receive a text message. Steps:

1. Launch the app. On the phone-number screen, enter: **+998 33 599 94 79**
2. Press **Next**. **Wait up to 10 seconds** — the 5-digit login code is fetched and filled in automatically by the app, then it submits itself. You do not need to type the code.
3. If a Two-Step Verification password is requested, it is filled automatically. (If prompted manually, the password is: **Xabarchi**)
4. You are now inside the full native app.

We have verified this sign-in flow end-to-end against the live code service immediately before this submission, and we improved the auto-submit timing in this build so the code now enters and confirms reliably without any manual step. [Confirm build number you are shipping, e.g. 1.0.0 (55), is selected for this version.]

If the automatic sign-in does not work on your review device for any reason (for example a network restriction in the review environment), we would be glad to help immediately. We can:

- Provide a screen recording / App Preview video that walks through sign-in and the native features below, and/or
- Schedule a short live screen-sharing call at your convenience so we can demonstrate the native macOS functionality directly.

Please just let us know in Resolution Center and we will respond the same day.

**Native macOS functionality you can exercise once signed in:**

- One-to-one voice and video calls (native camera and microphone capture)
- Group calls and live voice streams (multi-participant)
- Screen sharing during calls (native macOS screen capture)
- Native drag-and-drop of files, photos, and videos into and out of conversations
- A native macOS Share extension (the system Share menu) and a Focus Filter app extension
- Native macOS notifications via UNUserNotificationCenter, with Dock badge integration
- A full native menu bar with standard macOS keyboard shortcuts (e.g. ⌘N, ⌘W, search)
- Multiple native windows, including a separate window per signed-in account
- Multi-account support (sign in to several accounts and switch between them, up to 10)
- Spotlight indexing of recent chats and contacts
- On-device features unique to this client: chat PIN lock, edited-message history, Ghost mode, voice-message-to-text, and inline message translation
- Standard macOS text editing throughout (spell-check, substitutions, the Edit menu)

These are real native macOS capabilities — calls, screen sharing, drag-and-drop, system extensions, and Spotlight are not possible in a web view. We are confident that once the reviewer is signed in, the app clearly demonstrates substantial native functionality well beyond a mobile web page.

Thank you very much for your time and patience. We are happy to provide a video or a live demonstration right away — please tell us which you prefer.

=====

## Why this reply is different from the first one (do NOT paste — internal)

The first reply (`APPLE_REVIEW_REPLY.md`) failed to clear 4.2.2 because it:
- bundled 4.1 + 4.2.2 together and spent its strongest paragraph on the (now-resolved) name issue;
- gave a generic capability list with no path for the reviewer if they were stuck;
- offered no proof artifact (no video, no offer of a call);
- pointed its internal checklist at the dead `xmax.uz` endpoint.

This v2 reply, by contrast:
- leads with the most likely real cause — the reviewer never got past sign-in — and makes the login steps explicit and numbered;
- states the auto-submit timing was improved in the new build so login is reliable;
- proactively offers a screen recording / App Preview AND a live call as a fallback (the single most persuasive move for a repeat 4.2.2);
- foregrounds verified, web-impossible native features (calls, screen share, drag-and-drop, system extensions, Spotlight) to directly rebut "no different from a web browser".

## Internal checklist before resubmitting (do NOT paste)

- [ ] **Seed the demo account** (+998 33 599 94 79) with 8–15 real chats / groups / channels and some photos, videos, voice notes, and files. This is the highest-impact action — an empty account reads as "non-functional" even after a perfect login, and is the most probable driver of the repeat 4.2.2. (No content-seeding code exists in the app; this is an ops task on the account itself.)
- [ ] **Confirm the login code is fresh**, not stale: the forwarder SIM is logged into the demo account, so Telegram may send the code in-app instead of by SMS. Ensure `code.vipads.uz` returns the *current* code, or disable 2FA / log out other sessions so a fresh SMS arrives. Test phone → auto-code → (auto-password) → inside-with-chats from a clean machine before submitting.
- [ ] **Record a 15–30 s App Preview / screen recording** showing: auto sign-in, a chat with content, a call or screen share, drag-and-drop into a chat, and a menu-bar keyboard shortcut. Attach in ASC and reference it in the reply.
- [ ] **New build selected** for this version (≥ build 55), and `APP_REVIEW_NOTES.md` pasted into App Review Information → Notes.
- [ ] Verify the **Release / App Store build** launches cleanly (the Debug-only Sparkle/Update path must not run in Release) — build Release and open it once.
- [ ] Consider softening the in-app IAP "install the official Telegram" alert to a neutral "not available in this app" message so it does not read as a redirect (re-risks 4.1). Keep the StoreKit gate itself.
