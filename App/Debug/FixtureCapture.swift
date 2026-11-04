#if DEBUG
import CoreGraphics
import ImageIO
import KakeiboCore
import KakeiboScan
import KakeiboStore
import SwiftUI
import UniformTypeIdentifiers

/// Debug only: saves the scan being reviewed as parser fixture files (T-24).
///
/// Writes `real-<timestamp>.txt` (rebuilt OCR lines, personal numbers masked),
/// `real-<timestamp>.expected.json` (the form's current values) and, when there is a photo,
/// `real-<timestamp>.jpg` (downscaled to the OCR size, for re-OCR later; not for the repo).
@MainActor
enum FixtureCapture {
    static func makeFiles(from form: ReviewForm, now: Date = .now) throws -> [URL] {
        let name = FixtureWriter.name(at: now)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let lines = (form.ocrText ?? "").components(separatedBy: "\n")
        let text = folder.appendingPathComponent("\(name).txt")
        try Data(FixtureWriter.text(lines: lines).utf8).write(to: text, options: .atomic)

        let json = folder.appendingPathComponent("\(name).expected.json")
        try FixtureWriter.expectedJSON(from: form.draft, scannedOn: now, lines: lines).write(to: json, options: .atomic)

        var urls = [text, json]
        if let image = uprightImage(form.pendingPhoto), let data = jpeg(image) {
            let jpg = folder.appendingPathComponent("\(name).jpg")
            try data.write(to: jpg, options: .atomic)
            urls.append(jpg)
        }
        return urls
    }

    private static func uprightImage(_ photo: ReviewForm.PendingPhoto?) -> CGImage? {
        switch photo {
        case .image(let image): ImageDownscaler.downscale(image, maxPixelSize: KakeiboScan.maxOCRPixelSize)
        case .data(let data): ImageDecoding.uprightImage(from: data, maxPixelSize: KakeiboScan.maxOCRPixelSize)
        case nil: nil
        }
    }

    /// JPEG without metadata (no GPS, no camera details).
    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// Lists the fixture files and shares them (AirDrop to the Mac).
struct FixtureShareSheet: View {
    let urls: [URL]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(urls, id: \.self) { url in
                    Label { Text(verbatim: url.lastPathComponent).font(.code) } icon: {
                        Image(systemName: url.pathExtension == "jpg" ? "photo" : "doc.text")
                    }
                    .foregroundStyle(Theme.text)
                }
                Text(verbatim: "Correct every field in the form before saving: the JSON is the expected answer. Card, member and approval numbers are masked; check the .txt for anything else personal before committing. Keep the .jpg out of the repo.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                ShareLink(items: urls) {
                    Label { Text(verbatim: "Share fixture files") } icon: { Image(systemName: "square.and.arrow.up") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("fixture.share")
                Spacer()
            }
            .padding(20)
            .background(Theme.groundLight.ignoresSafeArea())
            .navigationTitle(Text(verbatim: "Save as fixture"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { dismiss() } label: { Text(verbatim: "Done") }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fixture")
    }
}
#endif
