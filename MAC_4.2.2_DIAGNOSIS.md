# MAC 4.2.2 DIAGNOSIS — TelegramSwift (Fenixuz fork)

> Submission ID `a0ff9208-00df-4016-9721-4cd5fd7619ce` · Review 2026-06-12 · MacBook Pro 14" (Nov 2024) · Build `1.0.0 (54)`
> Guideline **4.2.2 — Design — Minimum Functionality** · REPEAT rejection ("issues we previously identified still need your attention")
> 4.1(a) Copycats — **DROPPED** (resolved by Telegram→Fenixuz rename). 4.2.2 — **PERSISTS**.

---

## 1. Xulosa

4.2.2 takror chiqishining sababi **login texnik jihatdan buzilganligida EMAS** — demo login network + parsing + UI darajasida to'liq ishlaydi (quyida dalillar bilan isbotlangan). Eng ehtimolli root cause, ishonch darajasi bo'yicha tartiblangan: **(1) — ENG EHTIMOLLI (~70%): demo account `+998335999479` bo'm-bo'sh.** Repo'da seeding kodi umuman yo'q (grep bilan tasdiqlandi), bu raqam shunchaki SMS-forwarder SIM — unda chat/kanal/kontakt/media yo'q. Reviewer muvaffaqiyatli kirsa ham bo'sh uch-panelli oynani ko'radi, bu "mobile web browser'dan farq qilmaydi" degan 4.2.2 hukmiga to'g'ridan-to'g'ri olib keladi. **(2) — EHTIMOLLI (~20%): stale-code login failure.** Forwarder SIM allaqachon o'sha akkauntga login qilingan bo'lsa, Telegram kodni SMS orqali emas, **in-app** yuboradi; `code.vipads.uz` esa eski (stale) kodni qaytarishi mumkin → `PHONE_CODE_INVALID` → reviewer code-entry ekranida qotib qoladi va native UI'ga umuman yetib bormaydi. (Transport ishlaydi, lekin bu kodning *to'g'riligini* kafolatlamaydi.) **(3) — KAM EHTIMOLLI (~7%): stripped/redirect signallari.** Settings'da Premium/Stars/TON/Business/Gift qatorlari comment qilingan; IAP block alert "rasmiy Telegram'ni o'rnating va o'sha yerda obuna bo'ling" deydi — bu redirect taassurotini kuchaytiradi. **(4) — ENG KAM (~3%): reviewer demo login'dan umuman foydalanmagan** (App Review Notes yetarlicha aniq emas). Ishonch bilan ayta olaman: **login pipeline'ni yana "tuzatish" — noto'g'ri yo'l.** Asosiy muammo **login'dan KEYINGI holat** (bo'sh akkaunt), kichik ikkilamchi xavf esa stale-code. Hech qaysi bittasi 100% tasdiqlanmagan, chunki reviewer logini bizda yo'q — lekin dalillar (1)-ni eng kuchli ko'rsatadi.

---

## 2. Dalillar

### 2.1 Demo login ISHLAYDI (texnik jihatdan to'liq) — bu 4.2.2 sababi emas

**Endpoint liveness (shu mashinadan, hozir tekshirildi):**
```
GET  https://code.vipads.uz/auth/request-code  -> HTTP 200  {"code":"57763"}  ~0.55s
POST https://code.vipads.uz/auth/request-code  -> HTTP 405  {"detail":"Method Not Allowed"}
HEAD ... -> HTTP 405, header: `allow: GET`   (server GET-ONLY)
```
- Server **GET-ONLY**. Ilova aynan **GET** qiladi (default), shu sababli **405 ilovaga ta'sir qilmaydi** — 405 noto'g'ri-metod probe'ining natijasi edi. `requestMatchesServer = true`.

**Ilova GET ishlatishi (kod dalili):**
- `packages/FenixuzCore/Sources/FenixuzCore/FenixuzDemoCodeFetcher.swift:288-290` —
  `var request = URLRequest(url: codeUrl)` qurilgan, `request.httpMethod` **hech qachon set qilinmagan** → Foundation default = **GET**. Faqat `cachePolicy = .reloadIgnoringLocalCacheData` (289) va `timeoutInterval = 15` (290) o'rnatilgan. `httpMethod|POST|httpBody|setValue|addValue` uchun grep = **NONE**.
