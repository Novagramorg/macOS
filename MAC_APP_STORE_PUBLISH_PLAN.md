# Mac App Store publish-readiness plan — Fenixuz (TelegramSwift fork)

> **PLAN ONLY** — bu hujjat hech narsani o'zgartirmaydi. Bu — App Store Connect (ASC) ga submit qilishdan oldin bajariladigan **tekshiruv ro'yxati (checklist)**.
> Target: `/Users/codingtech/Documents/Telegram/TelegramSwift` — native macOS AppKit Telegram klienti (Fenixuz fork). Distribution: **Mac App Store**.
> Team: **Vipads MCHJ**, Team ID `ZDBP5RSRZF`, Apple ID `vipadsllc@gmail.com`. Bundle ID `uz.fenixuz.app` (iOS bilan Universal Purchase uchun bir xil).
> Distribution identity: `Apple Distribution: Vipads MCHJ`. Installer: `3rd-Party Mac Developer Installer: Vipads MCHJ`.
>
> **Holat markerlari:** ✅ = repo'da bajarilgan (dalil bilan) · ⏳ = qilish kerak · ❓ = tekshirish kerak (hozir aniq emas).
> **Prioritet:** `[P0]` = rad etadi · `[P1]` = katta xavf · `[P2]` = sayqal / kelajak.
>
> Tekshirilgan manbalar (live, 2026-06-13):
> [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (living document) ·
> [App Store screenshot sizes 2026 (aso.dev)](https://aso.dev/app-store-connect/screenshots/) ·
> [Hardened Runtime & Sandboxing (lapcatsoftware)](https://lapcatsoftware.com/articles/hardened-runtime-sandboxing2.html) ·
> [get-task-allow MAS analysis (afine)](https://afine.com/to-allow-or-not-to-get-task-allow-that-is-the-question) ·
> [App Store rejection reasons 2026 (QAwerk)](https://qawerk.com/blog/app-store-rejection-reasons/).

---

## ⚠️ Asosiy kashfiyot — repo allaqachon kutilganidan ko'p oldinga ketgan

Topshiriqda "P0 hole" deb belgilangan **3.1.1 IAP gate** (bot-checkout / `t.me` deep-link / Web-App invoice yo'llari Mac'da bloklanmagan) — `FORK_NOTES.md §3.9` (2026-05-18) holatiga ko'ra ochiq edi. Lekin manba kodi (2026-06-12) **endi to'liq yopilgan** ko'rsatadi: `FENIXUZ_HOOKS.md` dagi 9 fayl × 10 hook **mavjud va ulangan** (grep bilan tasdiqlandi). `FORK_NOTES.md §3.9` shunchaki yangilanmagan (stale). Shu sababli bu band quyida **"verify the hooks ship in the Release binary"** (❓) sifatida belgilangan — noldan qurish emas.

Shuningdek `MAC_4.2.2_DIAGNOSIS.md §2.3` da tavsiya qilingan **IAP alert matnini neytrallashtirish** ham bajarilgan: `iap_block_message` endi "Premium subscriptions are not available in this app." (oldingi "install the official Telegram… subscribe there" CTA olib tashlangan). Bu 4.1 re-risk'ni kamaytirdi.

---

## P0 — submit qilishdan oldin MAJBURIY (faqat shular rad ettiradi)

Bularsiz submit = yo'qotilgan review sikli. Tartib bo'yicha:

1. **[P0] ❓ Demo account `+998335999479` ni real kontent bilan to'ldirish (8–15 chat/guruh/kanal + media).** — 4.2.2 takror rad etishining **eng ehtimolli (~70%) sababi** (`MAC_4.2.2_DIAGNOSIS.md §1, §4`). Reviewer kirib bo'sh oyna ko'rsa "mobile web browser'dan farqsiz" deydi. Bu **kod emas, ops** — repo'da seeding kodi yo'q (tasdiqlangan). HOW: demo SIM'ga login qilib, qo'lda 8–15 chat/guruh/kanal + rasm/video/voice/fayl qo'shing.
2. **[P0] ❓ Stale-code login muammosini hal qilish.** — forwarder SIM allaqachon login qilingan bo'lsa Telegram kodni **in-app** yuboradi, `code.vipads.uz` eski kodni qaytarsa `PHONE_CODE_INVALID` → reviewer code-entry'da qotadi (`MAC_4.2.2_DIAGNOSIS.md §1 case-2`). HOW: demo akkauntda 2FA'ni vaqtincha o'chiring + boshqa sessiyalarni logout qiling (SMS fresh keladi), YOKI `code.vipads.uz` backend doim joriy kodni qaytarsin.
3. **[P0] ❓ Release archive haqiqatan sandboxed + Distribution imzolangan ekanligini tasdiqlash.** — Release config `Telegram-Sandbox.entitlements` (sandbox=TRUE, get-task-allow YO'Q) ishlatadi (tasdiqlangan, `project.pbxproj:9024`), lekin **archive chiqargandan keyin** `codesign -d --entitlements` bilan real `.app` ni tekshirish shart. HOW: §SIGNING bo'limidagi regression-check.
4. **[P0] ❓ Sparkle.framework App Store binary'ga embed BO'LMASLIGINI tasdiqlash.** — Sparkle hali Frameworks (link) phase'da (`project.pbxproj:3527`), lekin Embed phase'da YO'Q (tasdiqlangan). MAS o'z-o'zini yangilovchini taqiqlaydi; agar archive Sparkle binary'sini ichiga olsa rad etiladi. HOW: archive'dan keyin `ls Fenixuz.app/Contents/Frameworks/ | grep -i sparkle` — bo'sh bo'lishi shart.
5. **[P0] ⏳ Distribution sertifikat + Mac App Store provisioning profile + Installer sertifikat yaratish/import qilish.** — `Apple Distribution: Vipads MCHJ` + `3rd-Party Mac Developer Installer: Vipads MCHJ` + `uz.fenixuz.app` uchun MAS profil. Hozir faqat `Apple Development` mavjud. HOW: §SIGNING.
6. **[P0] ⏳ ASC metadata'da hech qanday "Telegram" so'zi/logosi bo'lmasligi.** — 4.1(a) + 2.3.1. Binary tozalangan (✅), lekin ASC listing (name/subtitle/keywords/description/screenshots) tekshirilishi shart. HOW: §ASC-METADATA.
7. **[P0] ⏳ GPL manba kodini nashr qilish.** — Telegram litsenziyasi fork'lardan manba nashrini talab qiladi; 5.2/legal. HOW: §LEGAL.
8. **[P0] ❓ `ITSAppUsesNonExemptEncryption` qiymatini Telegram-class crypto uchun to'g'ri belgilash.** — hozir `false` (`Info.plist:39`). Telegram MTProto + E2E shifrlashdan foydalanadi; bu exemption'ga tushadimi-yo'qmi aniqlanishi kerak. HOW: §EXPORT.

---

## A. App Review Guidelines — rad etish xavflari

### A.1 — 2.1 App Completeness + reviewer demo login

- [ ] **[P0] ❓ Demo account real kontent bilan to'ldirilgan** — yuqorida P0 #1. WHY: 2.1 — "include demo account info … if your app includes a login"; bo'sh akkaunt 4.2.2 ga olib keladi. HOW: ops, demo SIM'ga 8–15 chat/media.
- [ ] **[P0] ❓ Demo login Release build'da end-to-end ishlaydi** — yuqorida P0 #2. WHY: 2.1 — reviewer login'dan o'ta olishi shart. HOW: `MAC_4.2.2_DIAGNOSIS.md §5.2` — Release build, toza profil, telefon → auto-kod → (auto-parol) → chatlar ko'rinadi.
- [ ] **[P1] ✅ App Review Notes matni tayyor (demo creds + auto-fill timing)** — `APP_REVIEW_NOTES.md` mavjud. WHY: 2.1(a) — generic notes rad etiladi. HOW: ASC → version → App Review Information → Notes ga `APP_REVIEW_NOTES.md` orasidagi `=====` blokini paste qiling.
- [ ] **[P1] ⏳ App Preview video (15–30s) tayyorlash** — calls / screen share / drag-drop / menu-bar shortcut / multi-window. WHY: repeat 4.2.2 uchun eng ishonarli artefakt (`MAC_4.2.2_DIAGNOSIS.md §3(c)`). HOW: QuickTime screen recording, ASC'ga upload + Notes'da timestamp havola.
- [ ] **[P1] ❓ Release build toza ishga tushadi (Debug-only Sparkle/Update path Release'da yo'q)** — `#if !APP_STORE` bilan o'ralgan (`AppUpdateViewController.swift:9`, `AppDelegate.swift:197/490/1098…`), Release `-D'APP_STORE'` (`Release.xcconfig:17`) → kod compile bo'lmaydi. WHY: 2.1 — launch crash = rad. HOW: Release build qilib, bir marta oching.
- [ ] **[P2] ❓ Placeholder/"Lorem ipsum"/"Coming soon" yo'q** — fork stub'lari (AI Chatbot tab disabled, Tasks tab olib tashlangan) reviewer'ga bo'sh pane ko'rsatmasligini tekshiring. WHY: 2.1 — incomplete bundle. HOW: har bir Settings bo'limini qo'lda oching.

### A.2 — 2.3.1 / 2.3.7 Accurate Metadata

- [ ] **[P0] ⏳ ASC: app name = "Fenixuz" (≤30), "Telegram" yo'q** — WHY: 2.3.1 — "promoting … services it does not offer"; 4.1. HOW: ASC → App Information → Name.
- [ ] **[P0] ⏳ ASC: subtitle (≤30) "Telegram" trademark + narx/`Free` so'zlarisiz** — WHY: 2.3.7 — subtitle "should not reference other apps … or make unverifiable claims"; `references/apple/metadata-forbidden-words.md` blocklist. HOW: ASC → version → Subtitle.
- [ ] **[P0] ⏳ ASC: keywords (≤100) "telegram", "telegram messenger" trademark + "free"/"cheap" yo'q** — WHY: 2.3.7 — "don't pack metadata with trademarked terms". HOW: ASC → version → Keywords (vergul, probelsiz).
- [ ] **[P1] ⏳ ASC: description'da "Telegram" faqat zarur kontekstda** — "third-party client for the Telegram messaging network" kabi tavsifiy ishlatish mumkin, lekin app nomi sifatida emas. WHY: 4.1 nominal-use chizig'i. HOW: ASC → version → Description.
- [ ] **[P1] ✅ Binary'da user-visible "Telegram" yo'q** — MainMenu.xib titles, `PRODUCT_NAME=Fenixuz`, window title, process nomi tozalangan (`FORK_NOTES.md §3.11`; grep'da residual topilmadi). WHY: 4.1(a) repeat rejection sababi edi. HOW: allaqachon bajarilgan; `grep 'title="Telegram"' Telegram-Mac/*.lproj/MainMenu.xib` bo'sh.
- [ ] **[P1] ⏳ Screenshots haqiqiy app'dan, "Telegram"/narx overlay'siz, mock device emas** — WHY: 2.3.10. HOW: §ASC-METADATA screenshot specs.
- [ ] **[P2] ❓ `tg://` / `telegram://` URL scheme'lari (`Info.plist:32-34`) reviewer'ga muammo bermaydi** — deep-link uchun kerak (FORK_NOTES ataylab saqlagan); 2.3.1 yashirin funksiya emas. WHY: dormant feature emasligini ko'rsatish. HOW: o'zgartirmaslik; Notes'da kerak bo'lsa izohlash.

### A.3 — 3.1.1 In-App Purchase (eng nozik band)

- [ ] **[P0] ❓ IAP gate hook'lari Release binary'da ham ishlaydi** — manba'da 9 fayl × 10 hook mavjud (`FENIXUZ_HOOKS.md`; grep tasdiqladi: `ChatInterfaceInteraction.swift:827`, `InAppLinks.swift:1318`, `WebpageModalController.swift`, `PremiumBoardingController.swift:1670/1775`, `GiveawayModalController.swift:1343`, `PremiumGiftController.swift:612`, `PremiumGiftingController.swift`, `PreviewStarGiftController.swift`, `Star_ListScreen.swift`). WHY: 3.1.1 — fiat-card digital obuna IAP'siz = rad (iOS'da aynan shu rad etgan). HOW: Release build'da Premium/Stars/Gift/bot-invoice/`t.me`-deep-link/WebApp-invoice tugmalarini bosib, har birida block-alert chiqishini tasdiqlang.
- [ ] **[P0] ✅ Settings'da Premium/Stars/TON/Business/Gift menyusi yashirilgan** — `AccountViewController.swift:~658-687` butunlay kommentariyada (`FORK_NOTES.md §3.9`). WHY: 3.1.1 — sotib bo'lmaydigan obunani ko'rsatmaslik. HOW: bajarilgan.
- [ ] **[P0] ✅ IAP block alert matni neytral (redirect CTA yo'q)** — `FenixuzL10n.swift:325/333`: "Premium unavailable" / "Premium subscriptions are not available in this app." WHY: "install official Telegram… subscribe there" 4.1 re-risk edi (`MAC_4.2.2_DIAGNOSIS.md §2.3`); olib tashlangan. HOW: bajarilgan.
- [ ] **[P1] ❓ `pull upstream` dan keyin hook'lar tushib qolmaganini tasdiqlash** — WHY: `FENIXUZ_HOOKS.md` ogohlantiradi: hook silent-drop = keyingi submit rad. HOW: `grep -rn "FenixuzAppStoreIAP" Telegram-Mac/*.swift` = 10 ta call-site bo'lishi shart.
- [ ] **[P1] ❓ Stars (XTR) top-up ham bloklangan** — `Star_ListScreen.swift:1395` `shouldBlockIAP` (unconditional). WHY: Stars Apple-approved bo'lsa-da, fork StoreKit receipt'ini Telegram serveriga submit qila olmaydi → "buy" ishlamaydi → 2.1 buzilgan IAP. HOW: Release'da Stars top-up tugmasini bosib block-alert tasdiqlang.
- [ ] **[P2] ✅ Bir martalik fizik tovar invoice'lari (non-subscription, XTR emas) bloklanmaydi** — `shouldBlock(invoice:)` detection: `currency != XTR && subscriptionPeriod != nil`. WHY: 3.1.5(a) — fizik tovarlar IAP ishlatmasligi kerak; ularni bloklash noto'g'ri bo'lardi. HOW: detection rule to'g'ri (`FENIXUZ_HOOKS.md`).

### A.4 — 4.2 / 4.2.2 Minimum Functionality

- [ ] **[P0] ❓ Demo account boy kontent (= A.1 #1)** — 4.2.2 takrorining asosiy sababi. WHY: "shouldn't primarily be … content aggregators" — bo'sh klient shu taassurot beradi. HOW: demo seeding.
- [ ] **[P1] ✅ To'liq native AppKit app (web wrapper emas)** — WKWebView yo'q, MTProto binary protocol. WHY: 4.2.2. HOW: `APPLE_REVIEW_REPLY_v2.md` da native funksiyalar ro'yxati (calls, screen share, drag-drop, Share extension, Spotlight) — web'da imkonsiz.
- [ ] **[P1] ⏳ Resolution Center reply v2 yuborish** — `APPLE_REVIEW_REPLY_v2.md` (yangi, kuchli, App Preview/live-call taklifi bilan). WHY: noaniq repeat 4.2.2 ni reviewer bilan to'g'ridan-to'g'ri hal qilish. HOW: `=====` blokini ASC Resolution Center'ga paste; eski `APPLE_REVIEW_REPLY.md` ni QAYTA ishlatmang.

### A.5 — 4.1 Copycats (name/logo residue)

- [ ] **[P0] ✅ App nomi/process/menu "Fenixuz"** — `FORK_NOTES.md §3.11`. WHY: 4.1(a) — "Telegram" nomi repeat rejection sababi edi. HOW: bajarilgan.
- [ ] **[P0] ✅ App icon = qizil phoenix (Telegram logosi emas)** — `Assets.xcassets/AppIcon.appiconset/Logo_*.png`. WHY: 4.1(c) — "cannot use another developer's icon … without approval". HOW: bajarilgan; barcha o'lchamlar (16–1024) mavjud.
- [ ] **[P1] ❓ ASC metadata + screenshots'da "Telegram"/Telegram logo yo'q** — A.2 bilan bir xil. WHY: 4.1 metadata'ga ham taalluqli. HOW: ASC tekshiruvi.
- [ ] **[P2] ✅ In-feature "Telegram Premium" matni ataylab qoldirilgan** — service nomi (app nomi emas); reviewer Premium UI'ni faqat block-alert ko'rinishida ko'radi. WHY: nominal-use; xavfsiz. HOW: `FORK_NOTES.md §3.11` "tegilmagan" ro'yxati.

### A.6 — 4.3 Spam / duplicate

- [ ] **[P1] ⏳ Boshqa Telegram fork'laridan farqlanish (description'da)** — Universal Purchase iOS bilan, + fork-only feature'lar (chat PIN lock, Ghost mode, voice-to-text, edited-history, AI integration). WHY: 4.3(b) — "indistinguishable from what's already widely available". HOW: ASC description'da differensiatorlarni aniq sanab o'ting.
- [ ] **[P2] ✅ Bitta bundle ID (`uz.fenixuz.app`), ko'p variant emas** — WHY: 4.3(a) — "don't create multiple Bundle IDs of the same app". HOW: bajarilgan.

### A.7 — 5.1.1 / 5.1.2 Privacy & data use

- [ ] **[P0] ❓ In-app account deletion (5.1.1(v)) Settings'da ko'rinadi va ishlaydi** — Real deletion mavjud: `PrivacyAndSecurityViewController.swift:417-437` (Delete My Account / auto-delete timer) + `TermsModalController.swift:121` `engine.auth.deleteAccount(reason: "GDPR")`. **DIQQAT:** `AccountViewController.swift:322` dagi "Delete account" — bu **logout** (`logoutFromAccount`), real deletion emas — uni 5.1.1(v) dalili sifatida olmang. WHY: "if your app supports account creation, you must also offer account deletion within the app". HOW: Release'da Settings → Privacy & Security → Delete My Account ochilib, ishlashini tasdiqlang (yashirilmagan).
- [ ] **[P1] ✅ Privacy policy mavjud (Telegram privacy)** — Telegram tarmog'i klienti. WHY: 5.1.1(i) — ASC + in-app privacy policy URL. HOW: §ASC-METADATA — Privacy Policy URL maydoni.
- [ ] **[P1] ❓ App Privacy "nutrition label" (ASC) ⇔ haqiqiy yig'ilgan data mos** — `PrivacyInfo.xcprivacy` da: PhoneNumber, Name, UserID, Messages, PhotosOrVideos, AudioData, OtherUserContent, ContactInfo, PreciseLocation (barcha linked, tracking=false, AppFunctionality) + CrashData, PerformanceData (not-linked). WHY: 5.1.2 — label ⇔ collection mos kelmasa rad. HOW: §ASC-PRIVACY — manifestdagi har bir type'ni ASC App Privacy oynasiga kirit.
- [ ] **[P1] ✅ `NSPrivacyTracking=false`, `NSPrivacyTrackingDomains` bo'sh** — `PrivacyInfo.xcprivacy:5-8`. WHY: ATT — fork reklama tracking qilmaydi. HOW: bajarilgan; ATT prompt kerak emas (IDFA yo'q).
- [ ] **[P1] ❓ AppCenter (Analytics/Crashes) Release'da faol emasligini tasdiqlash** — `submodules/AppCenter/*.framework` link qilingan (`project.pbxproj:6842-6851`), lekin kod'da `AppCenter.start` **chaqirilmaydi** (grep bo'sh) → dead/legacy. WHY: 5.1.2 — agar faol bo'lsa data-collection deklaratsiyasi + uchinchi-tomon manifest kerak; faol bo'lmasa label'da analytics SDK ko'rsatmaslik. HOW: archive'dan keyin `AppCenter*.framework` embed bo'lmaganini tasdiqlang; bo'lsa link'dan olib tashlashni ko'rib chiqing (kod o'zgarmaydi, faqat pbxproj).
- [ ] **[P2] N/A Sign in with Apple (4.8)** — kerak emas: Telegram phone-number auth ishlatadi, uchinchi-tomon ijtimoiy login yo'q (grep tasdiqladi). WHY: 4.8 faqat ijtimoiy login bo'lsa. HOW: hech narsa.
- [ ] **[P2] ❓ NSAppTransportSecurity `NSAllowsArbitraryLoads=true` (`Info.plist:47-51`) oqlangan** — MTProto custom DC ulanishlari uchun. WHY: ATS exception reviewer e'tiborini tortishi mumkin, lekin messaging protokoli uchun normal. HOW: kerak bo'lsa Notes'da "MTProto requires direct DC connections" deb izohlash.

### A.8 — 5.6 Developer Code of Conduct

- [ ] **[P1] ✅ Repeat-violation siyosatiga rioya** — 4.1/3.1.1 rad etishlari to'g'ri (silent-removal emas) tuzatilgan, sun'iy metadata yo'q. WHY: 5.6 — takroriy/egregious buzilish = account termination. HOW: har bir tuzatish halol (gate haqiqatan ishlaydi, demo halol). Mualliflik to'g'ri (Vipads MCHJ).

---

## B. Mac App Store TEXNIK darvozalar

### B.1 — App Sandbox (MAJBURIY)

- [ ] **[P0] ✅ Release main target sandboxed** — `project.pbxproj:9024` Release config → `Telegram-Sandbox.entitlements` da `com.apple.security.app-sandbox = true`. WHY: MAS'da sandbox majburiy ([Apple: sandbox required for MAS](https://developer.apple.com/forums/thread/739482)). HOW: bajarilgan.
- [ ] **[P0] ❓ DIQQAT — `Telegram-Mac.entitlements` (sandbox=FALSE, get-task-allow=TRUE) faqat DEBUG'da** — `project.pbxproj:9256` Debug config shu faylni ishlatadi. Agar pbxproj qayta yozilsa Release adashib bunga o'tmasligini tasdiqlash shart. WHY: sandbox=false bilan MAS'ga submit = darhol rad. HOW: regression: `xcodebuild -showBuildSettings -configuration Release | grep CODE_SIGN_ENTITLEMENTS` → `Telegram-Sandbox.entitlements` bo'lishi shart.
- [ ] **[P0] ✅ Share extension + FocusIntents sandboxed** — `TelegramShare.entitlements` + `FocusIntents.entitlements` ikkalasida `app-sandbox=true`. WHY: barcha bundle'lar sandboxed bo'lishi shart. HOW: bajarilgan.

### B.2 — Capability entitlement'lar + mos Info.plist usage string'lar

Har bir entitlement uning ishlatish-sababi (usage string) bilan juftlanishi shart, aks holda runtime crash + rad.

- [ ] **[P0] ✅ `com.apple.security.network.client` + `network.server`** (Sandbox.entitlements:22-25) — MTProto ulanishlari + calls (P2P server). WHY: messaging tarmoq klienti. HOW: bajarilgan.
- [ ] **[P0] ✅ `com.apple.security.device.camera` + `NSCameraUsageDescription`** (Sandbox.entitlements:17; Info.plist:52) — video xabarlar/qo'ng'iroqlar. WHY: 5.1.1(iv) — purpose string majburiy. HOW: bajarilgan.
- [ ] **[P0] ✅ `com.apple.security.device.audio-input` + `NSMicrophoneUsageDescription`** (Sandbox.entitlements:14; Info.plist:64) — voice/calls. WHY: purpose string. HOW: bajarilgan.
- [ ] **[P0] ✅ `com.apple.security.personal-information.location` + `NSLocation*UsageDescription`** (Sandbox.entitlements:26; Info.plist:58-61) — joylashuv yuborish + auto-night theme. WHY: purpose string. HOW: bajarilgan. ⚠️ `NSLocationAlwaysUsageDescription` (Info.plist:58) macOS'da `NSLocationWhenInUse` yetarli bo'lishi mumkin — ❓ ortiqcha "Always" reviewer savol tug'dirmasin.
- [ ] **[P0] ✅ `com.apple.security.files.user-selected.read-write`** (Sandbox.entitlements:20) — chatga fayl drag-drop/save. WHY: sandbox file access. HOW: bajarilgan.
- [ ] **[P0] ✅ `com.apple.security.files.downloads.read-write` + `NSDownloadsFolderUsageDescription`** (Sandbox.entitlements:18; Info.plist:54) — chatdan fayl saqlash. WHY: purpose string. HOW: bajarilgan.
- [ ] **[P1] ✅ `NSSpeechRecognitionUsageDescription`** (Info.plist:68) — voice-to-text (fork feature). WHY: SFSpeechRecognizer purpose string. HOW: bajarilgan. ❓ Agar on-device bo'lsa entitlement shart emas, lekin string zarar qilmaydi.
- [ ] **[P1] ✅ `com.apple.developer.maps`** (Sandbox.entitlements:5) — joylashuv xaritasi. WHY: MapKit. HOW: bajarilgan; ASC capability'da Maps yoqilganini tasdiqlang.
- [ ] **[P1] ❓ Apple Events / Automation** — `com.apple.security.automation.apple-events` YO'Q (grep bo'sh). WHY: agar app boshqa app'larni AppleScript bilan boshqarmasa kerak emas; **qo'shmang** ([ASC bu entitlement'ni yangi qo'shilsa rad qilishi mumkin](https://developer.apple.com/forums/thread/108526)). HOW: hozir yo'q — to'g'ri.
- [ ] **[P2] ❓ Printing** — `com.apple.security.print` YO'Q. WHY: agar app chop etmasa kerak emas. HOW: chat-export-print kerak bo'lsa qo'shing, aks holda yo'q.
- [ ] **[P1] ❓ `com.apple.security.cs.disable-library-validation`** — Sandbox.entitlements'da YO'Q (faqat Debug Telegram-Mac.entitlements:7-8 da bor). WHY: MAS'da library-validation o'chirilishi qo'shimcha tekshiruv talab qiladi; sandboxed Release'da bo'lmasligi yaxshi. HOW: tasdiqlangan — Release'da yo'q. Agar dinamik framework yuklashda crash bo'lsa, bu kerak bo'lishi mumkin — archive'ni test qiling.

### B.3 — Hardened Runtime + taqiqlangan distribution entitlement'lar

- [ ] **[P0] ✅ `ENABLE_HARDENED_RUNTIME = YES`** — `project.pbxproj:9034` (Release main), share/focus targets'da ham. WHY: notarization/MAS uchun ([Apple: hardened runtime required for notarization](https://eclecticlight.co/2021/01/07/notarization-the-hardened-runtime/)). HOW: bajarilgan.
- [ ] **[P0] ❓ `com.apple.security.get-task-allow` Release'da YO'Q** — `Telegram-Sandbox.entitlements` da yo'q (faqat Debug `Telegram-Mac.entitlements:9-10` da). Standart export uni avtomatik strip qiladi, **lekin temporary exception hech qachon berilmaydi** ([Apple: get-task-allow exception not granted for MAS](https://afine.com/to-allow-or-not-to-get-task-allow-that-is-the-question)). WHY: get-task-allow bilan MAS submit = rad. HOW: archive'dan keyin `codesign -d --entitlements - Fenixuz.app | grep get-task-allow` = bo'sh bo'lishi shart.
- [ ] **[P1] ✅ Hardened-runtime JIT/unsigned-memory exception'lari YO'Q** — `allow-jit`, `allow-unsigned-executable-memory`, `disable-executable-page-protection`, `allow-dyld-environment-variables` — hech biri Release entitlements'da yo'q (grep bo'sh). WHY: bular MAS scrutiny'sini oshiradi. HOW: tasdiqlangan — yo'q.

### B.4 — Sparkle self-updater (MAS taqiqlaydi — O'CHIRILGAN holatda QOLSIN)

- [ ] **[P0] ✅ Sparkle kod APP_STORE build'da compile bo'lmaydi** — `AppUpdateViewController.swift:9` `#if !APP_STORE`; Release `-D'APP_STORE'`. WHY: MAS o'z-o'zini yangilovchini taqiqlaydi. HOW: bajarilgan.
- [ ] **[P0] ❓ Sparkle.framework archive'ga embed BO'LMAYDI** — Frameworks (link) phase'da bor (`project.pbxproj:3527`, weak BUILT_PRODUCTS_DIR ref), lekin **Embed phase'da YO'Q** (tasdiqlangan: faqat `TelegramShare.appex`, fonts, palettes embed). WHY: agar binary Sparkle'ni ichiga olsa MAS rad. HOW: archive'dan keyin `ls Fenixuz.app/Contents/Frameworks/ | grep -i sparkle` = bo'sh. Agar bor bo'lsa — Frameworks link phase'dan Sparkle'ni APP_STORE config uchun olib tashlash kerak.
- [ ] **[P1] ✅ `SFEED_URL` `*.telegram.org` ga ishora qilmaydi** — `Release.xcconfig:14` = `https://127.0.0.1/none.xml` (FORK_NOTES.md §3.8, §7). WHY: upstream URL fork binary'sini rasmiy Telegram bilan almashtirardi. HOW: bajarilgan — re-enable so'ralsa STOP (CLAUDE.md §7).

### B.5 — App Groups + Keychain-sharing migration

- [ ] **[P0] ✅ App Group = `ZDBP5RSRZF.uz.fenixuz.app`** — barcha 4 entitlements faylida (Sandbox/Share/Focus). WHY: ZDBP5RSRZF team prefiksi + yangi bundle. HOW: bajarilgan (FORK_NOTES.md §7.4 migration tugagan).
- [ ] **[P0] ✅ Keychain-access-group = `ZDBP5RSRZF.uz.fenixuz.app`** — `Telegram-Sandbox.entitlements:28-32`. WHY: shared keychain. HOW: bajarilgan.
- [ ] **[P1] ❓ Legacy group migration (`uz.fenixuz.macapp` → `uz.fenixuz.app`) bir martalik ishlaydi** — `Config.swift:legacyGroup` mavjud. WHY: eski o'rnatilgan user'lar (agar bo'lsa) data'sini yo'qotmasligi uchun. HOW: birinchi MAS submit yangi o'rnatish — legacy migration faqat oldingi direct-distribution user'lar uchun; test qiling.
- [ ] **[P1] ❓ ASC App Store Connect'da App Group + Keychain Sharing + Maps capability'lari `uz.fenixuz.app` App ID'da yoqilgan** — WHY: provisioning profil bu capability'larni o'z ichiga olishi shart. HOW: Apple Developer → Identifiers → `uz.fenixuz.app` → Capabilities.

### B.6 — Private API usage scan (keng tarqalgan MAS rad)

- [ ] **[P1] ✅ Umumiy private-API pattern'lari topilmadi** — `_UIApplication`, `setStatusBar`, `method_exchangeImplementations`, `com.apple.springboard` h.k. grep'i Telegram-Mac/*.swift'da bo'sh. WHY: 2.5.1 — private framework/API = rad. HOW: yengil skan o'tdi. ⚠️ **Bu to'liq emas** — MAS binary'ni chuqurroq tahlil qiladi (ayniqsa `submodules/tg_owt` WebRTC, native C/C++ core). HOW: birinchi submit'da ITMS private-API ogohlantirishlariga tayyor turing.
- [ ] **[P2] ❓ tg_owt / tgcalls private symbol'lari** — WebRTC ba'zan `mach_*` / IOKit symbol'lar ishlatadi. WHY: native call stack MAS static analysis'ga tushadi. HOW: ASC upload natijasidagi ITMS-90338/90087 ogohlantirishlarni kuzating.

### B.7 — Bundle metadata texnik kalitlari

- [ ] **[P1] ✅ `LSApplicationCategoryType = public.app-category.social-networking`** — `Info.plist:41-42`. WHY: MAS category majburiy. HOW: bajarilgan.
- [ ] **[P1] ❓ `LSMinimumSystemVersion` = `$(MACOSX_DEPLOYMENT_TARGET)` = 10.15** — `Info.plist:45-46`; Release deployment target 10.15 (`project.pbxproj:9069`). WHY: 10.15 (Catalina) MAS'da hali qabul qilinadi, lekin **❓ Xcode 26 / macOS 26 SDK bilan 10.15 target'i deprecation ogohlantirishi berishi mumkin**; share/focus targets 13.0. HOW: build SDK = current (macOS 26.x) ekanligini tasdiqlang ([2026-04-28 deadline: current SDK majburiy](https://dev.to/alanwest/apples-april-sdk-deadline-is-here-your-app-might-get-rejected-5di7)). 10.15 minimum maqbul, lekin asosiy app + extension'lar deployment target nomuvofiqligini (10.15 vs 13.0) tekshiring.
- [ ] **[P1] ✅ Built with current SDK (macOS 26.x, Xcode 26)** — `FORK_NOTES.md §2`: SDK MacOSX26.5, Xcode 26. WHY: ASC current-SDK talabini qondiradi. HOW: bajarilgan.
- [ ] **[P1] ❓ MAS receipt yo'q bo'lsa app crash qilmaydi** — sandboxed MAS app birinchi launch'da receipt validatsiyasi qilsa va receipt yo'q bo'lsa `exit(173)` qaytarishi mumkin (upstream Telegram-Mac da bu xatti-harakat bormi tekshiring). WHY: receipt-yo'q crash = reviewer'da launch fail = 2.1. HOW: `grep -rn "appStoreReceiptURL\|exit(173)\|receipt" Telegram-Mac/*.swift` — agar receipt-check bo'lsa, yo'q-receipt holatini graceful qiling.
- [ ] **[P2] ✅ Version/build alignment: main + share CFBundleVersion = 61, MARKETING_VERSION = 1.0.0** — `Info.plist:38` + `TelegramShare/Info.plist:CFBundleVersion 61`. WHY: MAS app + extension bir xil version/build talab qiladi. HOW: bajarilgan; `tools/sync_share_version.sh` ham mavjud.
- [ ] **[P2] ✅ Copyright = "Copyright © 2026 Fenixuz"** — `Info.plist:56-57`. WHY: joriy yil + Fenixuz brendi. HOW: bajarilgan.

---

## C. Signing & build pipeline

- [ ] **[P0] ⏳ `Apple Distribution: Vipads MCHJ` sertifikat** — Apple Developer → Certificates → Mac App Distribution. WHY: MAS binary Distribution cert bilan imzolanishi shart. HOW: Xcode → Settings → Accounts → Manage Certificates, yoki Developer portal'dan yaratib import.
- [ ] **[P0] ⏳ `3rd-Party Mac Developer Installer: Vipads MCHJ` sertifikat** — WHY: MAS `.pkg` installer imzosi uchun. HOW: Developer portal → Certificates → Mac Installer Distribution.
- [ ] **[P0] ⏳ Mac App Store provisioning profile (`uz.fenixuz.app`)** — capability'lar (App Groups, Keychain, Maps, camera, mic, location) bilan. WHY: MAS profil entitlement'larni qamrab olishi shart. HOW: Developer portal → Profiles → Mac App Store profil, yoki Automatic signing'ga tayaning.
- [ ] **[P0] ❓ `CODE_SIGN_IDENTITY = "";` (bo'sh) yo'qligini tasdiqlash** — `FORK_NOTES.md §6.1` pitfall: bo'sh identity + Automatic = ad-hoc archive → Organizer "No Team Found in Archive". WHY: ad-hoc archive submit qilib bo'lmaydi. HOW: `grep -n 'CODE_SIGN_IDENTITY = "";' Telegram.xcodeproj/project.pbxproj` = bo'sh chiqishi shart (regression check).
- [ ] **[P0] ❓ `DEVELOPMENT_TEAM = ZDBP5RSRZF` barcha targetlarda** — `project.pbxproj` da main/share/focus = ZDBP5RSRZF (tasdiqlangan). WHY: noto'g'ri team = signing fail / Universal Purchase buziladi. HOW: `xcodebuild -showBuildSettings -configuration Release | grep DEVELOPMENT_TEAM` = ZDBP5RSRZF.
- [ ] **[P1] ⏳ Archive → Distribute App → "App Store Connect" → `.pkg` export** — WHY: MAS yetkazib berish formati `.pkg`. HOW: Xcode → Product → Archive → Organizer → Distribute App → App Store Connect → Upload (yoki Export `.pkg` keyin Transporter/asc).
- [ ] **[P1] ⏳ Upload: Xcode Organizer / Transporter / `asc` CLI** — WHY: binary ASC'ga yuklash. HOW: Organizer "Upload" eng oddiy; muqobil — Transporter.app yoki `xcrun altool`/`asc upload`.
- [ ] **[P1] ❓ Archive'dan keyin to'liq codesign verifikatsiya (regression bundle)** — WHY: barcha P0 sign/entitlement gap'larni bitta qadamda tutadi. HOW:
  ```bash
  APP=Fenixuz.app
  codesign -dvvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Sandbox|flags"   # Authority=Apple Distribution, TeamIdentifier=ZDBP5RSRZF
  codesign -d --entitlements - "$APP" 2>&1 | grep -E "app-sandbox|get-task-allow"   # sandbox=true, get-task-allow YO'Q
  ls "$APP/Contents/Frameworks/" | grep -iE "sparkle|appcenter"                      # bo'sh bo'lishi kerak
  spctl -a -vvv --type install "$APP"                                                 # accepted
  ```

---

## D. Export compliance / encryption

- [ ] **[P0] ❓ `ITSAppUsesNonExemptEncryption` qiymati Telegram-class crypto uchun to'g'ri** — hozir `false` (`Info.plist:39`, share ham). Telegram MTProto + secret-chat E2E shifrlashdan foydalanadi. WHY: noto'g'ri exemption = ASC har build'da savol beradi yoki export-compliance buzilishi. HOW: live tekshirish kerak ([Apple export compliance docs](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-export-compliance-information/)) — Telegram'ning o'z app'lari odatda exemption talab qiladi (shifrlash standart/cheklangan maqsadlarda), lekin custom MTProto uchun **YES + self-classification (CCATS) ko'rib chiqilishi kerak**. Hozircha ❓ — submitdan oldin aniqlang; agar exemption tasdiqlanmasa `false` → noto'g'ri deklaratsiya.
- [ ] **[P1] ❓ Agar YES bo'lsa: yillik self-classification report ASC'ga upload** — WHY: non-exempt crypto uchun CCATS/self-classification talab. HOW: ASC → App → App Information → Export Compliance.
- [ ] **[P2] ❓ Fransiya export deklaratsiyasi (agar FR'da tarqatilsa)** — WHY: Fransiya custom-crypto app'lar uchun alohida deklaratsiya. HOW: ASC export-compliance bo'limidagi Fransiya checkbox; FR storefront'da bo'lsa.

---

## E. App Store Connect setup & metadata

### E.1 — App record + Universal Purchase

- [ ] **[P0] ⏳ ASC'da macOS app record yaratish / iOS `uz.fenixuz.app` bilan bog'lash** — WHY: Universal Purchase iOS + macOS bir xil bundle ID + bir xil team talab qiladi. HOW: ASC → mavjud `uz.fenixuz.app` app → "+ macOS" platform qo'shing (yangi app record EMAS — bir app, ikki platforma).
- [ ] **[P1] ⏳ Pricing = Free** — WHY: fork hech narsa sotmaydi. HOW: ASC → Pricing and Availability → Free.

### E.2 — Metadata maydonlari (barcha "Telegram"siz — A.2 bilan birga)

- [ ] **[P0] ⏳ Name = "Fenixuz"** — HOW: ASC → App Information → Name.
- [ ] **[P0] ⏳ Subtitle (≤30, trademark/narx yo'q)** — HOW: ASC → version → Subtitle.
- [ ] **[P0] ⏳ Keywords (≤100, "telegram"/"free"/"cheap" yo'q)** — HOW: ASC → version → Keywords.
- [ ] **[P1] ⏳ Description (4000, differensiatorlar + "third-party client for the Telegram network" nominal-use)** — HOW: ASC → version → Description.
- [ ] **[P2] ⏳ Promotional text (170, ixtiyoriy)** — HOW: ASC → version → Promotional Text.
- [ ] **[P1] ⏳ Support URL + Marketing URL + Privacy Policy URL (HTTPS, ishlaydigan)** — WHY: 1.5 + 5.1.1(i). HOW: ASC → App Information / version → URLs.

### E.3 — Screenshots + icon

- [ ] **[P0] ⏳ macOS screenshots — 16:10, kamida 1280×800 (tavsiya 2560×1600), PNG/JPEG sRGB/P3, alpha YO'Q** — qabul qilinadigan o'lchamlar: 1280×800 / 1440×900 / 2560×1600 / 2880×1800 ([aso.dev 2026](https://aso.dev/app-store-connect/screenshots/)). Kamida 1, tavsiya 3, maksimum 10. WHY: 2.3.10 + ASC majburiy. HOW: real `Fenixuz.app` oynasidan screenshot (mock device emas, "Telegram"/narx overlay'siz). ⚠️ Reviewer'ga boy native app ko'rsatish — bo'sh oyna emas (4.2.2).
- [ ] **[P0] ✅ App icon 1024×1024** — `Logo_1024.png` mavjud (qizil phoenix). WHY: ASC icon majburiy, alpha/rounded-corner yo'q. HOW: bajarilgan; ASC avtomatik asset catalog'dan oladi.
- [ ] **[P1] ⏳ App Preview video (15–30s, on-device capture)** — A.1 #4 bilan bir xil. WHY: repeat 4.2.2. HOW: ASC → version → App Previews.

### E.4 — App Privacy "nutrition label" (A.7 bilan birga)

- [ ] **[P1] ⏳ ASC App Privacy ⇔ `PrivacyInfo.xcprivacy` mos** — Data Linked to You: Phone Number, Name, User ID, Messages, Photos/Videos, Audio Data, Other User Content, Contact Info, Precise Location (purpose: App Functionality). Not Linked: Crash Data, Performance Data. Tracking: NONE. WHY: 5.1.2 — label ⇔ collection. HOW: ASC → App Privacy → Get Started → har bir type'ni manifestga mos kirit.

### E.5 — Age Rating questionnaire (2026-01-31 dan majburiy)

- [ ] **[P0] ⏳ Age Rating 7-step / 21-question questionnaire to'ldirish** — WHY: 2026-01-31 dan Apple barcha app'larni yangi questionnaire'ga ko'chirdi; javobsiz submit to'xtaydi. Telegram-class UGC messaging app → Q1.2.2 (UGC) = YES, Q1.2.3 (messaging/calls) = YES → ehtimoliy rating **17+ (US) / 16+ (EU)** (cheklanmagan UGC + foydalanuvchilararo aloqa). HOW: `/age-rating` skill bilan `APP_STORE_AGE_RATING.md` generatsiya qiling, keyin ASC → App Information → Age Rating → Edit ga kiriting. ⚠️ UGC=NO belgilash 2.3.1 rad ettiradi.
- [ ] **[P1] ⏳ Age restriction mechanism (UGC content > app rating)** — §1.2.1(a)/4.7.5. WHY: UGC app'lar ortiqcha-yosh kontent uchun filter/flag/block taqdim etishi kerak (Telegram'da mavjud — reporting/block). HOW: upstream Telegram reporting/block ishlashini tasdiqlang.

### E.6 — Content rights

- [ ] **[P1] ⏳ Content Rights deklaratsiyasi** — "Does your app contain third-party content?" → GPL manba nashr etilgan + Telegram trademark ishlatilmagan. WHY: ASC content-rights savol. HOW: ASC → App Information → Content Rights.

---

## F. Legal / GPL

- [ ] **[P0] ⏳ Fork manba kodini ommaviy nashr qilish** — WHY: Telegram (overtake/TelegramSwift) GPL/litsenziyasi fork'lardan manba nashrini talab qiladi; nashr qilmaslik = litsenziya buzilishi + 5.2. HOW: GitHub'da public repo (Fenixuz patchlari bilan) yoki kamida manba'ga havola; `git push` faqat user ruxsati bilan (CLAUDE.md).
- [ ] **[P0] ✅ O'z production api_id/api_hash (test pair emas)** — `Config.swift`: `apiId=35846757`, `apiHash=67cdc52f…` (Fenixuz production, CLAUDE.md bilan mos). WHY: Telegram TOS — production app'lar o'z API credential'laridan foydalanishi shart, `17349/344583…` test pair emas. HOW: bajarilgan.
- [ ] **[P1] ⏳ Trademark scrub (ASC + binary)** — A.2/A.5 bilan birga. WHY: "Telegram" so'zlik/figurali belgi nominal-use chegarasida. HOW: ASC metadata + screenshots'da Telegram logo/wordmark yo'qligini tasdiqlang.

---

## G. FORK_NOTES'dan olib o'tilgan ochiq ishlar

- [ ] **[P1] ✅/❓ FORK_NOTES §7.1 — Mac App Store deploy** — bu hujjat aynan shu rejani to'liq qamrab oladi (C + E bo'limlari). Eski "ru.keepcoder.Telegram → uz.fenix..." satrlari **stale** — bundle allaqachon `uz.fenixuz.app`. HOW: §7.1'ni shu hujjat bilan almashtiring.
- [ ] **[P1] ✅ FORK_NOTES §7.4 — Bundle/AppGroup/Keychain migration** — `uz.fenixuz.macapp → uz.fenixuz.app` + `ZDBP5RSRZF.*` group/keychain bajarilgan (B.5). HOW: tugagan; faqat legacy-migration runtime test (B.5).
- [ ] **[P1] ✅ FORK_NOTES §3.9 — Mac IAP gate to'liqlash** — invoice + StoreKit hook'lari endi mavjud (A.3; FENIXUZ_HOOKS.md). §3.9 "menu-only" izohi **stale** — yangilang. HOW: Release binary'da hook'larni qo'lda tasdiqlang (A.3 #1).
- [ ] **[P2] ❓ FORK_NOTES §7.3 — crash reporting (ixtiyoriy)** — Firebase olib tashlangan, AppCenter dead. MAS uchun MetricKit (native) yoki Sentry tavsiya. WHY: ixtiyoriy; crash reporting MAS'da Apple Organizer orqali ham keladi. HOW: keyinga qoldirsa bo'ladi.

---

## H. Submit-dan oldingi yakuniy checklist

- [ ] **[P0]** Demo account boy kontent bilan to'ldirilgan + fresh-code test o'tdi (Release build, toza profil, kirib chatlar ko'rinadi)
- [ ] **[P0]** Release archive: sandbox=true, get-task-allow YO'Q, `Apple Distribution: Vipads MCHJ`, TeamIdentifier=ZDBP5RSRZF (codesign regression o'tdi)
- [ ] **[P0]** `Fenixuz.app/Contents/Frameworks/` da Sparkle/AppCenter YO'Q
- [ ] **[P0]** IAP gate hook'lari Release'da ishlaydi (Premium/Stars/Gift/bot-invoice/deep-link/WebApp → block-alert)
- [ ] **[P0]** ASC metadata (name/subtitle/keywords/description/screenshots) "Telegram"/narx so'zlarisiz
- [ ] **[P0]** Age Rating questionnaire to'ldirilgan (17+/16+ kutilmoqda)
- [ ] **[P0]** GPL manba nashr etilgan
- [ ] **[P0]** `ITSAppUsesNonExemptEncryption` qiymati aniqlandi (exemption tasdiqlangan yoki YES+self-classification)
- [ ] **[P1]** App Review Notes (`APP_REVIEW_NOTES.md`) + Resolution Center reply v2 (`APPLE_REVIEW_REPLY_v2.md`) paste qilingan
- [ ] **[P1]** App Preview video upload qilingan
- [ ] **[P1]** In-app account deletion (Settings → Privacy → Delete My Account) ishlaydi va yashirilmagan
- [ ] **[P1]** Distribution + Installer sertifikatlar + MAS profil tayyor
- [ ] **[P1]** App Privacy nutrition label ⇔ `PrivacyInfo.xcprivacy` mos
- [ ] **[P2]** Support / Marketing / Privacy Policy URL'lar ishlaydi (HTTPS)

---

## 🎯 Eng muhim 3 ish (boshqasidan oldin)

1. **Demo account `+998335999479` ni 8–15 real chat/guruh/kanal + media bilan to'ldiring** + stale-code'ni hal qiling (2FA off / fresh-code). Bu 4.2.2 takrorining eng ehtimolli sababini yo'q qiladi — kod emas, ops.
2. **Release archive'ni codesign bilan tasdiqlang** (sandbox=true, get-task-allow yo'q, Apple Distribution, Sparkle/AppCenter embed yo'q) + Distribution/Installer sertifikat va MAS profil yarating.
3. **ASC metadata + Age Rating + GPL manba + export-compliance** ni yakunlang ("Telegram"siz metadata, 17+ rating, public manba, `ITSAppUsesNonExemptEncryption` to'g'ri).

> **Yo'qotmang:** IAP gate hook'larini (FENIXUZ_HOOKS.md), Sparkle-disabled holatini (CLAUDE.md §7), Fenixuz rename'ni (FORK_NOTES §3.11). Bularning birortasi tushib qolsa Apple qayta rad etadi.
