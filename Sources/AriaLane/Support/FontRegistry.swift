import CoreText
import Foundation

enum FontRegistry {
    private static var hasRegisteredBundledFonts = false

    static func registerBundledFonts() {
        guard !hasRegisteredBundledFonts else { return }
        hasRegisteredBundledFonts = true

        let fontURLs = Bundle.main.urls(
            forResourcesWithExtension: "ttf",
            subdirectory: "Fonts"
        ) ?? []

        for url in fontURLs {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
