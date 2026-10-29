import AppKit
import CoreGraphics

/// Renders the BGRX framebuffer supplied by the FreeRDP bridge and forwards
/// mouse/keyboard input. All drawing happens on the main thread.
final class RDPView: NSView {
    weak var client: RDPMacClient?

    private var frameData = Data()
    private var remoteWidth = 0
    private var remoteHeight = 0
    private var tracking: NSTrackingArea?

    // Use the standard (bottom-left) AppKit coordinate system: CGImage is
    // drawn upright there. Mouse coordinates are converted explicitly below.
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // MARK: - Rendering

    private var imageRect: NSRect {
        guard remoteWidth > 0, remoteHeight > 0 else { return .zero }
        let scale = min(bounds.width / CGFloat(remoteWidth), bounds.height / CGFloat(remoteHeight))
        guard scale > 0 else { return .zero }
        let size = NSSize(width: CGFloat(remoteWidth) * scale, height: CGFloat(remoteHeight) * scale)
        return NSRect(x: (bounds.width - size.width) / 2,
                      y: (bounds.height - size.height) / 2,
                      width: size.width,
                      height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        guard let client else { return }

        let width = Int(client.frameWidth)
        let height = Int(client.frameHeight)
        guard width > 0, height > 0 else { return }

        let expected = width * height * 4
        if remoteWidth != width || remoteHeight != height || frameData.count != expected {
            remoteWidth = width
            remoteHeight = height
            frameData = Data(count: expected)
        }

        let stride = width * 4
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return }

        frameData.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var copiedWidth = 0
            var copiedHeight = 0
            let ok = client.copyFrame(intoBuffer: base,
                                      capacity: raw.count,
                                      stride: stride,
                                      width: &copiedWidth,
                                      height: &copiedHeight)
            guard ok, copiedWidth > 0, copiedHeight > 0 else { return }

            guard let provider = CGDataProvider(dataInfo: nil,
                                                data: base.assumingMemoryBound(to: UInt8.self),
                                                size: raw.count,
                                                releaseData: { _, _, _ in }) else { return }
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue |
                                          CGBitmapInfo.byteOrder32Little.rawValue)
            guard let image = CGImage(width: copiedWidth,
                                      height: copiedHeight,
                                      bitsPerComponent: 8,
                                      bitsPerPixel: 32,
                                      bytesPerRow: stride,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo,
                                      provider: provider,
                                      decode: nil,
                                      shouldInterpolate: true,
                                      intent: .defaultIntent) else { return }

            context.interpolationQuality = .high
            context.draw(image, in: rect)
        }
    }

    func invalidate(remoteRect: CGRect) {
        guard remoteWidth > 0, remoteHeight > 0 else {
            needsDisplay = true
            return
        }
        let scale = imageRect.width / CGFloat(remoteWidth)
        guard scale > 0 else {
            needsDisplay = true
            return
        }
        // remoteRect uses top-left origin; the view uses bottom-left.
        let viewRect = NSRect(x: imageRect.minX + remoteRect.minX * scale,
                              y: imageRect.maxY - remoteRect.maxY * scale,
                              width: remoteRect.width * scale,
                              height: remoteRect.height * scale)
        setNeedsDisplay(viewRect.insetBy(dx: -2, dy: -2))
    }

    // MARK: - Coordinates

    private func remotePoint(_ event: NSEvent) -> (x: Int, y: Int) {
        let rect = imageRect
        guard rect.width > 0, rect.height > 0, remoteWidth > 0, remoteHeight > 0 else {
            return (0, 0)
        }
        let point = convert(event.locationInWindow, from: nil)
        let normalizedX = (point.x - rect.minX) / rect.width
        // AppKit y grows upward; the remote framebuffer y grows downward.
        let normalizedY = (rect.maxY - point.y) / rect.height
        let x = Int((normalizedX * CGFloat(remoteWidth)).rounded(.down))
        let y = Int((normalizedY * CGFloat(remoteHeight)).rounded(.down))
        return (max(0, min(x, remoteWidth - 1)), max(0, min(y, remoteHeight - 1)))
    }

    private func focusIfNeeded() {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        focusIfNeeded()
        let point = remotePoint(event)
        client?.sendMouseButton(0, down: true, x: Int32(point.x), y: Int32(point.y))
    }

    override func mouseUp(with event: NSEvent) {
        let point = remotePoint(event)
        client?.sendMouseButton(0, down: false, x: Int32(point.x), y: Int32(point.y))
    }

    override func rightMouseDown(with event: NSEvent) {
        focusIfNeeded()
        let point = remotePoint(event)
        client?.sendMouseButton(1, down: true, x: Int32(point.x), y: Int32(point.y))
    }

    override func rightMouseUp(with event: NSEvent) {
        let point = remotePoint(event)
        client?.sendMouseButton(1, down: false, x: Int32(point.x), y: Int32(point.y))
    }

    override func otherMouseDown(with event: NSEvent) {
        focusIfNeeded()
        let point = remotePoint(event)
        let button: Int32
        switch event.buttonNumber {
        case 2: button = 2
        case 3: button = 3
        case 4: button = 4
        default: return
        }
        client?.sendMouseButton(button, down: true, x: Int32(point.x), y: Int32(point.y))
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = remotePoint(event)
        let button: Int32
        switch event.buttonNumber {
        case 2: button = 2
        case 3: button = 3
        case 4: button = 4
        default: return
        }
        client?.sendMouseButton(button, down: false, x: Int32(point.x), y: Int32(point.y))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = remotePoint(event)
        client?.sendMouseMoveTo(x: Int32(point.x), y: Int32(point.y))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = remotePoint(event)
        client?.sendMouseMoveTo(x: Int32(point.x), y: Int32(point.y))
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let point = remotePoint(event)
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 0.1 : 1.0
        let dy = Double(event.scrollingDeltaY * factor)
        let dx = Double(event.scrollingDeltaX * factor)
        if dy != 0 {
            client?.sendMouseWheelHorizontal(false,
                                             points: dy,
                                             x: Int32(point.x),
                                             y: Int32(point.y))
        }
        if dx != 0 {
            client?.sendMouseWheelHorizontal(true,
                                             points: dx,
                                             x: Int32(point.x),
                                             y: Int32(point.y))
        }
    }

    // MARK: - Keyboard

    /// The Edit menu owns Cmd+C/V/X/A/Z for text fields. When the remote
    /// desktop has focus these shortcuts must be forwarded to Windows instead
    /// (with Command mapped to Ctrl by the bridge).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else { return false }
        let flags = event.modifierFlags
        guard flags.contains(.command),
              !flags.contains(.shift),
              !flags.contains(.option),
              !flags.contains(.control),
              let key = event.charactersIgnoringModifiers?.lowercased(),
              ["c", "v", "x", "a", "z", "y"].contains(key) else {
            return false
        }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        client?.sendKeyEvent(withKeyCode: event.keyCode,
                             characters: event.characters ?? "",
                             modifiers: event.modifierFlags.rawValue,
                             down: true,
                             repeat: event.isARepeat)
    }

    override func keyUp(with event: NSEvent) {
        client?.sendKeyEvent(withKeyCode: event.keyCode,
                             characters: event.characters ?? "",
                             modifiers: event.modifierFlags.rawValue,
                             down: false,
                             repeat: false)
    }

    override func flagsChanged(with event: NSEvent) {
        client?.sendModifierFlags(event.modifierFlags.rawValue)
    }
}
