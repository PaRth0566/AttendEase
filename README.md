<div align="center">
  <h1>AttendEase</h1>
  <img src="assets/icon/app_icon2.png" alt="Attend Ease Logo" width="120" height="120" /><br /><br />
<a href="https://github.com/PaRth0566/AttendEase/releases/download/v1.0.5/AttendEase.apk"><img src="https://img.shields.io/badge/Download-APK-2D80EC?logo=android" width="226" ></a> &nbsp&nbsp&nbsp&nbsp
<a href="https://attendease-cbc6f.web.app"><img src="https://img.shields.io/badge/Open_Web-APP-ff9a00?logo=firebase&logoColor=FFCA28" width="230"></a><br><br>
<a href="https://github.com/neo999in/AttendEase-backend"><img src="https://img.shields.io/badge/Backend-Repository-339933?logo=nodedotjs" width="180" ></a><br><br>
<a href="https://github.com/PaRth0566/AttendEase/releases/tag/v1.0.5"><img src="https://img.shields.io/badge/version-1.0.5-22C55E?labelColor=333333&logo=github&logoColor=white" alt="version 1.0.5" height="24" hspace="6" vspace="3" /></a><img src="https://img.shields.io/badge/platforms-Android%20%7C%20Web-A855F7?labelColor=333333" alt="platforms: Android and Web" height="24" hspace="6" vspace="3" /><a href="https://docs.flutter.dev/release/archive"><img src="https://img.shields.io/badge/Flutter-3.10.7+-00CCFF?labelColor=333333&logo=flutter&logoColor=00CCFF" alt="Flutter 3.10.7+" height="24" hspace="6" vspace="3" /></a><a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-D97706?labelColor=333333&logo=opensourceinitiative&logoColor=white" alt="MIT license" height="24" hspace="6" vspace="3" /></a>
</div>

---
### 📖 Description

<img src="assets/cover.png" alt="Attend Ease Cover" width="100%" />


**AttendEase** is an attendance management system designed to streamline how students track and analyze their academic presence. Upload your college attendance PDF once and AttendEase turns it into a live picture of where you stand: per-subject percentages, a day-by-day calendar, and a straight answer to the question that actually matters — *can I skip tomorrow?*

Reports are parsed locally on-device by default. Gemini handles the web upload path through a token-authenticated Node.js backend, so your API keys never ship inside the client.

> [!IMPORTANT]
> **Disclaimer**: AttendEase is an automated tool. We are not liable for any calculation inaccuracies or resulting consequences. Please verify your attendance with official college records.
>
> **Privacy Note**: On Android your PDF is parsed entirely on-device and never leaves your phone. On the web, the file is sent to our Node.js backend for one-time Gemini analysis only after you give explicit consent. It is held in memory rather than written to disk, and is not stored on our servers.


---

### 📸 Screenshots

<div align="center">
  <a href="assets/screenshots.png"><img src="assets/screenshots.png" alt="Dashboard, PDF sync, calendar, profile and reports screens" width="100%" /></a>
  <p><sub><i>Dashboard · Smart PDF extraction · Monthly calendar · Profile &amp; cloud sync · PDF reports</i><br />Tap the strip to open it full size.</sub></p>
</div>
  
---

### ✨ Features

