# Kakeibo

An iPhone app that turns a photo of a Japanese receipt (レシート) into a household ledger (家計簿) entry, entirely on the device. No account, no server, nothing leaves the phone.

## What it does (v1.0)

- Scan a receipt with the document camera; edges are found and the page is flattened.
- Read it on-device with Apple Vision OCR (Japanese and English).
- Pull out store, date (including 令和 era dates), total, 8% and 10% consumption tax, payment method and the invoice registration number (登録番号).
- On Apple Intelligence iPhones, refine the result and read item lines with Apple's on-device Foundation Models, including English item names.
- Review and correct, then save to a local SwiftData ledger with the original photo.
- Browse by month with category totals; export CSV.
- Japanese and English UI.

## Stack

| Layer | Choice |
| --- | --- |
| UI | SwiftUI, iOS 26+, iPhone only |
| Capture | VisionKit document camera, PhotosPicker |
| OCR | Vision `RecognizeTextRequest` (`ja-JP`, `en-US`) |
| Extraction | Rule-based `ReceiptParser` + optional Foundation Models refiner |
| Storage | SwiftData, photos as JPEG files |
| Charts | Swift Charts |
| Tests | Swift Testing, XCUITest |
| CI | Xcode Cloud → TestFlight |

## Repository layout

```
CLAUDE.md                 conventions and commands for Claude Code
Kakeibo.xcodeproj
App/                      KakeiboApp target (SwiftUI)
Packages/
  KakeiboCore/            parser, domain types, CSV (Foundation only)
    Tests/Fixtures/receipts/*.txt + *.expected.json
  KakeiboScan/            Vision, VisionKit, Foundation Models
  KakeiboStore/           SwiftData, PhotoStore
UITests/
```

Open `Kakeibo.xcodeproj` in Xcode 26 or later. See `CLAUDE.md` for build and test commands.

## Planning

- Linear project: **Kakeibo iOS v1.0** (issues DAI-425 to DAI-456, milestones M1 to M3)
- Design and technical plan: the "Kakeibo iOS v1.0 — Design & Technical Plan" document in that Linear project
- Screen designs: the "Kakeibo iOS App Screens" canvas on claude.ai

## Privacy

All processing happens on the iPhone. The app makes no network calls and collects no data. App Store privacy label: Data Not Collected.
