# Releasing AttendEase

The runbook for shipping a new version. AttendEase is distributed through the
**Google Play Store** as an Android App Bundle (`.aab`). Play builds every
device-specific APK from that bundle and signs them with the **Play app-signing
key**, so the app can only be updated by Play — a sideloaded APK signed with the
upload key no longer matches an installed build and cannot update it.

Updates reach users two ways, both handled by Play, not by app code:

- **Play's own auto-update** — the standard Store behaviour once a build is on a
  track the user is on.
- **In-app updates** — `lib/services/play_update_service.dart` asks Play on
  startup whether a newer build exists and, if so, downloads it in the background
  (flexible flow) and prompts to restart. This only works for a build **installed
  from Play**; on dev/sideloaded/emulator builds it is a silent no-op.

Read [The things that break a release](#the-things-that-break-a-release) first if
you only have a minute.

---

## 1. Bump the version

Two files, and the second one is the trap.

**`pubspec.yaml`** — the source of truth for CI, web, and a fresh clone:

```yaml
version: 1.1.2+8
```

**`android/local.properties`** — gitignored and machine-local, but **it overrides
pubspec for Android builds**:

```properties
flutter.versionName=1.1.2
flutter.versionCode=8
```

Keep `versionCode` in step with the `+N` build number, and **increase it every
upload** — Play rejects an `.aab` whose `versionCode` is equal to or lower than
one already on the track. This is the number Play uses to tell "newer" from
"older", so it is also what makes an in-app update appear.

> **Why the second file matters.** The Gradle plugin reads `flutter.versionName`
> and `flutter.versionCode` from `local.properties` when present, so a stale value
> there stamps the bundle with the wrong version even though `pubspec.yaml` is
> correct. The file is gitignored, so nothing in CI or code review catches it —
> check it by hand.

Also update any version strings/badges in `README.md` (search for the old
version).

---

## 2. Pre-flight checks

All must be clean before you build:

```bash
flutter analyze
flutter test
flutter build web --release
```

If you have removed or added a dependency since the last build, run
`flutter clean` **first**. The generated `web_plugin_registrant.dart` is cached
and will keep importing a package you just deleted, failing the build with
`Couldn't resolve the package '<name>'`.

`in_app_update` and `in_app_review` are Android-only. They register no web
plugins, so the web build must still compile and render text (see the
[web-font appendix](#appendix-if-web-text-disappears)).

---

## 3. Build the App Bundle

```bash
flutter build appbundle --release
```

Output lands at `build/app/outputs/bundle/release/app-release.aab`. This — not an
APK — is what you upload to Play.

### Confirm the bundle carries the new version

```bash
# path may differ by build-tools version
"$LOCALAPPDATA/Android/sdk/build-tools/36.1.0/aapt2.exe" dump badging \
  build/app/outputs/bundle/release/app-release.aab | grep "^package"
```

Expect:

```
package: name='com.parthm.attendease' versionCode='8' versionName='1.1.2' ...
```

If `versionName`/`versionCode` are the *old* values, go back to step 1, fix
`android/local.properties`, and rebuild.

### Watch the R8 output

`in_app_update` bundles `com.google.android.play:app-update`, which ships its own
consumer ProGuard rules. If a **release-only** failure or a new
`play.core`/`play.app-update` R8 warning appears, add a scoped
`-dontwarn`/`-keep` in [android/app/proguard-rules.pro](android/app/proguard-rules.pro)
— never a blanket wildcard (see that file's own guidance). The existing
`-dontwarn com.google.android.play.core.*` lines target the older split-install
classes and are unrelated but harmless.

---

## 4. Upload to Play and write the release notes

Play Console → **AttendEase** → **Testing → Internal testing** (or your closed
track) → **Create new release**.

1. **Upload** `app-release.aab`.
2. **Release notes** go in the `<en-US>` (and any other locale) box. **These
   become the "What's new" text on the Play listing** — there is no in-app
   patch-notes sheet anymore, Play shows this. Write plain user-facing bullets;
   there are no parser constraints, only Play's 500-character-per-language limit.
3. **Review + roll out** to the track.

> **In-app update priority (optional).** Flexible updates ignore priority unless
> you add immediate-fallback logic (not currently in the app), so there is nothing
> to set here for the current flow.

---

## 5. Test on a Play-installed build

In-app updates and the review prompt **only work when the app was installed from
Play** — never on `flutter run`, an emulator, or a sideloaded APK (there
`InAppUpdate.checkForUpdate()` throws `ERROR_API_NOT_AVAILABLE`, which the code
swallows and `debugPrint`s).

**In-app update:**

1. Add your Google account as a tester on the track and install AttendEase via the
   Play tester opt-in link.
2. Bump the version (step 1), build (step 3), and upload a **higher `versionCode`**
   build to the **same track**.
3. Open the installed app. After ~1s the flexible update should download in the
   background, then prompt to restart. There is no manual "Check for Updates"
   tile — Play auto-updates and the launch check cover it between them.

**In-app review:**

1. The **Rate AttendEase** tile in Profile always works — it opens the store
   listing.
2. The automatic native prompt (`requestReview()`) fires from the report-sync
   success path, gated: after 3 successful syncs, not the first action, at most
   once per 30 days. Play may still legitimately show **nothing** (quota) — that
   is normal, not a bug, and cannot be forced on demand.
3. A review can only be **submitted** from the **production** track; on
   internal/closed tracks the dialog's submit is disabled, so you can confirm the
   dialog appears but not complete a rating. Once submitted (on production) or
   rated from the store listing, Google aggregates it into the star rating and
   review list on the listing automatically — nothing in the app fetches or
   displays those totals.

---

## 6. Promote to production

When the track has been verified, promote the same release (Play Console →
**Production → Create new release → Add from library**, or promote the track
release). Reuse the release notes. Roll out staged or at 100%.

---

## 7. Deploy the web build

The web app is separate from Play and still ships via Firebase Hosting:

```bash
flutter build web --release
firebase deploy --only hosting
```

Hosting serves `build/web` (see `firebase.json`). Confirm the version rode along:

```bash
cat build/web/version.json    # expect {"version":"1.1.2","build_number":"8", ...}
```

> Flutter's asset copy adds new files but **does not prune removed ones**. If you
> deleted an asset this cycle, a stale copy can linger in `build/web/assets/` and
> get deployed. `flutter clean` before the release build avoids it.

The landing page's "Get it on Google Play" button points at
`https://play.google.com/store/apps/details?id=com.parthm.attendease` — web users
cannot use Play in-app updates, so the store listing is the correct destination.

---

## The things that break a release

| Symptom | Cause | Fix |
|---|---|---|
| Play rejects the upload | `versionCode` equal to or lower than one already on the track | Step 1 — always increase `+N` and `flutter.versionCode` |
| Bundle carries the old version | Stale `flutter.versionName`/`versionCode` in `android/local.properties` | Step 1, rebuild, re-verify with `aapt2 dump badging` |
| In-app update never appears in dev | Build was not installed from Play (`flutter run`/sideload/emulator) | Expected — test on a Play-installed build (step 5) |
| Review dialog never appears | Play quota, or not installed from Play, or gate not met | Normal — use the Rate tile to reach the listing directly |
| New `play.app-update` R8 warning at release | Consumer ProGuard rules from the app-update lib | Add a scoped `-dontwarn`/`-keep`, never a wildcard (step 3) |
| Web text renders blank | Inter font not bundled | See the appendix |

---

## Appendix: if web text disappears

Icons and card outlines paint but **no text**, with the layout still reserving
space for the missing labels. This is a solved problem — do not re-diagnose it.

The cause is a text font that is not bundled. With no `fontFamily` set, Flutter
falls back to Roboto, and the CanvasKit renderer does not ship Roboto — it
fetches it from `fonts.gstatic.com` on first paint. A slow, blocked or offline
request means every string is measured correctly and then painted with no glyphs.
That network dependency is why it used to appear and vanish between deploys.

What holds it fixed, all of which must stay in place:

- `assets/fonts/` — `Inter-Regular.ttf`, `Inter-SemiBold.ttf`, `Inter-Bold.ttf`,
  plus `OFL.txt` (Inter is OFL-licensed; keep the licence with the fonts).
- The `fonts:` block in `pubspec.yaml` declaring family `Inter` at 400/600/700.
- `AppTheme.fontFamily` applied to both `lightTheme` and `darkTheme`.
- `AppTheme._f()` stamping the family onto **component** theme text styles.
  `ThemeData.fontFamily` only reaches `textTheme`, so a raw `TextStyle` in
  `appBarTheme`, `dialogTheme`, `snackBarTheme` or a button style would resolve
  to Roboto and render blank on its own.

To confirm a build is safe:

```bash
flutter build web --release
cat build/web/assets/FontManifest.json   # Inter must appear
```

The real test is loading the site with `fonts.gstatic.com` blocked, or with
DevTools set to offline. Text must still render.

Do not switch the family to one that is not in `assets/fonts/`, and do not fetch
Inter from Google Fonts' `static/` URLs — Inter now ships there only as a
variable font, so those paths return an HTML 404 that saves as a `.ttf` and fails
later at build or render time.
