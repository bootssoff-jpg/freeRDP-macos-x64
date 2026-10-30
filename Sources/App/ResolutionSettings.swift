import AppKit

/// Remote desktop size for one profile. Three separate things are kept apart:
/// the remote Windows resolution, how the image is fitted into the window, and
/// whether the session uses Retina density.
struct ResolutionPolicy: Codable, Equatable {
    enum Preset: Int, Codable, CaseIterable {
        case window = 0
        case r1024x768 = 1
        case r1280x720 = 2
        case r1600x900 = 3
        case r1920x1080 = 4
        case r2560x1440 = 5
        case custom = 6
    }

    /// Hard limits. The bridge accepts up to 8192 and FreeRDP's DisplayControl
    /// clamps to the same value, but two framebuffer copies at that size would
    /// need about 500 MB, so the app stops at a 4096 × 2560 desktop.
    static let minWidth = 640
    static let minHeight = 480
    static let maxWidth = 4096
    static let maxHeight = 2560
    static let windowMinWidth = 800
    static let windowMinHeight = 600

    var preset: Preset = .window
    var customWidth: Int = 1600
    var customHeight: Int = 900
    /// Window preset: use the display's backing scale for the remote size.
    /// Fixed presets: request 200 % Windows DPI scaling (servers may ignore it).
    var retina: Bool = true

    static let `default` = ResolutionPolicy()

    init(preset: Preset = .window, customWidth: Int = 1600, customHeight: Int = 900,
         retina: Bool = true) {
        self.preset = preset
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.retina = retina
    }

    /// Legacy 1.0.x profiles stored a plain Int: 0 window, 1 1280×720,
    /// 2 1920×1080, 3 2560×1440. Older fixed modes always ignored Retina.
    init(legacyValue: Int) {
        switch legacyValue {
        case 1:
            self.init(preset: .r1280x720, retina: false)
        case 2:
            self.init(preset: .r1920x1080, retina: false)
        case 3:
            self.init(preset: .r2560x1440, retina: false)
        default:
            self.init(preset: .window, retina: true)
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case preset, customWidth, customHeight, retina
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let legacyValue = try? single.decode(Int.self) {
            self.init(legacyValue: legacyValue)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try container.decodeIfPresent(Preset.self, forKey: .preset) ?? .window
        let width = try container.decodeIfPresent(Int.self, forKey: .customWidth) ?? 1600
        let height = try container.decodeIfPresent(Int.self, forKey: .customHeight) ?? 900
        let retina = try container.decodeIfPresent(Bool.self, forKey: .retina) ?? true
        self.init(preset: preset, customWidth: width, customHeight: height, retina: retina)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encode(customWidth, forKey: .customWidth)
        try container.encode(customHeight, forKey: .customHeight)
        try container.encode(retina, forKey: .retina)
    }

    // MARK: - Presentation

    var title: String {
        switch preset {
        case .window:
            return L("Как в окне")
        case .r1024x768:
            return "1024 × 768"
        case .r1280x720:
            return "1280 × 720"
        case .r1600x900:
            return "1600 × 900"
        case .r1920x1080:
            return "1920 × 1080"
        case .r2560x1440:
            return "2560 × 1440"
        case .custom:
            return L("Другой размер…")
        }
    }

    var isCustom: Bool { preset == .custom }
    /// Only the window preset follows the window; fixed sizes never resize the
    /// remote desktop when the window changes.
    var allowsAutoResize: Bool { preset == .window }

    /// Percentage sent to Windows. Meaningful for fixed presets; window mode
    /// expresses Retina through the framebuffer size instead.
    var desktopScaleFactor: Int { retina ? 200 : 100 }

    // MARK: - Size

    func size(forWindow contentSize: NSSize, backingScale: CGFloat) -> (width: Int, height: Int) {
        switch preset {
        case .window:
            let scale = retina ? max(1.0, backingScale) : 1.0
            let width = Int((contentSize.width * scale).rounded(.down))
            let height = Int((contentSize.height * scale).rounded(.down))
            return (Self.even(max(Self.windowMinWidth, min(width, Self.maxWidth))),
                    Self.even(max(Self.windowMinHeight, min(height, Self.maxHeight))))
        case .r1024x768:
            return (1024, 768)
        case .r1280x720:
            return (1280, 720)
        case .r1600x900:
            return (1600, 900)
        case .r1920x1080:
            return (1920, 1080)
        case .r2560x1440:
            return (2560, 1440)
        case .custom:
            return (Self.clamped(customWidth, min: Self.minWidth, max: Self.maxWidth),
                    Self.clamped(customHeight, min: Self.minHeight, max: Self.maxHeight))
        }
    }

    /// Explains an out-of-range custom size instead of silently changing it.
    var customSizeWarning: String? {
        guard preset == .custom else { return nil }
        if customWidth > Self.maxWidth || customHeight > Self.maxHeight {
            return L("Больше %@×%@ не поддерживается: ограничение памяти клиента.",
                     String(describing: Self.maxWidth), String(describing: Self.maxHeight))
        }
        if customWidth < Self.minWidth || customHeight < Self.minHeight {
            return L("Минимальный размер — %@×%@.", String(describing: Self.minWidth),
                     String(describing: Self.minHeight))
        }
        return nil
    }

    static func clamped(_ value: Int, min lower: Int, max upper: Int) -> Int {
        even(max(lower, min(value, upper)))
    }

    static func even(_ value: Int) -> Int {
        value & ~1
    }
}

