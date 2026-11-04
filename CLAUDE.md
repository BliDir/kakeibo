# CLAUDE.md

Guidance for Claude Code working in this repository.

## Project

Kakeibo is a native SwiftUI iPhone app (iOS 26+) that reads Japanese receipts on-device and keeps a local expense ledger. No login, no server, no network calls, no third-party SDKs.

Work is tracked in Linear, project **Kakeibo iOS v1.0** (team DailyAdventureGame, issues `DAI-425` to `DAI-456`). Issue titles start with a plan ID such as `[T-12]`. Read the project's design doc, "Kakeibo iOS v1.0 — Design & Technical Plan", before starting a new area.

## Workflow

- One Linear issue = one branch = one pull request. Use Linear's suggested branch name (e.g. `imadeagusdirawan/dai-431-t-10-text-normalizer`).
- Check the issue's "blocked by" relations first. Do not start an issue whose blockers are not done.
- Every acceptance-criteria checkbox in the issue must be met and verifiable by a test or a described manual check before opening the PR.
- Issues labelled **Human task** are for the owner. Do not attempt them; prepare anything they need instead.
- Put the Linear issue ID in the PR title, e.g. `DAI-431 [T-10] Text normalizer`.

## Architecture rules

- `Packages/KakeiboCore`: domain types, `ReceiptParser`, normalizer, era dates, category rules, line geometry, summary math, CSV writer. **Imports Foundation only.** No UIKit, SwiftUI, Vision or SwiftData here.
- `Packages/KakeiboScan`: Vision OCR, VisionKit wrappers, Foundation Models refiner, `ExtractionPipeline`. Depends on Core.
- `Packages/KakeiboStore`: SwiftData models (`VersionedSchema`), `ExpenseRepository`, `PhotoStore`. Depends on Core.
- `App/`: SwiftUI screens and wiring only. Business logic belongs in a package.
- `Kakeibo.xcodeproj` uses folder-synced groups: files added under `App/` or `UITests/` are picked up automatically, so do not edit `project.pbxproj` just to add a file. New packages are added as local package references.
- Money is `Int` yen everywhere. Dates for grouping use `dayKey` (`yyyy-MM-dd`, Asia/Tokyo).
- Every user-facing string goes in `Localizable.xcstrings` with `ja` and `en`.
  Exception: `ExpenseCategory` names (`japaneseName`, `englishName`) live in Core code, because screens show both names together and CSV exports need fixed names. `swift test` cannot compile a String Catalog inside a package.
- The category enum is `ExpenseCategory`, not `Category`: Objective-C's `Category` type makes the short name ambiguous wherever SwiftUI or UIKit is imported.
- Raw values of `ExpenseCategory`, `PaymentMethod`, `Confidence` and `ReceiptField` are stored on disk. Never rename them.
- Field parsers take lines that have already been through `TextNormalizer`. Do not repeat full-width, ¥ or spacing clean-up in a parser; add the rule to `TextNormalizer` with a test.
- Store chains live in `Packages/KakeiboCore/Sources/KakeiboCore/Resources/chains.json`. To add one, append `{"name", "nameEn", "category", "match": [...]}` (`name` must also be in `match`; add OCR variants such as no-hyphen or Latin spellings). Use `"generic": true` with no `name` for words that only set a category (タクシー, クリニック). Add a test in `StoreClassifierTests`.
- When testing normalized Japanese text, compare `unicodeScalars`, not `==`: Swift's `==` treats `フ` + `゙` and `ブ` as equal, but `NSRegularExpression` does not.
- Storage: never edit `KakeiboSchemaV1` models once shipped. Copy them into `KakeiboSchemaV2`, add a stage to `KakeiboMigrationPlan`, and repoint the `Expense`/`LineItem` typealiases. Enums are stored as `…Raw` strings; use the typed properties (`expense.payment`) in code and the raw fields only in `#Predicate`. Read items with `orderedItems`, since SwiftData does not keep relationship order. Use `ExpenseRepository` (main actor) rather than inserting models directly; tests use `KakeiboStore.makeContainer(inMemory: true)`.
- Photos: save and read them only through `PhotoStore` (`<UUID>.jpg` in Application Support/Receipts; GPS is stripped on save). Create `ExpenseRepository` with the photo store so deleting an expense deletes its photo, and call `removeOrphanPhotos()` at launch. Do not set file protection or backup-exclusion options on photo files.
- OCR results are `TextObservation` (Core) with a top-left, 0–1 `BoundingBox`. In files that import Vision, write `OCRTextObservation`: Vision has its own `TextObservation`, and `KakeiboCore.TextObservation` does not compile because the `KakeiboCore` enum hides the module name.
- Do not name a package resource folder `Resources` in a test target that uses `.copy`: iOS code signing rejects the bundle ("bundle format unrecognized"). Use a descriptive name such as `SampleImages` or `Fixtures`.
- Refiner: get one with `ReceiptRefiners.automatic()` (on-device model when Apple Intelligence is available, otherwise `NoopRefiner`). Merge rules live in `RefinementMerger` and are tested with `MockModel`; keep model-specific code in `FoundationModelsRefiner.swift`. The live model test runs only where Apple Intelligence is available and takes about 15 s.
- Scanning never waits for the model (decided 2026-11-04; the model takes 13–43 s). Use `ExtractionPipeline.extract` (about 1 s) and show its draft on the review screen at once; then run `refine` in a background task and apply its answer with `BackgroundRefinement.apply(refined:original:current:)`, which keeps any field the user has already edited. Cancel the refine task when the user leaves the screen.
- Scan UI state lives in `ScanSession` (KakeiboScan, main actor, tested with `swift test`); views only observe it. Decode library photos with `ImageDecoding.uprightImage` (applies EXIF orientation), never `CGImageSourceCreateImageAtIndex`.
- UI tests: give a SwiftUI container `.accessibilityElement(children: .contain)` before `.accessibilityIdentifier`, or the identifier replaces every child's. Debug builds read `KAKEIBO_SCAN_IMAGE_PATH` (start a scan with that image) and `KAKEIBO_SCAN_OCR_DELAY` (seconds) so UI tests can drive the scan flow without the photo picker.
- Design tokens: colors are asset-catalog color sets with light and dark variants, all generated from the table in `scripts/design-tokens.py`. To change or add a color, edit that table and run `python3 scripts/design-tokens.py`; `--check` (run in CI) fails on stale assets or contrast below 4.5:1 for text or 3:1 for UI. Add any new text/background pair to `PAIRS`. Views use `Theme.*` colors, the `Font` type scale in `DesignSystem/Typography.swift` (`.amountHero`, `.amount`, `.amountSmall` for yen) and `ExpenseCategory.color` / `.symbolName` / `CategoryBadge`; never literal colors or ad-hoc fonts. Debug builds show every token in light and dark from the hammer button on the root screen.
- Review screen logic lives in `ReviewForm` (KakeiboStore): fields to check, validation, unsaved changes, save (photo first, removed again if the expense fails to save) and delete. `ReviewView` only binds to it. Confirmations (discard, delete) use the in-app `ConfirmPanel`, never `.alert` or `.confirmationDialog`.
- `BackgroundRefinement` is in Core (it only uses Core types).
- UI tests launch with `KAKEIBO_IN_MEMORY_STORE=1` (empty ledger, temporary photo folder) and `KAKEIBO_NO_REFINER=1` (no on-device model, so results do not depend on the machine).
- Format yen with `Yen.format(_:)` (`¥1,234`, `-¥120`), not `NumberFormatter` or locale currency styles.

