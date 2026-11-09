# Kakeibo v1.1 — Migration and regression verification (B-09)

Run on 2026-11-09 against `main` at B-14 (`1878877`) plus this branch. Everything ran on the Mac or the iOS Simulator (iPhone 17, iOS 26.5); nothing ran on a physical iPhone. Real-device checks belong to B-10.

## Results

| Area | How | Result |
|---|---|---|
| Core, Store, Scan packages | `swift test --package-path Packages/<name>` | Core 365, Store 229, Scan 75: all passed |
| Same, other device time zones | `TZ=America/Los_Angeles`, `TZ=UTC`, `TZ=Pacific/Kiritimati` (UTC+14) `swift test` for Core and Store | all passed in each |
| Parser regression | `ReceiptAccuracyTests` (18 fixtures, 3 from real receipts) | 100% on every field |
| Full app test plan (English + Japanese) | `xcodebuild test -scheme Kakeibo -destination 'platform=iOS Simulator,name=iPhone 17'` | 781 tests: 764 passed, 17 skipped, 0 failed |
| Budget UI smoke, scan → review → save smoke | `SmokeTests`, `BudgetUITests`, `BudgetAlertUITests`, `KakeiboUITests.testScanShowsProgressThenReviewAndSaves` (in the full plan) | passed |
| Upgrade from v1.0 on the simulator | `scripts/upgrade-check.sh` (v1.0 = `0a410e6`) | see below |
| Upgrade, restart and rollovers on a store file | `ReleaseVerificationTests` (KakeiboStore) | passed |
| No network, analytics or new permissions | build comparison, see below | none added |

## Upgrade from a populated v1.0 install

`scripts/upgrade-check.sh` builds v1.0 (`0a410e6`, the last commit before v1.1 work) and the current tree. It installs v1.0 on a temporary simulator, gives it the store v1.0 writes (`Fixtures/v2-store`: three November 2026 expenses, items, a receipt number, one photo) and a photo file, and launches it. Then it installs the current build over it, as an App Store update would, and launches that.

| | v1.0 | after the update |
|---|---|---|
| Ledger | 3 receipts, ¥3,606, Lawson row with its photo | 3 receipts, ¥3,606, same rows |
| Store | `ZEXPENSE` 3, `ZLINEITEM` 2 | the same, plus empty `ZBUDGETMONTH`, `ZBUDGETTEMPLATE`, `ZBUDGETALERTINTENT` |
| Photo | `Receipts/<id>.jpg` | kept, still referenced |
| Budget | — | not set: the card offers "Set a monthly budget" |
| Alerts | — | off; no permission prompt at launch |

`ReleaseVerificationTests.v1_0UserThroughUpgradeRestartAndRollovers` then takes the same v1.0 store through a user's next weeks, on the store file, closing and reopening the app between steps:

1. **First launch:** expenses, items and the photo are kept, and `removeOrphanPhotos` keeps the photo. The November CSV has a UTF-8 BOM, the header and 3 rows, and totals ¥3,606. No budget or template exists, alerts are off, iOS is not asked and nothing is sent.
2. **Setting a budget:** the user turns alerts on (iOS asks once) and sets ¥4,000 from this month on. Spend is 90%, so the 80% alert fires once (banner and notification).
3. **Restart:** the budget, the handled 80% and the template are kept. Nothing is replayed, and iOS is not asked again.
4. **Midnight into December:** the template gives December ¥4,000 and December starts with no alerts. A late November receipt raises nothing, because November is closed. December reaches 82% and raises its own 80% alert.
5. **Restart, then midnight into January 2027:** January gets ¥4,000 and starts at ¥0.
6. **Moving an expense** from 31 December to 2 January moves its spend: January raises its 80% alert, and December's is not raised again. A jump past 100% then raises only 100%.

## Dates and amounts

Already covered by the package tests and passing:

- **Month lengths:** 28 days (Feb 2027), 29 (Feb 2028, leap day), 30 and 31. Last day of a month, last day of the year, Monday the 28th of December (week clipped at the year end). Sunday the 1st (a one-day week). Thursday weeks clipped to the month end. (`WeeklyAllowanceTests.daysLeft`)
- **Tokyo time, not the device's:** 23:59 vs 00:00 at a month end, and a UTC instant that is already Monday in Tokyo (`usesTokyoTimeNotTheDevicesTimeZone`). Packages are also run under three other `TZ` values.
- **Month and year rollover:** alerts (`monthRolloverCancelsOldPendingAndStartsFresh`), templates (`templateAppliesLazilyToNewMonthsOnly`) and both across a year end (the end-to-end test above).
- **Maximum values:** budget ¥999,999,999 accepted and ¥1,000,000,000 refused (`largestBudget`, `invalidAmountsAreRefused`). Sums near `Int.max` give the `.outOfRange` state, not a crash (`largeAmountsDoNotOverflow`, `overflowIsAStateNotACrash`).
- **Date moves:** an expense moved into the current month is evaluated (`movingAnExpenseIntoThisMonthIsEvaluated`). Moving one across a year end is in the end-to-end test.

## Network, analytics and permissions

Compared between the v1.0 and current Debug builds:

- `PrivacyInfo.xcprivacy`: identical (no tracking, no collected data, `UserDefaults` CA92.1 only). `App/PrivacyInfo.xcprivacy`, `Config/` and `App/InfoPlist.xcstrings` are unchanged since v1.0.
- `Info.plist`: no keys added. Local notifications need no usage description.
- **Linked frameworks added:** `UserNotifications` (local budget alerts) and `Accessibility`. Our code does not import `Accessibility`; SwiftUI links it automatically for its accessibility features, and it is on-device only.
- **No network or analytics:** no `URLSession`, `Network`, `WebKit` or analytics symbols in the binary, and no remote Swift packages.
- **Permission prompt:** the only call is `BudgetNotifier.setEnabled(true)` (the Settings switch). It is checked at launch, on upgrade and after a restart (`BudgetNotifierTests`, `ReleaseVerificationTests`).

## Limitations (for B-10, owner on a real iPhone)

- **Real notifications:** the tests use `InMemoryNotificationCenter`, so iOS's own allow/deny prompt, banners, tapping a notification and turning permission back on in iOS Settings need a real iPhone.
- **Data protection:** the simulator does not enforce `FileProtectionType.complete`. B-11's upgrade of v1.0 files is covered by `DataProtectionTests.upgradesV1_0FilesWithoutChangingThem`, and on a device by `KAKEIBO_PROTECTION_REPORT=1` (see CLAUDE.md).
- **The update path:** the simulator check installs a Debug build over a Debug build. An App Store or TestFlight update of a Release build keeps the same container in the same way, but that is part of B-10.
- **Time zone:** the app on the simulator ran in the Mac's time zone (Asia/Tokyo). Other zones were run in the package tests, where all date logic lives (`Calendar.kakeibo`). Nothing in the app uses the device calendar or time zone.

No failures were found, so no follow-up blockers were created.
