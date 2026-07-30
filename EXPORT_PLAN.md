# Chat export — plan and format spec

Goal: bring the official client's "Export chat history" to the Novagram Mac fork.
The feature does **not** exist in `overtake/TelegramSwift` 11.15 (verified by search —
only `ExportedInvitation*`, `ExportProxyModal*`, `ExportMessageLink`, `MediaEditorVideoExport`,
none of which are chat export). It was added in the unpublished 12.x line, so we write it
from scratch.

We do **not** port code from `telegramdesktop/tdesktop` (C++/Qt, GPL-3.0). We match the
**output format** instead — the format is an interface, and reproducing it keeps our code
entirely our own. Reference exports produced by the official macOS client are cached in
`_export-reference/` (gitignored — they contain real chat content).

---

## 1. What the user sees

Chat menu (⋯) → **Export chat history** → settings modal → progress → result modal.

**Settings modal** (`Chat export settings`):

| Control | Values |
|---|---|
| Checkboxes | Photos, Videos, Voice messages, Video messages, Stickers, GIFs, Files |
| Size limit | slider, 0 … 4000 MB — **per-file cap**, not total. 4000 MB because that is the largest file Telegram allows |
| Format | link → sub-modal `Choose export format`: **Human-readable HTML** / **Machine-readable JSON** / **Both** |
| Path | link → folder picker, default `Downloads/<App> Desktop/` |
| From / to | date range links, default `the oldest message` → `present` |
| Buttons | Cancel / Export |

**Result modal** (`Export Your Data`): "Data export completed.", Total files, Total size,
`Show my data` button (reveals the folder in Finder).

---

## 2. Output layout (measured from the cached references)

### HTML only
```
ChatExport_<YYYY-MM-DD>/
  Chats/
    messages.html          ~57 KB for 83 messages
    css/style.css
    js/script.js
    images/                42 files
```

### JSON only
```
ChatExport_<YYYY-MM-DD>/
  result.json              ~50 KB for 83 messages
```
No css/js/images — JSON is self-contained.

### Both
```
ChatExport_<YYYY-MM-DD>/
  messages.html            ~64 KB
  result.json              ~51 KB
  css/style.css
  js/script.js
  images/                  42 files
```

Note the difference: HTML-only nests under `Chats/`, Both writes at the root. Media
folders (`photos/`, `video_files/`, `voice_messages/`, `files/`, `stickers/`) appear only
when the matching checkbox is on — the cached samples were exported with all media off.

### `images/` — 42 files, 21 icons at 1x and @2x
```
back            media_contact   media_game      media_music     media_shop
media_call      media_file      media_location  media_photo     media_video
media_voice     …
```
We will draw our own set (or use SF Symbols) in the Novagram accent — no asset copying.

---

## 3. JSON schema (extracted from `_export-reference/json-only/result.json`)

### Root
```
name      string     chat title
type      string     chat kind
id        int        chat id
messages  array
```

### Message object — union of keys across 83 messages

Always present:
```
id                  int
type                string     "message" | "service"
date                string     ISO-ish local time
date_unixtime       string     unix seconds, as string
text                string | array[string|object]   plain text, or runs with entities
text_entities       array[object]                   parallel structured form
```

Present on regular messages:
```
from                string     display name
from_id             string     e.g. user id in prefixed form
```

Optional, by feature:
```
reply_to_message_id   int
edited                string      edit timestamp
edited_unixtime       string
reactions             array[object]
forwarded_from        string
forwarded_from_id     string
```

Media (only the keys relevant to the attachment appear):
```
file                  string     relative path inside the export
file_size             int
file_name             string
mime_type             string
media_type            string     seen: "video_file", "voice_message"
duration_seconds      int
width, height         int
thumbnail             string     relative path
thumbnail_file_size   int
photo                 string     relative path
photo_file_size       int
```

Service messages (`type == "service"`):
```
actor        string
actor_id     string
action       string     seen: "pin_message"
message_id   int        target message
```

`text` is polymorphic — a bare string when there is no formatting, otherwise an array
mixing raw strings and `{type, text, …}` objects. `text_entities` always carries the
structured form, so **the writer should emit both** and the reader can use either.

---

## 4. HTML structure (from `_export-reference/both/messages.html`)

