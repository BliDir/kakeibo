# CI: Xcode Cloud

Two Xcode Cloud workflows test every pull request and send every merge to `main` to TestFlight. The workflows themselves live in App Store Connect, so the owner creates them once by following the steps below. Everything they rely on is in this repo.

## What is in the repo

| File | Purpose |
| --- | --- |
| `Kakeibo.xctestplan` | The app's test plan: `KakeiboCoreTests`, `KakeiboScanTests`, `KakeiboStoreTests` and `KakeiboUITests`, run on the iOS simulator. It is the default plan of the shared `Kakeibo` scheme. |
| `ci_scripts/ci_pre_xcodebuild.sh` | Xcode Cloud custom step. Before the test action's `build-for-testing`, it runs `swift test` for all three packages on the macOS host. It does nothing for other actions. |
| `ci_scripts/test_packages.sh` | Runs `swift test` for each package. It can also be run locally. |
| `ITSAppUsesNonExemptEncryption = NO` | Set in the app's build settings so TestFlight does not ask the export-compliance question for each build. |

## Workflows

### 1. Pull Request

- **Start condition:** Pull Request Changes, source branch: any, target branch: `main`. Turn on auto-cancel.
- **Environment:** Xcode: Latest Release (26.x). macOS: Latest Release.
- **Action:** Test. Scheme `Kakeibo`, test plan `Kakeibo`, platform iOS, destination: iPhone 17 simulator, latest iOS 26.
- **Result:** Xcode Cloud posts a check on the GitHub pull request.

### 2. Main to TestFlight

- **Start condition:** Branch Changes, branch `main`.
- **Environment:** same as above.
- **Actions:**
  1. Test (same as the Pull Request workflow).
  2. Archive. Platform iOS, scheme `Kakeibo`, deployment preparation: TestFlight (Internal Testing Only).
- **Post-action:** TestFlight Internal Testing, group "Internal".
- **Build numbers:** Xcode Cloud sets `CFBundleVersion` for each archive, so nothing in the repo needs bumping. `MARKETING_VERSION` (1.0) is changed by hand for each release.

## Owner setup (one time)

These steps need the Apple Developer account and cannot be done from the repo.

1. In App Store Connect, register the bundle ID and create the app record. The placeholder bundle ID is `com.blidir.kakeibo`; if you choose a different one, change `PRODUCT_BUNDLE_IDENTIFIER` in the project first.
2. In Xcode, open `Kakeibo.xcodeproj`. Under target `Kakeibo` > Signing & Capabilities, select your team and keep "Automatically manage signing" on. Do the same for `KakeiboUITests`. Commit the resulting `DEVELOPMENT_TEAM` change.
3. In Xcode, go to Integrate > Create Workflow, choose the `Kakeibo` product, and grant Xcode Cloud access to the `BliDir/kakeibo` GitHub repository.
4. Create the two workflows above. Xcode suggests a default workflow; edit it into "Pull Request" and add "Main to TestFlight".
5. In App Store Connect > TestFlight, create the internal group "Internal" and add yourself.
6. Open a test pull request and confirm the Xcode Cloud check runs and passes. Merge it and confirm a build shows up in TestFlight.
7. Optional: in GitHub branch protection for `main`, require the Xcode Cloud check.

## Running the same checks locally

```
ci_scripts/test_packages.sh
xcodebuild test -scheme Kakeibo -testPlan Kakeibo -destination 'platform=iOS Simulator,name=iPhone 17'
```
