import AppKit
import CoreImage
import XCTest
@testable import AriaLane

final class QRCodeImageDecoderTests: XCTestCase {
    func testDecodesQRCodeFromImageData() throws {
        let expectedURL = "https://example.com/archive.zip"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(expectedURL.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        let outputImage = try XCTUnwrap(filter.outputImage)
            .transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(
            outputImage,
            from: outputImage.extent
        ) else {
            throw XCTSkip(
                "Core Image rendering is unavailable in this test environment"
            )
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        let pngData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )

        XCTAssertEqual(
            try QRCodeImageDecoder.payloads(in: pngData),
            [expectedURL]
        )
    }

    func testExtractsSupportedLinksFromMultiplePayloadsAndDeduplicates() {
        let urls = QRCodeDownloadPayloadParser.downloadURLs(
            from: [
                "plain text",
                "https://example.com/file.zip",
                "magnet:?xt=urn:btih:ABC123\nhttps://example.com/file.zip"
            ]
        )

        XCTAssertEqual(
            urls,
            [
                "https://example.com/file.zip",
                "magnet:?xt=urn:btih:ABC123"
            ]
        )
    }
}
