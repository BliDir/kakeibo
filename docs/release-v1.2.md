# Kakeibo v1.2 — Budget Insights: release handoff

For the owner, before submitting v1.2 to App Store Connect. Verification results are in the BI-08 pull request.

## App Privacy label: stays "Data Not Collected"

Nothing in v1.2 changes the answers in App Store Connect → App Privacy:

- Insights, drivers, suggestions and the budget review are computed on the iPhone from the local ledger (KakeiboCore). Nothing is sent anywhere and nothing new is stored: analysis is recomputed from expenses and budgets, which are already stored.
- The optional wording (BI-06) uses Apple's on-device Foundation Models. Apple runs it on the device; the app sends nothing over the network. Its input is the analysis figures only, never receipts or photos, and its answer is kept only in memory.
- No new SDKs, no network code, no new required-reason APIs: `App/PrivacyInfo.xcprivacy` is unchanged since v1.1 (no tracking, no collected data, `UserDefaults` CA92.1 only).
- Notifications keep v1.1 rules: no amounts or store names on the lock screen.

So keep **Data Not Collected** and **no tracking**. No new usage descriptions (Info.plist) are needed.

## What's New in This Version

### 日本語

予算インサイトを追加しました。
・予算を超えそう、または超えたときに、その理由（カテゴリの増加、大きな買い物、利用回数の増加、今月初めての支出）を金額つきで表示します。
・今月の残りに使える1日あたりと今週の目安を表示します。
・最近の支出から提案額を計算し、予算を「維持」「今月のみ変更」「今月以降に適用」から選んで見直せます。確定するまで予算は変わりません。
・分析はすべてこのiPhoneの中で行い、データは外部に送信しません。

### English

New: budget insights.
• When you're on pace to go over your budget, or already over, Kakeibo shows why, with amounts: a category above usual, one larger purchase, more visits, or new spending.
• See what you can spend per day and this week for the rest of the month.
• Review your budget with a suggested amount from your recent spending: keep it, change it for this month only, or change it from this month on. Nothing changes until you confirm.
• Everything is worked out on your iPhone. Nothing leaves it.

## Real-device pass (owner)

All of this was checked on the iOS simulator (results in the BI-08 PR). Repeat it on a real iPhone with a Debug build from Xcode; each state below is seeded with an in-memory ledger, so your own data is not touched.

Launch with `KAKEIBO_IN_MEMORY_STORE=1` and one of the `KAKEIBO_SEED_INSIGHT` values (Xcode → Scheme → Run → Environment Variables), in Japanese and in English:

| `KAKEIBO_SEED_INSIGHT` | Covers | Check |
|---|---|---|
| `onPace` | Heads up, projection, large one-off + category increase, daily/weekly amounts | Card and analysis figures match; the projection is labelled as an estimate |
| `over` | Why am I over?, ¥0 rest of month, driver → filtered ledger | Each driver row opens the matching expenses |
| `closed` | Last month's look back, read-only review | No suggestions or rest-of-month amounts |
| `limited` | No earlier months to compare (limited history) | Drivers show their share of the budget, no "usual" comparisons |
| `raise` | Review: raise, this month only / from this month on | Confirm updates the budget card, bar and weekly amount |
| `lower` | Review: lower | Suggested amount is below the current one |
| `steady` | Review: keep (amount locked) | Confirm stores nothing |

On each state:

1. VoiceOver: every driver row reads as one sentence (name, kind, amount, what happened, suggestion).
2. Settings → Accessibility → Larger Text at the largest size: no figure is cut off or split across lines.
3. Light and dark mode.
4. With Apple Intelligence on, the card's first sentence may change to the on-device wording after a few seconds; it must still quote the card's figures.
5. v1.1 regression on your own ledger (normal launch, no variables): budget card, weekly amount and the 80%/100% alerts behave as before.

## Before submitting

1. Merge the BI-08 PR and let the "Main to TestFlight" workflow upload the build.
2. Install from TestFlight on a real iPhone and open a month with a budget: the ledger, budget card and alerts behave as in v1.1.
3. In App Store Connect, paste the What's New text above (ja and en), keep the privacy answers, and submit for review.
