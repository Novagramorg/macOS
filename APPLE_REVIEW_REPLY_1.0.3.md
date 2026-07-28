# App Store Connect — Reply to Review (Submission ID ae71506c-1b6d-4cb9-a54d-83f7ff2b0d75)

> macOS **Novagram** · Version 1.0.3 (114) · reviewed 2026-07-15
> Two open items: **4.1(c) Copycats** (app name) + **2.4.5(i)** (three entitlements).
> **No new binary required for either item.** (Apple: "You will not need to upload a new binary.")
> On-device name is already `Novagram` (verified); build 1.0.3 (115) continues review once both items are answered.
>
> STATUS 2026-07-20: audit re-verified all three entitlements against current source — all justified, none removable
> without deleting a real shipping feature. **Part A below (2.4.5(i)) is ready to send now.**
> **Part B (4.1(c) / the Name) is pending the user's name decision** — the Name field MUST lose the word "Telegram"
> for macOS to pass; there is no reply-only way around 4.1(c) short of Telegram's written permission.

---

## PART A — Guideline 2.4.5(i), Entitlements  ·  READY TO PASTE (name-independent)

Paste the block between the `=====` markers into Resolution Center. (Send together with Part B once the Name is fixed.)

=====

Hello, and thank you for the detailed review.

**Guideline 2.4.5(i) — Entitlements**

All three entitlements are backed by shipping functionality that is reachable in the app. Below is where each is used and how to reproduce it. A demo account with automatic code entry is described at the end of this message.

1) com.apple.security.network.server
The app provides one-to-one voice and video calls and multi-participant group voice chats. Calls use a WebRTC peer-to-peer engine. When a direct peer-to-peer path is available, the app must accept the call peer's inbound UDP packets, which this entitlement grants; without it, calls are forced to relay-only and quality degrades. To reproduce: open any one-to-one conversation and click the phone or video-call button in the conversation header (the same Call / Video Call buttons also appear on a contact's profile Info screen). Group voice chats are started from any Group or Channel Info screen, and a dedicated "Calls" tab in the sidebar shows call history.

2) com.apple.security.personal-information.location
Core Location backs several reachable features:
   • Sharing your location in a chat — open any conversation, click the attachment (paperclip) button in the message field, and choose "Location" to send your current or live location.
   • Attaching a location to a Business account profile.
   • Auto-Night appearance — in Settings → Appearance, the Auto-Night option uses your location's local sunrise/sunset times to switch automatically between the light and dark themes.
The matching NSLocationWhenInUseUsageDescription and NSLocationAlwaysUsageDescription strings are present in Info.plist.

3) com.apple.security.files.downloads.read-write
Open any photo, video, or GIF from a chat in the full-screen media viewer, then click the Save icon in the viewer's toolbar (this is separate from Share and from the "…" More menu). This one-tap "Quick Save" copies the file straight into the macOS Downloads folder and shows a "Saved to Downloads" confirmation — with no per-file save dialog. The same Downloads location (its path is shown in Settings → Data and Storage → Download Folder) is also written to automatically when a received file finishes downloading. Writing to the Downloads folder without presenting a save panel requires this entitlement; the separate "Save As…" action instead uses com.apple.security.files.user-selected.read-write.

We believe all three are the minimum needed for the calling, location, and file-saving features above. We are happy to provide a short screen recording of any of them if that would help.

**Reaching the signed-in experience (automatic demo login)**

1. Launch the app. On the phone-number screen enter: +998 33 599 94 79
2. Press Next and wait up to 10 seconds — the 5-digit code is fetched and filled in automatically, then submitted. You do not need to type it.
3. If a Two-Step Verification password is requested, it is filled automatically (manual value if needed: Xabarchi).
4. You are now inside the full app and can exercise the calls, location sharing, and file saving described above.

Thank you again for your time.

=====

---

## PART B — Guideline 4.1(c), App name  ·  PENDING YOUR NAME DECISION

**Why this is unavoidable for macOS:** Apple rejected the App Store **listing Name** "Novagram Messenger **Telegram**" because it contains another developer's product name. Their instruction was literally "revise the metadata to remove … product names." A resubmission that keeps "Telegram" in the Name = an automatic re-reject. The only exception is attaching Telegram's written permission (we do not have it). So the Name must drop "Telegram."

**This does NOT touch the published iOS binary.** The Name lives in App Store Connect → General → **App Information → Localizable Information → Name** — it is app-level metadata shared by iOS and macOS (one field, one record). Editing it changes only the store listing text; installed iOS apps and their behavior are unaffected, and it also protects the in-review iOS 2.0.5 from the same 4.1(c) flag. There is no way to give macOS a different store Name from iOS in the same Universal-Purchase record.

**Name options** (pick one, then set it in ASC):
- `Novagram Messenger` — clean, guaranteed 4.1(c)-safe, fastest approval. (Recommended)
- `Novagram` — shortest / safest.
- `Novagram: Unofficial Telegram` — keeps the "Telegram" search keyword via the ToS-compliant "Unofficial" connective (live precedents: Swiftgram, Nicegram, Tevegram). Slightly higher re-reject risk right after a copycat flag.

Keep the word "Telegram" OUT of Name/Subtitle/Keywords. It may (and per Telegram API ToS 2.2, should) appear in the **Description** as a disclosure that the app connects to the Telegram network.

**4.1(c) paragraph to PREPEND to the Part A reply once the Name is changed:**

> **Guideline 4.1(c) — App name**
> We have updated the app's name to remove the third-party product name; it no longer contains "Telegram" and now reads "<CHOSEN NAME>". Novagram is our own brand and icon. The app is an independent third-party client that connects to the Telegram messaging network via its public API, which is what the previous name was describing; we agree it does not belong in the app name and have removed it.

---

## ASC mechanics (order of operations)

1. **(Part B) Change the Name** — ASC → your app → General → **App Information → Localizable Information → Name** → set the chosen name. Repeat for each localization (en / uz / ru) that still has "Telegram". Save. This is editable while 1.0.3 is in the rejected state; no Developer-Reject and no new build needed.
2. **(Part A + B) Reply** — open **Resolution Center** for submission `ae71506c-…`, paste the 4.1(c) paragraph + the Part A block as one message. (Resolution Center replies can only be sent by hand — there is no App Store Connect API for them.)
3. Review resumes on the existing build **1.0.3 (115)**. No upload required.

> If you want extra insurance for 2.4.5(i), I can build the app and capture a short screen recording of location-sharing + Quick-Save-to-Downloads (a call needs a second party, so I'd narrate that one) — say the word.