- `codeUrl = https://code.vipads.uz/auth/request-code` (`:105`).
- `extractCode` (`:263-278`): JSON `obj["code"]` ni oladi → `"57763"` (string) → faqat raqamlar → `prefix(6)` → 5 ta raqam → `count >= 4` true → submit qilinadi. Real body bilan tekshirildi, mos keladi.

**Hook wiring (hammasi mavjud, `Telegram-Mac/AuthController.swift`):**
- `:1088` — `FenixuzDemoCodeFetcher.prewarmIfDemo(phoneNumber:)` (phone "Next" da prewarm).
- `:827-833` — `autoFillIfDemo(...)` → `code_entry_c.applyExternalLoginCode(code)` (codeEntry'da auto-fill + auto-submit).
- `:320-322` — `applyExternalLoginCode(_:)` → `code_entry_c.applyExternalLoginCode`.
- `:838` — `dismissIfActive()` (codeEntry'dan chiqilganda polling to'xtaydi).
- `:844` — `autoFillPasswordIfDemo(phoneNumber:)` → 2FA parol `Xabarchi` (0.8s kechikish, one-shot).
- Auto-submit zanjiri: `insertAll(digits)` har raqamni to'ldiradi VA `invoke()` ni chaqiradi (`Auth_CodeEntryContol.swift`), to'liq to'lganda `takeNext?(value)` = real login submit. Ya'ni **fill + submit ikkalasi ham ulangan**.

**Xulosa:** login network + parse + UI bo'yicha **end-to-end ishlaydi**. Reviewer katta ehtimol bilan **ichkariga kirgan** (yoki stale-code tufayli code-entry'da qolgan). 4.2.2 takrori → login'dan keyingi holatga ishora qiladi.

### 2.2 Demo account content risk: **bo'sh (empty-likely)**
- Repo bo'ylab seeding kodi **yo'q**: `seed|demo.*chat|sampleChat|welcome.*message|prefill|populate` grep'i faqat WebRTC/keychain `seed`, emoji `:seedling:`, particle-emitter `seed` larini topdi — **demo-akkauntga chat/kontakt/media joylashtiruvchi kod yo'q**.
- `+998335999479` — Apple demo strategiyasidagi SMS-forwarder SIM. Unda real foydalanuvchi tarixi yo'q → muvaffaqiyatli login ham **bo'sh uch-panelli** oynani beradi.

### 2.3 Stripped / redirect signallari (ikkilamchi)
- **Settings qatorlari comment qilingan** — `Telegram-Mac/AccountViewController.swift:658-687`: Premium / Stars (`stars_purchase_blocked`) / TON / Business / Gift bloki butunlay `//` ostida. Stock Telegram'ga nisbatan kamtarroq menyu.
- **IAP block alert redirect-flavored** — `packages/FenixuzCore/Sources/FenixuzCore/FenixuzL10n.swift:325-335`:
  - `iap_block_title` (en): **"Telegram Premium"**
  - `iap_block_message` (en): **"...please install the official Telegram app from the App Store and subscribe there."**
  - Bu alert `ChatInterfaceInteraction.swift:828`, `PremiumGiftingController.swift:748/806`, `GiveawayModalController.swift:1264/1346`, `WebpageModalController.swift:1878` da chaqiriladi. Reviewer Premium'ga tegsa — "rasmiy Telegram'ni o'rnat" xabari → redirect taassuroti, 4.1 ni qayta xavf ostiga qo'yadi.
- Tasks tab olib tashlangan (`git 1fef1a211`), Sparkle/Update yashirilgan, AI Chatbot tab disabled stub.

### 2.4 Login'dagi kichik nuance (rejection sababi EMAS, faqat hardening uchun)
- **Auto-submit timing race** — `Auth_CodeEntryContol.swift` `invoke()` da `guard !locked else { return }`. Agar bufferdagi kod control hali `locked` paytida yetkazilsa, raqamlar maydonga **yoziladi**, lekin submit "yutilib" ketishi mumkin → reviewer kodni ko'radi, lekin bir marta **Enter** bosishi kerak. Magic-login → manual one-tap'ga aylanadi, **lekin login'ni bloklamaydi**.
- **Digit-count coupling** — `extractCode` `prefix(6)`, lekin `insertAll` faqat `values.count == subviews.count` bo'lsagina ishlaydi. Hozir 5==5 (server 5 raqam qaytaradi, tasdiqlandi), shuning uchun **muammo emas**; Telegram kelajakda 6-raqamli kod bersa silent no-op bo'lardi.