#### 📥 Getting your data in
- 📄 **On-Device PDF Parser**: Attendance reports are parsed locally with `syncfusion_flutter_pdf`, anchored on the date/time/status pattern of each row so the file never has to leave your device. It reads subject names that carry digits and hyphens (`Applied Mathematics-IV`, `.NET`, `C++`) instead of truncating them, keeps two variants of one stem (`…-III` and `…-IV`) from collapsing into a single merged subject, and pulls the semester off the *Academic Session* line without mistaking a date fragment for it. Runs on a background isolate, so the UI stays responsive.
- 📲 **Open With / Share to AttendEase (Android)**: Tap an attendance PDF anywhere on the phone — WhatsApp, Gmail, Drive, any file manager — pick AttendEase, and the same import runs, whether the app was cold or already open. The file is read natively (the chooser hands over a `content://` URI that Dart's `File` can't touch) and verified by its `%PDF-` header rather than its filename before it ever reaches the parser.
- ⚡ **One-Tap Sync & SAP Shortcut**: The dashboard's AppBar pairs a shortcut to SVKM's SAP portal — where the report is downloaded — with a one-tap sync button, so "fetch, then import" is a couple of taps from the home screen. That button, the full Sync screen, and Open-With all run one shared import path rather than three copies that quietly drift apart.
- 🤖 **AI-Powered PDF Ingestion (Web)**: Gemini reads the report on the web upload path, behind a consent checkbox and a data-retention disclosure.
- 🔁 **Model Fallback Chain**: The backend walks Gemini 3 Flash → 2.5 Flash → 3.1 Flash Lite → 2.5 Flash Lite, advancing only on `503 overloaded`, so a busy model degrades instead of failing.
- ♻️ **Non-Destructive Re-Import**: Refreshing a report replaces only report-derived rows inside that report's date range. Your subject IDs, planned timetable, and records outside the range survive untouched — and your name, programme, academic year, and semester follow the report header, so a new term updates the profile instead of stranding last year's on it. The whole import runs in a single transaction — what used to be a several-hundred-row, one-fsync-per-row wait that felt like a hang.
- 🧑‍🎓 **Different-Owner Guard**: A routine sync folds a report into what's already there. But when it detects a *different student or course* — a friend's report opened to check their attendance — it stops before writing and asks, rather than silently unioning two people's curricula into one dashboard. Confirming rebuilds the app from that report alone; declining imports nothing. The check is conservative, so your own next report never trips it.
- 🧹 **Ghost Record Cleanup**: If the PDF covers a date but has no lecture for a subject, a stray manual record there is treated as a ghost and removed. The report is the authority.
- ✍️ **Manual Setup Path**: No PDF? Add subjects, set criteria, and build a weekly timetable by hand.

#### 📊 Making sense of it
- 🎯 **"Can I Skip?" Projections**: Per subject, AttendEase computes the exact number of future lectures you can miss and the actual upcoming dates they fall on — solved from `attended / (total + x) ≥ required`, not estimated.
- 📆 **Cumulative Week Strip**: A Mon→Sun verdict for the current week where green days *stack*. Two green days mean you can take both off, not two offers that quietly conflict. An expensive Wednesday no longer hides a cheap Friday, and on Sunday the strip rolls over to the coming week.
- 🧠 **History-Derived Timetable**: Your weekly footprint is inferred from real attendance history rather than a configured timetable, so swaps and replacement lectures stay visible. A slot counts only when it recurs (≥2 dates) and was seen within 21 days, so a schedule that shifted mid-semester drops its stale slots.
- 🧾 **Honest Status Handling**: `P` / `A` / `NU` / `NC` are each treated on their own terms. `NU` and `NC` never inflate your totals, but `NU` still counts as evidence a lecture was held, while `NC` doesn't. *Attendance Granted* (`AG`) normalizes to present.
- 📈 **Subject Deep-Dive & Reports**: Per-subject detail screens plus a generated PDF report you can share straight from the app.
- 📅 **Smart Calendar**: Visualize history, edit individual lectures, and see future in-range days projected from your timetable.

#### 🔐 Platform & trust
- 🛡️ **Locked-Down Firestore Rules**: Strict UID ownership on user documents; bug reports are create-only with field, type, and length validation; everything else denied by default.
- 🔑 **Authenticated Backend**: Every analysis request requires a verified Firebase ID token, rate-limited to 5/min per IP, capped at 5 MB, and validated as a real PDF by magic bytes — not just its extension.
- 🚦 **Login Throttling**: 5 failed attempts trigger a 60-second lockout with a live countdown.
- ☁️ **Conflict-Safe Cloud Sync**: Firestore transactions with optimistic locking, so a stale device can't clobber a newer backup. Guest users are isolated from backup and restore entirely.
- 🚪 **Account-Isolated Sign-Out**: Signing out wipes the local database and preferences on *both* Android and web — where the store is IndexedDB and used to be skipped, which left one account's subjects visible to the next person on a shared browser. The router's cached "has setup data?" verdict is invalidated in the same step, so nobody inherits the previous session's screen.
- 🔄 **Verified OTA Updates**: Checks GitHub Releases, downloads with live progress, and verifies the APK against its published **SHA-256** before handing it to Android's installer. Download URLs are restricted to official GitHub hosts; drafts and prereleases are ignored.
- 📝 **"What's New" Sheet**: Release notes are parsed from the GitHub release body and shown exactly once after an install completes, with a 20-entry history.

