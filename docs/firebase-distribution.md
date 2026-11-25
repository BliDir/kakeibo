# Test builds: Firebase App Distribution

`scripts/firebase-distribute.sh` builds a Release `.ipa`, signs it and uploads it to Firebase App Distribution. Testers get an email and install the app from Firebase App Tester. A launchd job on the owner's Mac runs it twice a week (below).

This is in addition to TestFlight (`docs/ci.md`), not a replacement. **No Firebase SDK is added to the app**: Firebase only hosts the `.ipa`, so the app still makes no network calls and has no third-party SDKs. `GoogleService-Info.plist` is not used; never add it to the app. `PrivacyInfo.xcprivacy` does not change.

## Configuration

`Config/firebase-distribution.env` holds the settings; environment variables with the same names override them. None of them is a secret (uploading needs a logged-in Firebase CLI). `.firebaserc` sets the default project for other `firebase` commands.

| Setting | Value |
| --- | --- |
| `FIREBASE_PROJECT` | `kakeibo-87093` |
| `FIREBASE_APP_ID` | `1:357039095760:ios:1551a1f07d8686be1ac3d5` (bundle ID `com.blidir.kakeibo`) |
| `FIREBASE_GROUPS` | `blidir-team` (the group's **alias**, shown under Testers & Groups; not always its display name) |
| `KAKEIBO_EXPORT` | `development` today; `adhoc` after joining the Apple Developer Program |
| `KAKEIBO_TEAM` | optional; default `A75X4JPQUW` |

## Signing: free account or paid program

The owner's Apple team is a free **Personal Team**. Apple refuses Ad Hoc profiles for it ("does not have permission to create iOS Ad Hoc provisioning profiles"), so builds are development-signed:

| | `development` (free, today) | `adhoc` (paid, $99/year) | TestFlight (paid) |
| --- | --- | --- | --- |
| Devices | iPhones registered to the team through Xcode (the owner's) | up to 100 registered iPhones | any iPhone |
| Build expires | **7 days** after it is made | about a year | 90 days |

With `development`, the script first removes the cached `iOS Team Provisioning Profile: com.blidir.kakeibo`, so Xcode gets a new profile and every build has the full 7 days. An expired build no longer opens, but its data stays on the iPhone: install the next build **over** it from App Tester; never delete the app first, or the ledger and photos are lost.

After joining the program, set `KAKEIBO_EXPORT=adhoc` and register testers' iPhones (below). The schedule can then drop to once a week or less.

## One-time setup (done 2026-11-25)

1. Firebase project `kakeibo-87093` with the iOS app `com.blidir.kakeibo` (the SDK and `GoogleService-Info.plist` steps skipped).
2. App Distribution: group `blidir-team` with the owner as tester.
3. Firebase CLI login on the Mac: `npx firebase-tools login`. The script uses `firebase` if it is installed, otherwise `npx firebase-tools`.
4. Xcode signed in to the Apple account (Xcode > Settings > Accounts) and the owner's iPhone registered (connect it once; Window > Devices and Simulators).

## Making a build by hand

From a clean checkout of the commit to test (usually `main`):

```
scripts/firebase-distribute.sh
```

- `--build-only` stops after `build/firebase/Kakeibo.ipa` is written (to check signing).
- `--testers "a@example.com"` invites single testers as well as the group.
- `--notes "Check the duplicate warning"` replaces the default notes (last commit and expiry date).

The script refuses a tree with uncommitted changes, so each test build matches a commit. The build number is `git rev-list --count HEAD`, so later commits on `main` always get higher numbers. The version stays `MARKETING_VERSION`.

## Scheduled build (this Mac)

```
scripts/install-scheduled-build.sh            # install or update
scripts/install-scheduled-build.sh --run-now  # install and build at once
scripts/install-scheduled-build.sh --uninstall
```

The launchd job `com.blidir.kakeibo.firebase-build` runs **Monday and Thursday at 10:00**: at most 4 days apart, so a build never expires before the next one even if a run is late. It fetches `origin/main`, builds it in a temporary worktree (the checkout, its branch and uncommitted work are not touched) and uploads it to `blidir-team`. A macOS notification says when it is done or failed; logs are in `~/Library/Logs/KakeiboBuild`. Then open App Tester on the iPhone and install the update.

Why not in the cloud: Xcode Cloud needs the paid program, and a free team's profiles can only be made by Xcode on a Mac signed in to the account, so a hosted runner cannot sign. The job therefore needs this Mac to be on (or wake) and logged in. A run missed while the Mac sleeps starts when it wakes; a run missed while it is off is skipped, so make a build by hand after a long trip.

The job runs a copy of `scheduled-firebase-build.sh` in `~/Library/Application Support/KakeiboBuild`. After changing that script, run the installer again.

## Registering tester iPhones (`adhoc` only)

- **Your own iPhone:** connect it to the Mac once and open Xcode > Window > Devices and Simulators. Or add it at <https://developer.apple.com/account/resources/devices/list>.
- **Other testers:** invite them in Firebase. When they accept on their iPhone, Firebase asks to install a profile that reads the UDID, and you get an email with it. In App Distribution > Testers & Groups, use "Export Apple UDIDs" and upload the file in the developer portal (Devices > plus button > Register Multiple Devices). Then make a new build.

With the free team, other people's iPhones cannot be added.

## When it fails

- **"No Accounts: Add a new account in Accounts settings":** Xcode is not signed in. Add the account in Xcode > Settings > Accounts.
- **"does not have permission to create iOS Ad Hoc provisioning profiles":** free Personal Team with `KAKEIBO_EXPORT=adhoc`. Use `development`.
- **"No profiles for 'com.blidir.kakeibo' were found":** no registered iPhone in the team. Connect the iPhone and open it in Xcode's Devices window.
- **"failed to distribute to testers/groups … 404":** the group alias is wrong. `npx firebase-tools appdistribution:groups:list` shows the aliases (first column).
- **"Authentication Error" from Firebase:** the CLI login expired. Run `npx firebase-tools login` again.
- **The app does not open on the iPhone:** the build expired, or (development) the iPhone was not registered when it was made. Install the latest build from App Tester, or make one.
- **The app needs iOS 26.** Older iPhones cannot install it.
