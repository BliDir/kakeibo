import Foundation
import KakeiboCore

/// The words for BI-02's drivers and suggestions. Core gives the figures; every sentence here
/// is a template from `Localizable.xcstrings` (ja and en). Suggestions describe and quantify;
/// they never judge.
enum InsightWording {
    /// "Dining out", or a store's saved name.
    static func name(_ target: InsightTarget) -> String {
        switch target {
        case .category(let category): category.displayName(for: LedgerFormat.language)
        case .store(let name): name
        }
    }

    /// The short label for a driver's kind ("More visits").
    static func kind(_ kind: OverspendDriver.Kind) -> String {
        switch kind {
        case .categoryIncrease: String(localized: "insight.kind.categoryIncrease")
        case .largeOneOff: String(localized: "insight.kind.largeOneOff")
        case .moreVisits: String(localized: "insight.kind.moreVisits")
        case .newSpending: String(localized: "insight.kind.newSpending")
        case .shareOfBudget: String(localized: "insight.kind.shareOfBudget")
        }
    }

    /// "+¥3,600" for a cause; the plain amount for a share of the budget (not a cause).
    static func impact(_ driver: OverspendDriver, spoken: Bool = false) -> String {
        let yen = spoken ? LedgerFormat.spokenYen(driver.impactYen) : LedgerFormat.yen(driver.impactYen)
        return driver.kind == .shareOfBudget ? yen : "+" + yen
    }

    /// What happened, in one sentence ("Dining out is ¥12,400 above usual.").
    static func description(_ driver: OverspendDriver, closed: Bool, budgetYen: Int?) -> String {
        switch driver.suggestion {
        case .categoryIncrease(let category, let above, _):
            let name = category.displayName(for: LedgerFormat.language)
            return closed
                ? String(localized: "insight.driver.categoryIncrease.closed \(name) \(LedgerFormat.yen(above))")
                : String(localized: "insight.driver.categoryIncrease \(name) \(LedgerFormat.yen(above))")
        case .moreVisits(let target, let visits, let usual, _, _):
            return String(localized: "insight.driver.moreVisits \(name(target)) \(visits) \(usual)")
        case .largeOneOff(_, let store, let dayKey, let amount, let typical, _):
            let day = LedgerFormat.shortDay(dayKey)
            let trimmed = store.trimmingCharacters(in: .whitespacesAndNewlines)
            var text = trimmed.isEmpty
                ? String(localized: "insight.driver.largeOneOff.noStore \(LedgerFormat.yen(amount)) \(day)")
                : String(localized: "insight.driver.largeOneOff \(LedgerFormat.yen(amount)) \(trimmed) \(day)")
            if typical > 0 {
                text += " " + String(localized: "insight.driver.largeOneOff.typical \(LedgerFormat.yen(typical))")
            }
            return text
        case .newSpending(let target, let amount):
            return String(localized: "insight.driver.newSpending \(name(target)) \(LedgerFormat.yen(amount))")
        case .shareOfBudget(let category, let spent, let percent):
            let name = category.displayName(for: LedgerFormat.language)
            if let percent, let budgetYen {
                return String(localized: "insight.driver.shareOfBudget \(name) \(percent) \(LedgerFormat.yen(budgetYen))")
            }
            return String(localized: "insight.driver.spent \(name) \(LedgerFormat.yen(spent))")
        }
    }

    /// What would help for the rest of the month, or nil (closed months, or nothing to suggest).
    static func suggestion(_ driver: OverspendDriver, overBudget: Bool, closed: Bool) -> String? {
        guard !closed else { return nil }
        switch driver.suggestion {
        case .categoryIncrease(_, _, let keepTo):
            guard let keepTo else { return nil }
            if keepTo == 0 { return String(localized: "insight.suggest.categoryIncrease.reached") }
            return overBudget
                ? String(localized: "insight.suggest.categoryIncrease.over \(LedgerFormat.yen(keepTo))")
                : String(localized: "insight.suggest.categoryIncrease \(LedgerFormat.yen(keepTo))")
        case .moreVisits(_, _, _, let fewer, let saving):
            guard let fewer, let saving else { return nil }
            return fewer == 1
                ? String(localized: "insight.suggest.moreVisits.one \(LedgerFormat.yen(saving))")
                : String(localized: "insight.suggest.moreVisits \(fewer) \(LedgerFormat.yen(saving))")
        case .largeOneOff(_, _, _, _, _, let onTrackWithout):
            return onTrackWithout
                ? String(localized: "insight.suggest.largeOneOff.onTrack")
                : String(localized: "insight.suggest.largeOneOff.check")
        case .newSpending, .shareOfBudget:
            return nil
        }
    }

    /// What VoiceOver reads for a driver row: the full sentences, not a chart.
    static func spoken(_ driver: OverspendDriver, overBudget: Bool, closed: Bool, budgetYen: Int?) -> String {
        var parts = [name(driver.target), kind(driver.kind), impact(driver, spoken: true),
                     description(driver, closed: closed, budgetYen: budgetYen)]
        if let suggestion = suggestion(driver, overBudget: overBudget, closed: closed) { parts.append(suggestion) }
        return parts.joined(separator: ". ")
    }

    /// "August, September and October" / "8月、9月、10月", oldest first.
    static func months(_ months: [LedgerMonth]) -> String {
        let names = months.sorted().map(LedgerFormat.monthName)
        let formatter = ListFormatter()
        formatter.locale = Locale(identifier: LedgerFormat.language == .ja ? "ja_JP" : "en_US")
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }
}
