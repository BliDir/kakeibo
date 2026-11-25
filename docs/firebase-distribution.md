# Test builds: Firebase App Distribution

`scripts/firebase-distribute.sh` builds a Release `.ipa` signed for Ad Hoc distribution and uploads it to Firebase App Distribution. Testers get an email and install the app from the Firebase App Tester web clip.

This is in addition to TestFlight (`docs/ci.md`), not a replacement. **No Firebase SDK is added to the app**: Firebase only hosts the `.ipa`, so the app still makes no network calls and has no third-party SDKs. `PrivacyInfo.xcprivacy` does not change.

## TestFlight or Firebase?

| | TestFlight (Xcode Cloud) | Firebase App Distribution |
| --- | --- | --- |
| Tester devices | any iPhone, no registration | only iPhones whose UDID is in the Apple Developer account (max 100 per year) |
| Review | none for internal testers | none |
| Builds | every merge to `main` | whenever the script is run |
| Expiry | 90 days | when the provisioning profile expires (1 year) |

Adding a tester's iPhone needs a new build: the UDID is baked into the provisioning profile.

## One-time setup (owner)

1. **Firebase project.** At <https://console.firebase.google.com>, create a project (for example "Kakeibo"). Google Analytics is not needed; turn it off.
2. **Register the iOS app.** In the project, click Add app > iOS. Bundle ID `com.blidir.kakeibo`, nickname "Kakeibo". Skip the steps that download `GoogleService-Info.plist` and add the SDK. Do not add either to the project.
3. **App ID.** Under Project settings > General > Your apps, copy the **App ID** (`1:…:ios:…`). It is not a secret, but keep it out of the repo; pass it as `FIREBASE_APP_ID`.
4. **App Distribution.** Open Release & Monitor > App Distribution and click Get started. Under Testers & Groups, create a group, for example `internal` (the alias is what the script takes), and add the testers' emails.
5. **Firebase CLI login** on the Mac. The script uses `firebase` if it is installed, otherwise `npx firebase-tools`:

   ```
   npx firebase-tools login
   ```

6. **Distribution certificate.** Ad Hoc export needs an Apple Distribution certificate. The script passes `-allowProvisioningUpdates`, so Xcode creates the certificate and the Ad Hoc profile itself, provided Xcode is signed in to the team's Apple account (Xcode > Settings > Accounts). The team must be a paid Apple Developer Program team.

## Registering tester iPhones

Each tester's iPhone must be registered before the build that they will install.

- **Your own iPhone:** connect it to the Mac once and open Xcode > Window > Devices and Simulators. With automatic signing, Xcode registers it in the team. Or add it by hand: <https://developer.apple.com/account/resources/devices/list>, then the plus button, name and UDID.
- **Other testers:** invite them in Firebase first. When they accept on their iPhone, Firebase asks to install a profile that reads the UDID. You then get an email with the UDIDs. In App Distribution > Testers & Groups, use "Export Apple UDIDs" and upload the file in the developer portal (Devices > plus button > Register Multiple Devices). Then run the script again.

## Making a test build

From a clean checkout of the commit to test (usually `main`):

```
FIREBASE_APP_ID=1:000000000000:ios:0000000000000000 scripts/firebase-distribute.sh --groups internal
```

- `--testers "a@example.com,b@example.com"` invites single testers instead of or as well as a group.
- `--notes "Check the duplicate warning"` sets the release notes (default: the last commit subject and hash).
- `--build-only` stops after `build/firebase/Kakeibo.ipa` is written (to check signing without uploading).

The script refuses a tree with uncommitted changes, so each test build matches a commit. The build number is `git rev-list --count HEAD`, so later commits on `main` always get higher numbers. The version stays `MARKETING_VERSION`.

## When it fails

- **"No profiles for 'com.blidir.kakeibo' were found" / "requires a provisioning profile with … devices":** there is no registered device in the team. Register at least one iPhone (above).
- **"No signing certificate 'iOS Distribution' found":** sign in to the team in Xcode > Settings > Accounts, then run again. Xcode creates the certificate.
- **Tester sees "Unable to install":** their iPhone was not registered when the build was made. Register it and make a new build.
- **The app needs iOS 26.** Older iPhones cannot install it.