#### 🎨 Look and feel
- 💧 **Liquid Glass Navigation**: A genuinely translucent bottom bar whose selection pill is a brighter lens on glass, not a solid fill — with per-theme tuning to hold WCAG AA contrast on a surface that has no guaranteed background.
- 🫧 **Container Transform Routing**: Tapped cards physically expand into full pages, implemented on top of GoRouter so URLs, deep links, and the back stack keep working.
- 🎛️ **Tokenized Design System**: Colors, dimensions, motion, and breakpoints live in `lib/theme/` as tokens and `ThemeExtension`s — replacing roughly 50 hardcoded color calls and their per-screen `isDark` branching.
- 🌗 **Unified Theme Crossfade**: A dark-mode toggle fades the entire app on one timeline instead of half the UI snapping at the theme midpoint.
- 👆 **Swipe-To-Switch Tabs**: Fling between Dashboard, Calendar, and Profile with the nav pill tracking your finger frame for frame, driven by an additive `alignmentOverride` patch on the glass tab bar.
- 🔤 **Text Scale Guardrails**: System font scaling is clamped to 0.9–1.15 (tighter on narrow phones) so large accessibility settings enlarge text instead of truncating subject names.
- 🌐 **Installable PWA & Clean First Paint**: Branded icons and a manifest make the web build installable, and the page paints the app's own scaffold colour straight from HTML while the engine boots — no white flash, no stale Flutter-logo placeholder, and a `prefers-color-scheme` match so a dark-mode visitor isn't flashed a light screen on the way in.

---

