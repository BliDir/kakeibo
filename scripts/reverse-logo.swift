// Derives the dark-appearance wordmark from the supplied logo (UI-01): the ink-green parts
// become ivory and the sage fold stays, the app icon's own colorway. Alpha and anti-aliased
// edges are kept; nothing is redrawn. Run again only if the supplied logo changes:
//
//     swift scripts/reverse-logo.swift \
//       App/Assets.xcassets/KakeiboLogo.imageset/KakeiboLogo.png \
//       App/Assets.xcassets/KakeiboLogo.imageset/KakeiboLogo-dark.png
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: swift scripts/reverse-logo.swift <logo.png> <logo-dark.png>")
    exit(1)
}
let width = source.width, height = source.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

// Measured from the supplied logo (ink green and sage), and the app icon's ivory #F7F4E9.
let ink: [Double] = [16, 56, 48]
let sage: [Double] = [156, 184, 158]
let ivory: [Double] = [247, 244, 233]
let step: [Double] = [sage[0] - ink[0], sage[1] - ink[1], sage[2] - ink[2]]
let stepLength: Double = step[0] * step[0] + step[1] * step[1] + step[2] * step[2]

for i in stride(from: 0, to: pixels.count, by: 4) {
    let alpha = Double(pixels[i + 3])
    if alpha == 0 { continue }
    // Un-premultiply, then place the color between ink (0) and sage (1).
    var projection: Double = 0
    for k in 0..<3 {
        let channel = Double(pixels[i + k]) * 255 / alpha
        projection += (channel - ink[k]) * step[k]
    }
    let t = max(0, min(1, projection / stepLength))
    for k in 0..<3 {
        let reversed = ivory[k] + (sage[k] - ivory[k]) * t
        pixels[i + k] = UInt8(max(0, min(255, (reversed * alpha / 255).rounded())))
    }
}

let output = context.makeImage()!
let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: arguments[2]))
print("wrote \(arguments[2])")
