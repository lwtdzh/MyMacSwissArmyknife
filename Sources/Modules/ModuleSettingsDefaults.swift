import Foundation

enum ModuleSettingsDefaults {
    static let scrollDomain = "com.mymacswissarmyknife.ScrollReverser"
    static let resourceDomain = "com.mymacswissarmyknife.ResourceMonitor"
    static let clipyDomain = ClipyEnhancedBridge.defaultsDomain

    static func seed() {
        seedScrollReverser()
        seedResourceMonitor()
        seedClipyEnhanced()
    }

    private static func seedScrollReverser() {
        guard let defaults = UserDefaults(suiteName: scrollDomain) else { return }
        setIfMissing(true, key: "ReverseY", defaults: defaults)
        setIfMissing(false, key: "ReverseX", defaults: defaults)
        setIfMissing(true, key: "ReverseTrackpad", defaults: defaults)
        setIfMissing(true, key: "ReverseMouse", defaults: defaults)
        setIfMissing(3, key: "DiscreteScrollStepSize", defaults: defaults)
    }

    private static func seedResourceMonitor() {
        guard let defaults = UserDefaults(suiteName: resourceDomain) else { return }
        setIfMissing(true, key: "showMenuBar", defaults: defaults)
        setIfMissing(true, key: "showFloatingPanel", defaults: defaults)
        setIfMissing(true, key: "floatingPanelAlwaysOnTop", defaults: defaults)
        setIfMissing(true, key: "showDownload", defaults: defaults)
        setIfMissing(true, key: "showUpload", defaults: defaults)
        setIfMissing(true, key: "showDiskRead", defaults: defaults)
        setIfMissing(true, key: "showDiskWrite", defaults: defaults)
        setIfMissing(true, key: "showCPU", defaults: defaults)
        setIfMissing(true, key: "showMemory", defaults: defaults)
        setIfMissing("bits", key: "dataRateUnit", defaults: defaults)
        setIfMissing(1, key: "refreshInterval", defaults: defaults)
    }

    private static func seedClipyEnhanced() {
        guard let defaults = UserDefaults(suiteName: clipyDomain) else { return }
        setIfMissing(30, key: "kCPYPrefMaxHistorySizeKey", defaults: defaults)
        setIfMissing(true, key: "kCPYPrefInputPasteCommandKey", defaults: defaults)
        setIfMissing(true, key: "kCPYPrefReorderClipsAfterPasting", defaults: defaults)
        setIfMissing(
            Dictionary(
                uniqueKeysWithValues: [
                    "String", "RTF", "RTFD", "PDF",
                    "Filenames", "URL", "TIFF", "Binary"
                ].map { ($0, true) }
            ),
            key: "kCPYPrefStoreTypesKey",
            defaults: defaults
        )

        setIfMissing(20, key: "kCPYPrefMaxMenuItemTitleLengthKey", defaults: defaults)
        setIfMissing(0, key: "kCPYPrefNumberOfItemsPlaceInlineKey", defaults: defaults)
        setIfMissing(10, key: "kCPYPrefNumberOfItemsPlaceInsideFolderKey", defaults: defaults)
        setIfMissing(false, key: "kCPYPrefMenuItemsTitleStartWithZeroKey", defaults: defaults)
        setIfMissing(true, key: "kCPYPrefShowAlertBeforeClearHistoryKey", defaults: defaults)
        setIfMissing(true, key: "kCPYPrefAddClearHistoryMenuItemKey", defaults: defaults)
        setIfMissing(true, key: "kCPYPrefShowIconInTheMenuKey", defaults: defaults)
        setIfMissing(true, key: "menuItemsAreMarkedWithNumbers", defaults: defaults)
        setIfMissing(false, key: "addNumericKeyEquivalents", defaults: defaults)
        setIfMissing(true, key: "showToolTipOnMenuItem", defaults: defaults)
        setIfMissing(true, key: "showImageInTheMenu", defaults: defaults)
        setIfMissing(200, key: "maxLengthOfToolTipKey", defaults: defaults)
        setIfMissing(100, key: "thumbnailWidth", defaults: defaults)
        setIfMissing(32, key: "thumbnailHeight", defaults: defaults)
        setIfMissing(true, key: "kCPYPrefOverwriteSameHistroy", defaults: defaults)
        setIfMissing(true, key: "kCPYPrefCopySameHistroy", defaults: defaults)
        setIfMissing(true, key: "kCPYPrefShowColorPreviewInTheMenu", defaults: defaults)

        setIfMissing(true, key: "kCPYBetaPastePlainText", defaults: defaults)
        setIfMissing(0, key: "kCPYBetaPastePlainTextModifier", defaults: defaults)
        setIfMissing(false, key: "kCPYBetaDeleteHistory", defaults: defaults)
        setIfMissing(0, key: "kCPYBetaDeleteHistoryModifier", defaults: defaults)
        setIfMissing(false, key: "kCPYBetaPasteAndDeleteHistory", defaults: defaults)
        setIfMissing(0, key: "kCPYBetapasteAndDeleteHistoryModifier", defaults: defaults)
        setIfMissing(false, key: "kCPYBetaObserveScreenshot", defaults: defaults)
    }

    private static func setIfMissing(
        _ value: Any,
        key: String,
        defaults: UserDefaults
    ) {
        if defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
