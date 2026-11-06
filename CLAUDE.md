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
  Exception: `ExpenseCategory` and `PaymentMethod` names (`japaneseName`, `englishName`, `displayName(for:)`, and `pairedName(for:)` for payments) live in Core code, because screens show both names together and CSV exports need fixed names. `swift test` cannot compile a String Catalog inside a package. Show the UI language first (`LedgerFormat.language`).
- The category enum is `ExpenseCategory`, not `Category`: Objective-C's `Category` type makes the short name ambiguous wherever SwiftUI or UIKit is imported.
- Raw values of `ExpenseCategory`, `PaymentMethod`, `Confidence` and `ReceiptField` are stored on disk. Never rename them.
- Field parsers take lines that have already been through `TextNormalizer`. Do not repeat full-width, ¥ or spacing clean-up in a parser; add the rule to `TextNormalizer` with a test.
- Store chains live in `Packages/KakeiboCore/Sources/KakeiboCore/Resources/chains.json`. To add one, append `{"name", "nameEn", "category", "match": [...]}` (`name` must also be in `match`; add OCR variants such as no-hyphen or Latin spellings). Use `"generic": true` with no `name` for words that only set a category (タクシー, クリニック). Add a test in `StoreClassifierTests`.
- When testing normalized Japanese text, compare `unicodeScalars`, not `==`: Swift's `==` treats `フ` + `゙` and `ブ` as equal, but `NSRegularExpression` does not.
- Storage: never edit `KakeiboSchemaV1` models once shipped. Copy them into `KakeiboSchemaV2`, add a stage to `KakeiboMigrationPlan`, and repoint the `Expense`/`LineItem` typealiases. Enums are stored as `…Raw` strings; use the typed properties (`expense.payment`) in code and the raw fields only in `#Predicate`. Read items with `orderedItems`, since SwiftData does not keep relationship order. Use `ExpenseRepository` (main actor) rather than inserting models directly; tests use `KakeiboStore.makeContainer(inMemory: true)`. Migration tests open checked-in store files (`Tests/KakeiboStoreTests/Fixtures/v1-store`); never create an old-schema container in a test, because parallel suites then crash SwiftData on iOS. The current schema is `KakeiboSchemaV3` (budgets, v1.1); `v2-store` is the populated store v1.0 ships with (generator in `BudgetMigrationTests`). When you add V4, add a `v3-store` fixture the same way.
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
- Duplicates: `ReceiptNumberParser` reads the receipt's own number (レシートNo., 取引番号, 伝票番号) with the register when printed (`02/0012`); compare with `comparisonKey`, never `==`. The invoice number is per shop, not per receipt, so never treat it alone as a duplicate. `ExpenseRepository.possibleDuplicates` holds the rules; `ReviewView` checks `ReviewForm.possibleDuplicates` on Save and shows `DuplicatePanel` (warn, never block).
- UI smoke test (`SmokeTests`, T-51): the core flow (add, save, find in the ledger, open, delete, empty again), run in both test plan configurations. It finds controls by accessibility identifier only, never sets the language itself (the configuration does), and checks amounts by digits so it works in both languages. Keep it passing; if you change an identifier it uses, update it. New UI test classes that force English must skip when `KAKEIBO_SMOKE_ONLY=1`.
- UI tests launch with `KAKEIBO_IN_MEMORY_STORE=1` (empty ledger, temporary photo folder) and `KAKEIBO_NO_REFINER=1` (no on-device model, so results do not depend on the machine). Debug builds read `KAKEIBO_COLOR_SCHEME=dark|light` to force the appearance; `XCUIDevice.shared.appearance` and `simctl ui … appearance` do not reach the app in tests.
- Privacy and release: `App/PrivacyInfo.xcprivacy` declares no tracking, no collected data, and only the required-reason APIs our code calls (today `UserDefaults`, CA92.1). If you start using another one (file timestamps, disk space, system boot time, active keyboards), add it there. No network calls and no third-party SDKs. Usage descriptions are `INFOPLIST_KEY_*` build settings with translations in `App/InfoPlist.xcstrings`; keys with no build setting (the launch screen color) go in `Config/Info.plist`, which Xcode merges.
- Branding: the app icon is the supplied single 1024 px `AppIcon` (no dark or tinted variants); the wordmark is `Image("KakeiboLogo")`, dark lettering for light backgrounds, so it sits on `Theme.logoPlate` (ivory in both modes). Do not regenerate either asset.
- Ledger: month and summary math (`LedgerMonth`, `JapaneseEra`, `MonthSummary`, `DayGroup`) is in Core; `LedgerModel` (KakeiboStore) reads through `ExpenseRepository` and reloads on `ModelContext.didSave`, so any save or delete updates the ledger. Do not add `@Query` to screens; read through the repository. UI tests can start with sample data via `KAKEIBO_SEED_SAMPLE=1` (with `KAKEIBO_IN_MEMORY_STORE=1`).
- Settings: preferences live in `AppSettings` (KakeiboStore, UserDefaults; UI tests get a fresh suite each launch). Photo storage and the version come from `SettingsModel`. App language is not stored: iOS keeps it per app, and Settings links there. New manual entries start with `settings.defaultPayment`.
- Swift Charts labels in `.value(...)` are picked up by the String Catalog when written as literals; pass a `String` constant for labels that never show (hidden charts).
- Summary tab: `SummaryView` shares the ledger's `LedgerModel`, so both tabs show the same month. Totals, tax by rate, category shares and bar lengths come from `MonthSummary`; month-over-month from `MonthComparison` (Core). Views only lay them out.
- Budgets (v1.1): the math is in Core `Budget.swift` (B-01). `MonthlyBudget` is a month's budget (`.unset`, `.invalid(Problem)`, `.yen(Int)`, max ¥999,999,999); parse typed input with `MonthlyBudget.parse` (full-width digits, commas, ¥/円 accepted; signs and fractions rejected). `BudgetSummary` takes the month, its budget, the same expenses the ledger shows (spend S = `MonthSpend.total`, identical to `MonthSummary.totalYen`) and an injected `now`; it keeps R = B − S signed, clamps only `progressFraction`, and has a `weeklyAllowance` only for the current Tokyo month. Use `Calendar.kakeibo` (Gregorian, Asia/Tokyo, weeks from Monday), never the device calendar. All math is overflow-checked; out-of-range data is the `.outOfRange` status, not a crash.
- Budget alerts (B-03): `BudgetAlertPolicy.evaluate` (Core) is the only place that decides 80%/100% alerts. It is pure: give it the month, budget, spend, stored handled thresholds, pending notifications, whether notifications are allowed and `now`; apply its `markHandled` (B-02 `markHandled`), raise `event` (in-app banner always, system notification only if `sendNotification`) and cancel `cancelPending`. Thresholds compare exactly in integers (5·S ≥ 4·B, S ≥ B). Only the current Tokyo month raises; jumping to 100% raises only 100% and consumes 80%; nothing rearms; with notifications off the event is still consumed, so nothing replays. Run it only after a successful save or on launch/foreground reconciliation.
- Budget notifications (B-06): `BudgetNotifier` (KakeiboStore, main actor, `AppServices.notifier`) is the only way to send or cancel budget alerts. It holds the opt-in (`AppSettings.budgetAlertsEnabled`, off by default) and the real iOS permission (`authorization`); pass `canSend` as `notificationsAllowed` to `BudgetAlertPolicy`. Ask permission only from `setEnabled(true)` (the Settings switch), never at launch. It talks to iOS through `BudgetNotificationCenter`: `SystemNotificationCenter` in the app (create it only there; `UNUserNotificationCenter.current()` traps under `swift test`), `InMemoryNotificationCenter` in tests and UI tests. Request IDs are `BudgetAlertIntent.requestID` (`budget-<yyyy-MM>-<80|100>`), shown at once (no trigger); `send` returns `.handedToSystem`, never "delivered". Copy is generic (no amounts or store names) in `notification.budget.*` strings, supplied by `AppServices`. `BudgetNotificationDelegate` hides the iOS banner for budget alerts in the foreground (the app shows its own banner) and routes a tap through `NotificationRouter` to the current month's ledger. UI tests set the fake permission with `KAKEIBO_NOTIFICATIONS=notDetermined|notDeterminedDeny|allowed|denied`; the real prompt never appears in tests.
- Budget progress (B-05): `BudgetProgressView` lays out `LedgerModel.budgetSummary` (never computes): bar clamped via `progressFraction`, status in words (`budget.status`: "82% used · close to budget", "103% used · over budget"), left/over/saved, and the weekly box (current month only) with its date range and how it is worked out. Refresh is event-driven: saves reload the ledger, and `ContentView` calls `LedgerModel.refreshForCurrentDate()` on foreground and at each Tokyo midnight (`Calendar.kakeibo.startOfNextDay(after:)`), which also moves the ledger to a new month if it was showing the old current one.
- Budget setup UI (B-04): `BudgetForm` (KakeiboStore) holds the sheet's logic (parse, validation, unsaved changes, save/remove, `failure`); `BudgetSheet` only binds to it. Save goes through `BudgetRepository.saveBudget(_:for:useForFutureMonths:now:)`, which stores the month's budget and the template choice in one write. `LedgerModel(budgets:)` exposes `budgetSummary`, `canEditBudget` and `makeBudgetForm()` (nil for past months). The ledger card shows the setup prompt (`budget.cta`), the budget with Edit, or a past month's budget view-only (`budget.closed`). Sample data (`KAKEIBO_SEED_SAMPLE`) gives last month a ¥5,000 budget.
- Budget storage (B-02): `BudgetRepository` (KakeiboStore, main actor, same context as `ExpenseRepository`) owns `BudgetMonth` (one row per `yyyy-MM`: budget, handled 80/100 thresholds), `BudgetTemplate` (single row, off by default) and `BudgetAlertIntent` (stable request ID `budget-<yyyy-MM>-<80|100>`, state `pending`/`delivered`/`cancelled`). Only the current Tokyo month can be set or removed; past months are read-only. Removing keeps the row (alert history survives, template stays out). The template applies from the month after it was saved, lazily on the first `budget(for:now:)` read while that month is current, and never to a month that has a row. Every write saves or rolls back; use `beforeSave` in tests to simulate a failed save.
- CSV export: `ExpenseCSV` / `CSVWriter` (Core) define the columns and escaping; `ExpenseExport` (KakeiboStore) writes `kakeibo-yyyy-MM.csv` / `kakeibo-yyyy.csv`. Keep UTF-8 with BOM and CRLF (Excel on Windows), and write user or OCR text with `CSVWriter.textField` so it can never run as a spreadsheet formula.
- Format yen in views with `LedgerFormat.yen(_:)` (`¥1,234` in English, `1,234円` in Japanese, via `Yen.format(_:for:)`); amount fields put the symbol where `Yen.fieldSymbol(for:)` says. Files and anything language-independent use `Yen.format(_:)` (`¥1,234`, `-¥120`). Never `NumberFormatter` or locale currency styles.
- Accessibility: wrap "label … value" and "icon text amount" rows in `AdaptiveStack` (a row, or a column at AX1–AX5), let text wrap (`.fixedSize(horizontal: false, vertical: true)`), never fix a height that holds text, and put panels in `ScrollIfNeeded`. Show amounts with `YenText` (VoiceOver: "1,234 yen" / "1,234円"); give combined rows an explicit label (ledger row: store, category, payment, amount, date). Fields the scan was unsure of use `.checkHint(...)` so VoiceOver announces the amber highlight. Tap targets at least 44 pt. `AccessibilityAuditTests` runs Xcode's audit on the main screens, launching once in light and once in dark (`KAKEIBO_COLOR_SCHEME`); add new screens to it.
- Localization check: `ScreenshotTourTests` walks every screen in ja and en at the default, XXXL and AX5 text sizes and attaches screenshots. It is skipped unless you run it with `TEST_RUNNER_KAKEIBO_SCREENSHOT_TOUR=1` (command in the file); add `TEST_RUNNER_KAKEIBO_TOUR_DARK=1` for dark mode. Add new screens to the tour. Debug-only tools (design tokens, fixture capture) stay English and are not localized.

