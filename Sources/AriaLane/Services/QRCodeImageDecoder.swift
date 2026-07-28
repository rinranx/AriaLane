import Foundation
import Vision

enum QRCodeImageDecoder {
    static func payloads(in imageData: Data) throws -> [String] {
        guard !imageData.isEmpty else { return [] }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(data: imageData)
        try handler.perform([request])

        return request.results?
            .compactMap(\.payloadStringValue)
            .filter { !$0.trimmed.isEmpty } ?? []
    }
}

enum QRCodeDownloadPayloadParser {
    static func downloadURLs(from payloads: [String]) -> [String] {
        DownloadInputParser.parse(payloads.joined(separator: "\n")).urls
    }
}