### 🛠 Requirements
Before you begin, ensure you have met the following requirements:
* **Flutter SDK**: `^3.10.7` (Dart SDK constraint declared in `pubspec.yaml`).
* **Dart SDK**: Bundled with the matching Flutter release.
* **Node.js**: `v22.0.0` or higher — the backend is an ES-module project, and `file-type` v22 sets the floor at Node 22.
* **IDE**: [Android Studio](https://developer.android.com/studio) or [VS Code](https://code.visualstudio.com/) with Flutter/Dart plugins.
* **Platform**:
    - **Android**: Uses Flutter's default `minSdk`. Requires the *Install unknown apps* permission for in-app updates.
    - **Web**: Modern browser with WebGL and JavaScript enabled (the glass shaders degrade gracefully without WebGL).
* **Firebase**: Your own project. `firebase_options.dart` and `google-services.json` are intentionally untracked — see [Getting Started](#-getting-started).

---

### 🚀 Getting Started

```bash
git clone https://github.com/PaRth0566/AttendEase.git
cd AttendEase
flutter pub get
```

**1. Wire up Firebase.** Credentials are deliberately not in the repo. Create a Firebase project, enable **Email/Password** and **Google** sign-in plus **Cloud Firestore**, then generate the config:

```bash
dart pub global activate flutterfire_cli

# writes lib/firebase_options.dart
# and android/app/google-services.json
flutterfire configure

firebase deploy --only firestore:rules
```

For Google Sign-In on Android, add your debug and release **SHA-1** fingerprints in the Firebase console — a missing SHA-1 is the single most common cause of sign-in failure, and the app reports it distinctly from a network error.

**2. Run the app.**

```bash
flutter run                    # Android
flutter run -d chrome          # Web
```

**3. Run the backend** (only needed for the web AI upload path):

```bash
cd backend
npm install

# .env: GEMINI_API_KEY=your_key
# plus Google application-default
# credentials for firebase-admin
npm run dev
```

**4. Verify your changes.**

```bash
flutter analyze
flutter test
```

---

### 🛠 Tech Stack

<p align="left"><a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-00CCFF?labelColor=333333&logo=Flutter&logoColor=00CCFF" alt="Flutter" height="30" hspace="4" vspace="3" /></a><a href="https://dart.dev/"><img src="https://img.shields.io/badge/Dart-40C4FF?labelColor=333333&logo=Dart&logoColor=40C4FF" alt="Dart" height="30" hspace="4" vspace="3" /></a><a href="https://ai.google.dev/"><img src="https://img.shields.io/badge/Google_AI_Studio-8E75FF?labelColor=333333&logo=GoogleGemini&logoColor=8E75FF" alt="Google AI Studio" height="30" hspace="4" vspace="3" /></a><a href="https://firebase.google.com/"><img src="https://img.shields.io/badge/Firebase-FFCA28?labelColor=333333&logo=Firebase&logoColor=FFCA28" alt="Firebase" height="30" hspace="4" vspace="3" /></a><br /><a href="https://nodejs.org/"><img src="https://img.shields.io/badge/Node.js-339933?labelColor=333333&logo=nodedotjs&logoColor=339933" alt="Node.js" height="30" hspace="4" vspace="3" /></a><a href="https://www.sqlite.org/"><img src="https://img.shields.io/badge/SQLite-007FFF?labelColor=333333&logo=SQLite&logoColor=007FFF" alt="SQLite" height="30" hspace="4" vspace="3" /></a><a href="https://render.com/"><img src="https://img.shields.io/badge/Render-7B2BF9?labelColor=333333&logo=render&logoColor=7B2BF9" alt="Render" height="30" hspace="4" vspace="3" /></a></p>

**Key packages**

| Package | Role |
| :--- | :--- |
| `syncfusion_flutter_pdf` | On-device PDF parsing |
| `pdf` · `share_plus` | Report generation and sharing |
| `sqflite` · `..._ffi_web` | Local persistence (schema v8) |
| `firebase_auth` · `google_sign_in` | Authentication |
| `cloud_firestore` | Cloud backup and restore |
| `go_router` | Routing with redirect guards |
| `liquid_glass_widgets` | Glass nav surfaces (vendored) |
| `package_info_plus` · `http` · `crypto` | OTA updates, SHA-256 checks |
| `file_picker` · `url_launcher` | Upload and external links |
| `connectivity_plus` | Network reachability |

**Backend**: Express 4, `firebase-admin` (ID-token verification), `express-rate-limit`, `multer` (in-memory), `file-type` (magic-byte PDF validation).

> [!NOTE]
> **Vendored dependency**: `third_party/liquid_glass_widgets/` is a patched copy of `liquid_glass_widgets` 0.18.4, wired in via `dependency_overrides`. Upstream squashes the nav pill *along* its direction of travel — the inverse of squash-and-stretch — which necked the pill to ~0.6× width on a full-width trip so it read as vanishing rather than sliding. The driving constants are literals with no parameter reaching them, so the fix required owning the source. Every edit is tagged `AttendEase patch` and pinned by tests. Read `third_party/liquid_glass_widgets/README.attendease.md` before upgrading.

---

### 📂 Folder Structure
```text
AttendEase/
├── lib/
│   ├── screens/     # Feature UI (auth, dashboard, calendar…)
│   ├── widgets/     # Glass buttons, overlays, nav icons
│   ├── theme/       # Tokens: colors, dimens, motion
│   ├── services/    # Auth, sync, PDF import, OTA update
│   ├── database/    # SQLite helper + DAOs
│   ├── models/      # Subject, TimetableEntry
│   ├── utils/       # Skip projections, attendance math
│   └── router/      # GoRouter config + redirect guards
├── backend/         # Express server for Gemini
├── test/            # Unit, widget, regression tests
├── third_party/     # Vendored liquid_glass_widgets
├── firestore.rules  # Security rules
└── assets/          # Icons, images, static files
```
---

### 🧪 Tests

`flutter test` covers the parts most likely to break silently:

- **Attendance logic** — the week-skip planner is pinned against a real 127-row report: cumulative budgets aren't offered twice, an unsafe day doesn't abort the walk, a real absence shrinks the rest of the week, stale slots don't leak in, and `NU`/not-conducted rows stay out of the plan. Plus replacement lectures and future-day calendar projection.
- **PDF parsing** — real SAP reports: subject names carrying digits and hyphens survive intact, two variants of one stem don't collapse into a merged subject, and the semester is read off the *Academic Session* line without a date fragment leaking in as "Semester 1".
- **Report ownership** — a report for a different student or course raises the replace dialog, a continuation of your own reports does not (so a routine sync is never interrupted), and the profile header follows the imported report.
- **Account isolation** — signing out wipes the local database on every platform, so the next user starts clean.
- **Editing & input** — delete-with-undo and the undo snackbar's placement, not-conducted-lecture visibility, and target-percentage input formatting.
- **Update pipeline** — semantic version comparison: numeric rather than lexicographic ordering, tags and build metadata accepted, downgrades and equal versions rejected.
- **Navigation & layout** — pill drag, jelly direction *and area conservation*, icon replay, overlay layout, container transforms, bottom-nav safe-area insets, and web desktop rendering.
- **Contrast** — the glass nav bar's WCAG AA ratios are asserted, not eyeballed, because "pick a color and hope" is how a translucent bar becomes unreadable.

> [!NOTE]
> Each test file opens its own SQLite database. `flutter test` runs files concurrently in one shared temp directory, so a single fixed filename meant whichever isolate lost the race died with "database is locked" — a private name per file removes the contention outright.

---

### 🤝 Contributing

Issues and pull requests are welcome. Please run `flutter analyze` and `flutter test` before opening a PR, and keep new colors, spacing, and motion routed through the tokens in `lib/theme/` rather than inlining literals.

Found a bug? The app has a built-in bug reporter under **Profile → Report a Bug**.

---
### 📄 License

Released under the <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?labelColor=333333" alt="license" height="24" align="center" /></a>
