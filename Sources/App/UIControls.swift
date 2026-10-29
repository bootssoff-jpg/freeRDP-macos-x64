import AppKit

enum UI {
    static func label(_ text: String,
                      size: CGFloat = 13,
                      weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor,
                      lines: Int = 1) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        field.maximumNumberOfLines = lines
        field.isSelectable = lines > 1
        return field
    }

    static func textField(placeholder: String, width: CGFloat? = nil) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.controlSize = .regular
        field.font = NSFont.systemFont(ofSize: 13)
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return field
    }

    static func secureField(placeholder: String, width: CGFloat? = nil) -> NSSecureTextField {
        let field = NSSecureTextField()
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 13)
        if let width {
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return field
    }

    static func button(_ title: String,
                       target: AnyObject?,
                       action: Selector?,
                       keyEquivalent: String = "") -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.keyEquivalent = keyEquivalent
        return button
    }

    static func checkbox(_ title: String,
                         target: AnyObject?,
                         action: Selector?,
                         state: Bool = false) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: target, action: action)
        button.state = state ? .on : .off
        return button
    }

    static func popup(_ titles: [String], target: AnyObject?, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles)
        popup.target = target
        popup.action = action
        return popup
    }

    static func hStack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    static func vStack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    static func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    static func statusDot() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 5
        view.layer?.backgroundColor = NSColor.systemGray.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 10).isActive = true
        view.heightAnchor.constraint(equalToConstant: 10).isActive = true
        return view
    }
}