## Commands

Fast core tests (no simulator):

```
swift test --package-path Packages/KakeiboCore
swift test --package-path Packages/KakeiboScan
swift test --package-path Packages/KakeiboStore
```

Full app build and tests (runs the `Kakeibo` test plan on the simulator, in two configurations: **English** runs all package and UI tests; **Japanese** runs the package tests and the UI smoke test `SmokeTests`, and the other UI tests skip there because they force English):

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

### Capturing a real receipt (Debug builds)

1. Scan or choose the receipt in a Debug build on the iPhone.
2. On "Check and save", **correct every field** against the paper receipt. The JSON is written from the form, so it is the expected answer; an uncorrected mistake becomes a wrong test. Items cannot be edited in the form yet: fix them in the JSON.
3. Tap the ladybug (Save as fixture), then Share fixture files → AirDrop to the Mac. You get `real-<timestamp>.txt`, `.expected.json` and `.jpg`.
4. Move the `.txt` and `.expected.json` into `Packages/KakeiboCore/Tests/Fixtures/receipts/`. Keep the `.jpg` outside the repo (`*.jpg` under `Tests/Fixtures/` is git-ignored); it is only for re-running OCR later.
5. Open the `.txt` and check for personal details. Card, member, approval, slip and terminal numbers and other 8+ digit runs are masked automatically; names or anything else are not.
6. Run the accuracy test (step 4 above), then commit the two files in one commit per batch.

## Design

Screen designs: the "Kakeibo iOS App Screens" canvas on claude.ai (Ledger, Reading receipt, Check and save, Monthly summary, Settings). Visual language: cool grey ground, white surfaces, indigo accent (藍), vermilion (朱) for destructive actions, monospaced digits for yen amounts, every Japanese label paired with English.
