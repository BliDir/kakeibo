// Renders the made-up receipts used by KakeiboScan's OCR and pipeline integration tests.
// Usage: swift scripts/make-sample-receipt.swift <preset> <output.png>
//   presets: sample, konbini, supermarket-skewed
// Example: swift scripts/make-sample-receipt.swift sample Packages/KakeiboScan/Tests/KakeiboScanTests/SampleImages/sample-receipt.png
// Every store, address and number is fictional.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let presets: [String: (lines: [(String, CGFloat)], rotationDegrees: CGFloat)] = [
    "sample": ([
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
    ], 0),
    "konbini": ([
        ("ローソン 架空町店", 52),
        ("令和8年11月2日(月) 7:52", 34),
        ("レジ1 No.0001", 34),
        ("", 20),
        ("からあげクン ※     ¥238", 40),
        ("緑茶 500ml ※       ¥140", 40),
        ("", 20),
        ("小計              ¥378", 40),
        ("(8%対象 ¥378 内消費税 ¥28)", 32),
        ("合計              ¥378", 56),
        ("Suica             ¥378", 40),
        ("Suica残高        ¥1,622", 34),
    ], 0),
    "supermarket-skewed": ([
        ("サンプルストア 架空店", 52),
        ("2026/10/28(水) 19:02", 34),
        ("", 20),
        ("たまご ※           248", 40),
        ("牛乳 ※             198", 40),
        ("ティッシュ          328", 40),
        ("", 20),
        ("小計             ¥774", 40),
        ("外税8%           ¥35", 36),
        ("外税10%          ¥32", 36),
        ("合計             ¥841", 56),
        ("クレジット       ¥841", 40),
    ], 2),
]

let args = CommandLine.arguments
guard args.count == 3, let preset = presets[args[1]] else {
    fatalError("usage: make-sample-receipt.swift <\(presets.keys.sorted().joined(separator: "|"))> <output.png>")
}

let width = 900
let margin: CGFloat = 60
let height = Int(preset.lines.reduce(CGFloat(2 * margin)) { $0 + $1.1 * 1.5 })

let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

if preset.rotationDegrees != 0 {
    // Rotate about the centre, like a receipt photographed slightly crooked.
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.rotate(by: preset.rotationDegrees * .pi / 180)
    context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
}

var y = CGFloat(height) - margin
for (text, size) in preset.lines {
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

let url = URL(fileURLWithPath: args[2])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
print("wrote \(url.path) (\(width)x\(height))")