---

## 3. Tuzatish rejasi (Fix plan)

### (a) CODE — faqat agar kerak bo'lsa (login texnik jihatdan ishlamoqda, shuning uchun bu PAST prioritet)

> Login pipeline ishlayapti — uni qayta yozish kerak emas. Quyidagilar faqat **hardening** va **redirect-signalini yumshatish** uchun. Demo parametrlarini (0.5s / 15s / 60s) **O'ZGARTIRMANG** — ular Apple rad etishlaridan kelib chiqqan.

1. **IAP alert redirect CTA'sini olib tashlash** (4.1 qayta xavfini kamaytirish):
   - Fayl: `packages/FenixuzCore/Sources/FenixuzCore/FenixuzL10n.swift:325` va `:333`.
   - `iap_block_title` "Telegram Premium" → neytral, masalan "Premium unavailable".
   - `iap_block_message` dan **"install the official Telegram app ... and subscribe there"** qismini olib tashlash → "This feature is not available in this version." kabi neytral matn. `id747648890` deep-link CTA'ni (`iap_block_open_app_store`) ham olib tashlash.
   - StoreKit gate'ning o'zini **saqlang** (3.1.1 uchun kerak) — faqat matn va deep-link o'zgaradi.

2. **Auto-submit race hardening** (ixtiyoriy, magic-login'ni kafolatlash):
   - Fayl: `Telegram-Mac/Auth_CodeEntryContol.swift` `insertAll` / `invoke`.
   - `insertAll` raqamlarni to'ldirgandan keyin, agar `invoke()` `locked` tufayli o'tkazib yuborilgan bo'lsa, `locked` `false` ga o'tganda keyingi runloop'da submit'ni qayta urinish (`asyncAfter`, `value.count == subviews.count` bilan guard'langan). Demo paramlarga tegmaydi.

3. **Digit-count fallback** (ixtiyoriy, future-proof): `extractCode` ni hardcoded `prefix(6)` o'rniga auth state'dagi haqiqiy `sentCode` uzunligiga moslash.

> **Diqqat:** (a)-bo'limi rejection'ning asosiy sababi emas. Agar vaqt cheklangan bo'lsa, faqat **#1 (IAP matn)** ni bajaring; #2/#3 ni keyinga qoldiring.

### (b) OPS / CONTENT — **ENG YUQORI TA'SIR** (kod emas, operatsiya)

1. **Demo account'ni real kontent bilan to'ldiring** (`+998335999479`):
   - 8-15 ta chat: shaxsiy suhbatlar, 2-3 guruh, 2-3 kanal (obuna bo'lingan).
   - Har xil media: rasmlar, videolar, voice message'lar, fayllar, stickerlar.
   - 5-10 ta kontakt.
   - Maqsad: reviewer kirgach **darhol** boy, ishlaydigan native client ko'rsin — bo'sh oyna emas. Bu 4.2.2 ni hal qiluvchi yagona eng muhim qadam.

2. **Stale-code login muammosini hal qiling:**
   - Variant A: demo akkauntdan **2FA'ni o'chiring** va boshqa barcha sessiyalarni **logout** qiling → Telegram kodni SMS orqali (in-app emas) yuboradi → forwarder yangi kodni oladi → `code.vipads.uz` doim **fresh** kodni qaytaradi.
   - Variant B: `code.vipads.uz` backend'ini har doim **joriy** kodni qaytaradigan qilib sozlang (eski kodni emas).
   - Variant A oddiyroq va ishonchliroq.

### (c) SUBMISSION — reviewerni ishontirish

1. **App Review Notes (ASC) ni qayta yozing** — oldingi rad etilgan matnni **takrorlamang**:
   - Demo phone: `+998335999479`, 2FA password: `Xabarchi`.
   - "Code auto-fills in 2-10s after pressing Next. If it doesn't, press Enter once."
   - Raqamli **"What to try"** ro'yxati: (1) suhbat oching, (2) xabar yuboring, (3) voice/video call boshlang, (4) screen share, (5) faylni chatga drag-drop qiling, (6) menu bar shortcut'larini sinab ko'ring, (7) multi-window oching, (8) akkaunt almashtiring.
   - Verified native feature ro'yxatini (1:1 calls, group calls/streams, screen sharing, share extension, Spotlight, drag-drop, native menu bar, multi-account up to 10, Ghost mode, voice-to-text, chat PIN lock, edited-history, translation) yetkazing.

2. **App Preview video (15-30s)** qo'shing — repeat 4.2.2 uchun eng ishonarli artefakt:
   - Calls, screen share, chatga drag-drop, menu bar shortcut'lar, multi-window ko'rsating.
   - Reviewer Notes'dagi timestamp'larga bog'lang.

3. **Resolution Center** orqali reviewer'dan qayerda qotib qolganini so'rang yoki call so'rang — noaniq 4.2.2 ni matndan ko'ra tezroq hal qiladi.

4. **Release build'ni tekshiring** — Debug-only Sparkle/Update launch crash Release'da yo'qligini bir marta build qilib, ishga tushirib tasdiqlang.

---

## 4. Prioritet — birinchi nima qilish kerak

**#1 (yagona eng yuqori ta'sir): demo account `+998335999479` ni 8-15 ta real chat / guruh / kanal / media bilan to'ldiring** — bu kod emas, operatsiya, va 4.2.2 ning eng ehtimolli sababini (bo'sh akkaunt → "mobile web browser'dan farqsiz") to'g'ridan-to'g'ri yo'q qiladi.

Keyingi tartib:
2. **Stale-code'ni hal qiling** (2FA off + boshqa sessiyalarni logout, yoki backend fresh-code) — login code-entry'da qotib qolmasligi uchun.
3. **App Preview video** + qayta yozilgan **App Review Notes**.
4. **IAP alert matnini** neytrallashtiring (redirect signalini olib tashlang).

> Login pipeline'ni qayta "tuzatishga" **vaqt sarflamang** — u ishlayapti. Asosiy ish ops + submission tomonida.

---

## 5. Tekshiruv — qayta yuborishdan OLDIN login ishlayotganini tasdiqlash

### 5.1 Endpoint smoke-test (toza mashinadan)
```bash
# GET 200 + {"code":"NNNNN"} qaytarishi va ~0.5s ichida javob berishi kerak:
curl -s -w '\nHTTP %{http_code} time=%{time_total}s\n' https://code.vipads.uz/auth/request-code

# 5 marta ketma-ket — har safar 200 va kod bo'lishi kerak (polling barqarorligi):
for i in 1 2 3 4 5; do curl -s -w ' HTTP %{http_code}\n' https://code.vipads.uz/auth/request-code; done
```
Kutilgan: har bir qator `{"code":"NNNNN"} HTTP 200`. Agar 200 emas yoki kod bo'sh bo'lsa — backend muammosi, login'dan oldin tuzating.

### 5.2 To'liq qo'lda login testi (Release build, toza akkaunt holatida)
1. Telegram'ni **Release** konfiguratsiyada build qiling, toza profil bilan ishga tushiring.
2. Phone entry: `+998335999479` kiriting → **Next**.
3. Kuting: kod **2-10s** ichida avtomatik to'lishi va submit bo'lishi kerak (Enter bosmasdan). Agar to'lsa-yu submit bo'lmasa — §3(a)#2 race hardening kerak.
4. 2FA ekrani chiqsa: parol `Xabarchi` avtomatik kiritilishi kerak.
5. **MUHIM:** kirgandan keyin oyna **bo'sh emas** — 8-15 ta chat ko'rinishi kerak (§3(b)#1 bajarilgan bo'lsa). Bo'sh bo'lsa — 4.2.2 yana chiqadi.
6. Adjacent flow'lar: bitta chat oching, xabar yuboring, call tugmasini bosing — native funksiyalar ishlashini tasdiqlang.

**Faqat §5.2 ning 5-qadami (kirgandan keyin chatlar ko'rinishi) muvaffaqiyatli bo'lsa, qayta yuboring.** Compile-success yoki "endpoint 200" — yetarli emas; reviewer ko'radigan holat boy, ishlaydigan client bo'lishi shart.
