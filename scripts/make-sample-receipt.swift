// Renders the made-up receipt used by KakeiboScan's OCR integration test.
// Usage: swift scripts/make-sample-receipt.swift Packages/KakeiboScan/Tests/KakeiboScanTests/SampleImages/sample-receipt.png
// The store, address and numbers are fictional.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let lines: [(String, CGFloat)] = [
    ("サンプルマート 中野店", 52),
    ("東京都中野区中野9-9-9", 34),
    ("2026年11月3日(火) 18:42", 34),
    ("登録番号 T1234567890123", 34),
    ("", 20),
    ("牛乳 ※            ¥198", 40),
    ("食パン ※          ¥158", 40),
    ("洗剤              ¥398", 40),
    ("", 20),
    ("小計             ¥754", 40),
    ("(内消費税等       ¥67)", 34),
    ("合計             ¥754", 56),
    ("お預り          ¥1,000", 40),
    ("お釣り           ¥246", 40),
]

let width = 900
let margin: CGFloat = 60
let height = Int(lines.reduce(CGFloat(2 * margin)) { $0 + $1.1 * 1.5 })

let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

var y = CGFloat(height) - margin
for (text, size) in lines {
    y -= size * 1.5
    guard !text.isEmpty else { continue }
    let font = CTFontCreateWithName("HiraginoSans-W3" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.textPosition = CGPoint(x: margin, y: y)
    CTLineDraw(line, context)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
print("wrote \(url.path) (\(width)x\(height))")
