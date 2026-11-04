import SwiftUI

/// The type scale. All sizes follow Dynamic Type. Yen amounts always use monospaced digits
/// so columns line up and numbers do not shift while typing.
extension Font {
    /// Screen titles in headers ("Check and save").
    static let screenTitle = Font.headline
    /// Card and panel titles ("Reading your receipt").
    static let sectionTitle = Font.title3.bold()
    static let bodyText = Font.body
    static let bodyEmphasis = Font.body.weight(.medium)
    /// Field labels and small captions.
    static let fieldLabel = Font.caption
    /// Uppercase overline labels ("AMOUNT PAID").
    static let overline = Font.caption.weight(.medium)
    static let footnoteText = Font.footnote
    /// Primary buttons.
    static let button = Font.system(.callout, weight: .bold)

    /// The big amount at the top of the review form (34 pt at default size).
    static let amountHero = Font.system(.largeTitle, design: .monospaced).weight(.semibold)
    /// Amounts in rows and totals.
    static let amount = Font.system(.body, design: .monospaced).weight(.semibold)
    /// Smaller amounts (tax lines, item prices).
    static let amountSmall = Font.system(.subheadline, design: .monospaced)
    /// Codes such as the invoice number and raw OCR text.
    static let code = Font.system(.footnote, design: .monospaced)
}