42 distinct CSS classes. Skeleton:

```
<html><head>…<body>
  <div class="page_wrap">
    <div class="page_header"> … </div>
    <div class="history">
      <div class="message default clearfix" id="message…">
        <div class="pull_left userpic_wrap"><div class="userpic userpicN"><div class="initials">…</div></div></div>
        <div class="body">
          <div class="pull_right date details" title="…">…</div>
          <div class="from_name">…</div>
          <div class="reply_to details">…</div>
          <div class="media_wrap clearfix">
            <div class="media clearfix pull_left media_video">
              <div class="fill pull_left"></div>
              <div class="body"><div class="title bold">…</div><div class="description">…</div><div class="status details">…</div></div>
            </div>
          </div>
          <div class="text">…</div>
          <div class="reactions"><div class="reaction"><div class="emoji">…</div><div class="userpics">…</div></div></div>
        </div>
      </div>
      <div class="message service" …>
    </div>
  </div>
</body></html>
```

Key classes by frequency: `details`, `clearfix`, `body`, `message`, `date`, `default`,
`pull_right`, `pull_left`, `text`, `userpic`, `initials`, `userpic_wrap`, `from_name`,
`joined`, `userpicN` (1…8, colour variants), `reply_to`, `reaction(s)`, `emoji`,
`media_wrap`, `media`, `media_video`, `fill`, `title`, `description`, `status`, `bold`.

`joined` marks a message grouped under the previous one from the same sender (no repeated
avatar/name). `userpic1…8` cycle avatar background colours.

---

## 5. Build order

Each stage ships something usable on its own.

| # | Stage | Deliverable | Est. |
|---|---|---|---|
| 1 | JSON writer, text only | Working export, no media | ~1 day ✅ **done** |
| 2 | HTML writer + format picker (HTML / JSON / Both) | Parity with the official look | ~1–2 days ✅ **done** |
| 3 | **Server-side history fetch + streaming write** | Whole history, not just cache | ~2 days |
| 4 | Media download queue + per-file size cap | Full export | ~2–3 days |
| 5 | Progress, cancel/resume, date range, folder picker | Reliable flow | ~1 day |

Total ≈ 6–8 days.

### Stage 3 in detail — why it is its own stage

Stages 1–2 read `transaction.withAllMessages`, i.e. **only what is cached on this device**.
A chat you have scrolled 500 messages into exports 500 messages, not its 10-year history.
The official client pulls from the server instead. Closing that gap needs four things that
have to land together — doing paging without streaming will OOM on a large chat:

| Piece | Notes |
|---|---|
| Paging | `messages.getHistory`, 100 per request (server cap), walk `offsetId` backwards until empty |
| `FLOOD_WAIT` handling | Telegram returns the number of seconds to wait; sleep exactly that, then retry the same page |
| Streaming write | Emit JSON/HTML incrementally instead of building one array in memory |
| Progress + resume | Report `fetched / estimated`; persist the last `offsetId` so a cancelled run can continue |

Rough cost at 100 messages/request, ~200–400 ms each plus anti-flood spacing:

| Chat size | Requests | Wall time | JSON (text only) |
|---|---|---|---|
| 5 000 | 50 | ~15–30 s | ~1.5 MB |
| 50 000 | 500 | ~3–5 min | ~15 MB |
| 200 000 | 2 000 | ~12–20 min | ~60 MB |
| 1 000 000 | 10 000 | ~1–1.5 h | ~300 MB |

Nothing here is technically blocked — it is ordinary paged fetching. The only real hazard is
memory, and streaming removes it.

### Where the code goes
- `Telegram-Mac/FenixuzChatExport*.swift` — Fenixuz-owned, keeps merge pain low
- Chat menu hook → log in `FENIXUZ_HOOKS.md` (upstream file)
- Message fetch: `messages.getHistory` via the shared core, paginated
- Media: existing `MediaBox` / fetch pipeline, bounded concurrency

### Open decisions
- Icon set: draw our own vs SF Symbols (avoid copying the official `images/`)
- Where to surface the entry point besides the chat menu (Settings → Data and Storage?)
- Whether to support exporting **all** chats at once (the `Chats/` nesting in HTML-only
  suggests the official client does) or one chat at a time for v1
