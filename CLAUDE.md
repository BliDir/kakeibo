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

The accuracy test prints per-field accuracy and fails if total-amount accuracy drops below 90%. Never lower the threshold to make a change pass; fix the parser or ask. Remove personal details (card digits, member numbers, names) from fixtures before committing.

## Design

Screen designs: the "Kakeibo iOS App Screens" canvas on claude.ai (Ledger, Reading receipt, Check and save, Monthly summary, Settings). Visual language: cool grey ground, white surfaces, indigo accent (藍), vermilion (朱) for destructive actions, monospaced digits for yen amounts, every Japanese label paired with English.
