import Foundation

/// Per-profile traffic/quality preferences. They are sent to the server once in
/// the Client Info PDU, so a change applies on the next connection; Windows may
/// ignore individual behaviour flags.
struct QualityPolicy: Codable, Equatable {
    enum Preset: Int, Codable, CaseIterable {
        case normal = 0
        case slow = 1
        case custom = 2

        var title: String {
            switch self {
            case .normal:
                return L("Обычное")
            case .slow:
                return L("Медленный интернет")
            case .custom:
                return L("Пользовательское")
            }
        }
    }

    var preset: Preset = .normal

    // Used only when preset == .custom; presets resolve to fixed values so an
    // upgrade can improve them without touching saved profiles.
    var disableWallpaper: Bool = false
    var disableThemes: Bool = false
    var disableAnimations: Bool = true
    var disableFullWindowDrag: Bool = true
    var allowDesktopComposition: Bool = false
    var allowFontSmoothing: Bool = true
    var colorDepth: Int = 32
    var compressionLevel: Int = 3
    var resizeThrottle: Double = 0.45

    static let `default` = QualityPolicy()

    init() {}

    // Old profiles.json files have no quality key.
    private enum CodingKeys: String, CodingKey {
        case preset, disableWallpaper, disableThemes, disableAnimations,
             disableFullWindowDrag, allowDesktopComposition, allowFontSmoothing,
             colorDepth, compressionLevel, resizeThrottle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decodeIfPresent(Preset.self, forKey: .preset) ?? .normal
        disableWallpaper = try container.decodeIfPresent(Bool.self, forKey: .disableWallpaper) ?? false
        disableThemes = try container.decodeIfPresent(Bool.self, forKey: .disableThemes) ?? false
        disableAnimations = try container.decodeIfPresent(Bool.self, forKey: .disableAnimations) ?? true
        disableFullWindowDrag =
            try container.decodeIfPresent(Bool.self, forKey: .disableFullWindowDrag) ?? true
        allowDesktopComposition =
            try container.decodeIfPresent(Bool.self, forKey: .allowDesktopComposition) ?? false
        allowFontSmoothing =
            try container.decodeIfPresent(Bool.self, forKey: .allowFontSmoothing) ?? true
        colorDepth = try container.decodeIfPresent(Int.self, forKey: .colorDepth) ?? 32
        compressionLevel = try container.decodeIfPresent(Int.self, forKey: .compressionLevel) ?? 3
        resizeThrottle = try container.decodeIfPresent(Double.self, forKey: .resizeThrottle) ?? 0.45
    }

    /// Applies the resolved preset to the FreeRDP session options.
    func apply(to options: RDPMacSessionOptions) {
        switch preset {
        case .normal:
            options.disableWallpaper = false
            options.disableThemes = false
            options.disableAnimations = true
            options.disableFullWindowDrag = true
            options.allowDesktopComposition = false
            options.allowFontSmoothing = true
            options.colorDepth = 32
            options.compressionLevel = 3
        case .slow:
            options.disableWallpaper = true
            options.disableThemes = true
            options.disableAnimations = true
            options.disableFullWindowDrag = true
            options.allowDesktopComposition = false
            options.allowFontSmoothing = false
            options.colorDepth = 32
            options.compressionLevel = 3
        case .custom:
            options.disableWallpaper = disableWallpaper
            options.disableThemes = disableThemes
            options.disableAnimations = disableAnimations
            options.disableFullWindowDrag = disableFullWindowDrag
            options.allowDesktopComposition = allowDesktopComposition
            options.allowFontSmoothing = allowFontSmoothing
            options.colorDepth = colorDepth == 16 ? 16 : 32
            let level = (1...3).contains(compressionLevel) ? compressionLevel : 3
            options.compressionLevel = UInt(level)
        }
    }

    /// DisplayControl debounce in seconds; slower links benefit from fewer
    /// resize requests while the window is dragged.
    var effectiveResizeThrottle: Double {
        switch preset {
        case .normal:
            return 0.45
        case .slow:
            return 1.2
        case .custom:
            return min(3.0, max(0.2, resizeThrottle))
        }
    }

    /// Slow preset starts from a small, non-Retina desktop. The form applies
    /// this visibly (resolution popup changes), never silently at connect time.
    static let slowStartResolution = ResolutionPolicy(preset: .r1280x720, retina: false)

    var summary: String {
        switch preset {
        case .normal:
            return L("Обычное качество: обои, темы и сглаживание шрифтов включены.")
        case .slow:
            return L("Медленный интернет: без обоев, тем и сглаживания шрифтов; реже запросы изменения размера.")
        case .custom:
            var parts: [String] = []
            if disableWallpaper { parts.append(L("без обоев")) }
            if disableThemes { parts.append(L("без тем")) }
            if !allowFontSmoothing { parts.append(L("без сглаживания")) }
            if colorDepth == 16 { parts.append(L("16 бит")) }
            parts.append(L("сжатие %@", String(describing: compressionLevel)))
            return L("Пользовательское: %@", parts.joined(separator: ", "))
        }
    }
}
