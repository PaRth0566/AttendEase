# Store listing text

Source of truth for the Play Store listing copy, one folder per Play locale.
Filenames and the folder layout match what `fastlane supply` expects under
`fastlane/metadata/android/`, so this can be wired into a release script later
without rewriting anything.

```
store_listing/<locale>/title.txt              -> App name          (max 30 chars)
store_listing/<locale>/short_description.txt  -> Short description (max 80 chars)
store_listing/<locale>/full_description.txt   -> Full description  (max 4000 chars)
```

Locales present: `en-US` (source), `hi-IN`, `mr-IN`.

## Getting this into Play Console

There is **no file import for store listing text** in Play Console. Three routes:

1. **Manual (what to do now).** Main store listing for `en-US`. For the others:
   Main store listing -> Manage translations -> Select languages -> add Hindi
   and Marathi -> paste from the files here.
2. **AI / machine translation.** Grow users -> Translations -> Store listings and
   products -> Create order. This translates the English listing itself; it takes
   no input file. Results land under "Review and apply". If you use this instead
   of the `hi-IN` / `mr-IN` files above, paste whatever Play produced back into
   those files so this folder stays the source of truth.
3. **Scripted.** `fastlane supply` reading this tree, or the Play Developer
   Publishing API (`edits.listings.update`, one call per language).

## House rules for edits

- `title.txt` stays `AttendEase` in every locale — it is the brand, not a phrase
  to translate.
- Every claim must be true of the **Android** build. In particular the privacy
  line ("the PDF is never uploaded") holds because Android parses reports with
  `LocalPdfParser`; the Gemini backend upload is web-only. If that ever ships on
  Android, this copy and the Data safety form both have to change.
- No "best", "#1", "download now", no emoji, no testimonials, no third-party
  trademarks — Play's Metadata policy rejects all of these.
- Keep the feature list in sync with the app. Removing a feature means editing
  every locale here, not just `en-US`.