## Commands

Fast core tests (no simulator):

```
swift test --package-path Packages/KakeiboCore
swift test --package-path Packages/KakeiboScan
swift test --package-path Packages/KakeiboStore
```

Full app build and tests (runs the `Kakeibo` test plan: all package tests plus UI tests, on the simulator):

```
xcodebuild test -scheme Kakeibo -destination 'platform=iOS Simulator,name=iPhone 17'
```

If that simulator name is unavailable, list devices with `xcrun simctl list devices available` and pick an iOS 26 iPhone.

## CI

Xcode Cloud runs two workflows (details and owner setup in `docs/ci.md`):

- **Pull Request** (PRs into `main`): `swift test` for all three packages via `ci_scripts/ci_pre_xcodebuild.sh`, then the `Kakeibo` test plan on an iOS 26 simulator.
- **Main to TestFlight** (push to `main`): the same tests, then archive and upload to TestFlight internal testing.

Once the owner has connected Xcode Cloud, a PR is ready to merge only when the Xcode Cloud check is green. To run the same checks locally, run `ci_scripts/test_packages.sh` and the `xcodebuild test` command above. When you add a package test target, add it to `Kakeibo.xctestplan` and to the scheme's build entries, or CI will skip it silently.

## Parser fixtures

Receipt fixtures live in `Packages/KakeiboCore/Tests/Fixtures/receipts/`:

- `<name>.txt`: OCR text, one line per receipt row
- `<name>.expected.json`: expected fields; fields left out are not scored

The accuracy test (`ReceiptAccuracyTests`) prints per-field accuracy and fails if total-amount accuracy drops below 90% (`minimumTotalAccuracy`). Never lower the threshold to make a change pass; fix the parser or ask. Remove personal details (card digits, member numbers, names) from fixtures before committing.

### Adding a fixture

1. Name it `<source>-<store or type>-<detail>`, e.g. `real-lawson-suica`. `hw-` marks hand-written fixtures; real receipts from T-16 use `real-`.
2. Save the OCR text as `<name>.txt`, one receipt row per line, exactly as OCR produced it. Do not clean it up: the normalizer is part of what is tested.
3. Write `<name>.expected.json` with what a careful person would enter:

   ```json
   {
     "storeName": "ローソン",
     "dayKey": "2026-11-03",
     "time": "07:52",
     "totalYen": 378,
     "tax10Yen": null,
     "tax8Yen": 28,
     "payment": "icCard",
     "category": "groceries",
     "invoiceNumber": "T1234567890123"
   }
   ```

   - Leave a field out to skip scoring it. Set it to `null` to require that nothing is found (for example `tax8Yen` on a receipt with no 8% items).
   - `storeName` is the canonical chain name when the store is in `chains.json`, otherwise the first store line as normalized.
   - `payment` and `category` use the raw values of `PaymentMethod` and `ExpenseCategory`.
   - Optional `scannedOn` (`yyyy-MM-dd`) sets the scan date. It defaults to `dayKey`. Set it for receipts without a year (`11月2日`).
   - Optional `items`: `[{"name": "牛乳", "priceYen": 198, "isReducedRate": true}, …]` in receipt order, discounts negative right after their item. Scored as item count and as item prices with their rate (names are not scored). Leave it out for receipts without item lines (fuel, parking).
4. Run `swift test --package-path Packages/KakeiboCore --filter ReceiptAccuracyTests` and read the table and the "Misses" list. If a miss is a parser bug, fix the parser and add a unit test for the case.

## Design

Screen designs: the "Kakeibo iOS App Screens" canvas on claude.ai (Ledger, Reading receipt, Check and save, Monthly summary, Settings). Visual language: cool grey ground, white surfaces, indigo accent (藍), vermilion (朱) for destructive actions, monospaced digits for yen amounts, every Japanese label paired with English.
