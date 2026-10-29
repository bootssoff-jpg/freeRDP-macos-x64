import AppKit

// Offline rendering of real views with reserved demo hosts. No server,
// Keychain, global pasteboard or saved profiles are read or written here.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.appearance = NSAppearance(named: .aqua)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let russian = ProcessInfo.processInfo.environment["RDPMAC_LANGUAGE"] == "ru"
let suffix = russian ? ".ru" : ""
var work = Profile(); work.name = "Design workstation"; work.host = "design.example.invalid"
work.username = "designer"; work.domain = "EXAMPLE"; work.group = "Studio"
var server = Profile(); server.name = "Build server"; server.host = "build.example.invalid"
server.username = "builder"; server.group = "Studio"
var home = Profile(); home.name = "Home PC"; home.host = "home.example.invalid"
home.username = "demo"; home.group = "Home lab"
func render(_ window: NSWindow, name: String) throws {
    guard let view = window.contentView else { fatalError("Missing content view") }
    view.appearance = NSAppearance(named: .aqua)
    view.layoutSubtreeIfNeeded()
    // AppKit's printing path renders native cells as well as layer-backed
    // subviews. cacheDisplay alone omits some native control text offscreen.
    var rendered: Data?
    view.appearance?.performAsCurrentDrawingAppearance {
        let pdf = view.dataWithPDF(inside: view.bounds)
        if let image = NSImage(data: pdf),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            // Printing preserves transparency outside native controls. Flatten
            // onto the light window background so labels remain visible.
            let context = CGContext(data: nil, width: cg.width, height: cg.height,
                                    bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(bounds)
            context.draw(cg, in: bounds)
            if let finalImage = context.makeImage() {
                rendered = NSBitmapImageRep(cgImage: finalImage).representation(using: .png, properties: [:])
            }
        }
    }
    guard let data = rendered else { fatalError("Cannot render native preview") }
    try data.write(to: root.appendingPathComponent("docs/images/\(name)\(suffix).png"))
}
let manager = ConnectionsWindowController()
manager.profilesProvider = { [work,server,home] }
manager.reload()
try render(manager.window!, name: "connections")
let form = ConnectFormView()
form.setProfiles([work,server,home], selectedID: work.id)
form.applyProfile(work, password: nil)
let formWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 620),
                          styleMask: [.titled], backing: .buffered, defer: false)
form.translatesAutoresizingMaskIntoConstraints = true
form.autoresizingMask = [.width,.height]
formWindow.contentView = form
form.frame = formWindow.contentView!.bounds
try render(formWindow, name: "connection-form")
print("Rendered \(russian ? "Russian" : "English") interface previews with demo profiles.")
