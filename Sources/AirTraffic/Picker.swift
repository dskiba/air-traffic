import AppKit
import Carbon.HIToolbox
import AirTrafficCore

/// A borderless panel that takes keyboard focus without activating the app (like Spotlight).
final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Two faces of one panel, built once at launch:
/// - picker: a link arrived and no rule matched. Icons near the cursor, ⌘Tab-style.
/// - launcher: the hotkey. A Spotlight-style field to type or paste a link.
/// No show/hide animation: it must feel instant.
final class Picker: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    var onChoose: (_ urls: [URL], _ choice: Choice, _ save: Bool, _ priv: Bool) -> Void = { _, _, _, _ in }
    var preselect: (URL) -> Target? = { _ in nil }
    var parse: (String) -> URL? = { _ in nil }

    private let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let glass = NSGlassEffectView()

    private let header = NSTextField(labelWithString: "")
    private let bigRow = TileRow(iconSize: 52)
    private let pickerDetail = NSTextField(labelWithString: "")
    private let pickerFooter = NSTextField(labelWithString: "")
    private lazy var pickerView = stack([header, bigRow, pickerDetail, pickerFooter], spacing: 8, insets: 14, minWidth: 300)

    private let symbol = NSImageView()
    private let field = NSTextField()
    private let smallRow = TileRow(iconSize: 26)
    private let launcherDetail = NSTextField(labelWithString: "")
    private let launcherFooter = NSTextField(labelWithString: "")
    private lazy var launcherView = makeLauncherView()

    private var choices: [Choice] = []
    private var selected = 0
    private var urls: [URL] = []
    private var launcher = false
    /// The user chose a browser by hand (⇥, arrows, hover): typing must not override it.
    private var manual = false
    private var monitor: Any?

    override init() {
        super.init()
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        glass.cornerRadius = 24
        panel.contentView = glass

        style(header, size: 13, color: .secondaryLabelColor)
        header.lineBreakMode = .byTruncatingMiddle
        style(pickerDetail, size: 13, weight: .semibold, color: .labelColor)
        style(pickerFooter, size: 11, color: .tertiaryLabelColor)
        style(launcherDetail, size: 12, color: .secondaryLabelColor)
        launcherDetail.alignment = .left
        launcherDetail.lineBreakMode = .byTruncatingMiddle
        style(launcherFooter, size: 11, color: .tertiaryLabelColor)

        symbol.symbolConfiguration = .init(pointSize: 18, weight: .medium)
        symbol.contentTintColor = .secondaryLabelColor
        field.placeholderString = "Open a link or search…"
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.lineBreakMode = .byTruncatingHead
        field.delegate = self

        for row in [bigRow, smallRow] {
            row.onClick = { [weak self] i, flags in self?.choose(i, save: flags.contains(.command), priv: flags.contains(.shift)) }
            row.onHover = { [weak self] i in self?.manual = true; self?.select(i) }
        }
    }

    // MARK: Showing

    func show(_ urls: [URL], choices: [Choice]) {
        // macOS may deliver several links as separate events: join the picker that's already open.
        let urls = panel.isVisible && !launcher ? self.urls + urls : urls
        guard let url = urls.first else { return }
        launcher = false
        self.urls = urls
        header.attributedStringValue = Self.headline(url, more: urls.count - 1)
        let host = Links.host(url).map { " for \($0)" } ?? ""
        pickerFooter.attributedStringValue = Self.keys([("1–9 ↵", "Open"), ("⇧", "Private"), ("⌘", "Always\(host)"), ("⌘C", "Copy")])
        present(pickerView, choices, preselect: preselect(url), atMouse: true)
    }

    func showLauncher(prefill: String, choices: [Choice]) {
        launcher = true
        field.stringValue = prefill
        launcherFooter.attributedStringValue = Self.keys([("↵", "Open"), ("⇥", "Browser"), ("⇧↵", "Private"), ("⌘↵", "Always")])
        present(launcherView, choices, preselect: parse(prefill).flatMap(preselect), atMouse: false)
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func present(_ view: NSView, _ choices: [Choice], preselect target: Target?, atMouse: Bool) {
        if self.choices.map(\.id) != choices.map(\.id) {
            self.choices = choices
            bigRow.set(choices)
            smallRow.set(choices)
        }
        if glass.contentView !== view { glass.contentView = view }
        manual = false
        select(index(of: target) ?? 0)

        let size = view.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        // Below the cursor, or above it near the bottom edge; never under it (no accidental hover).
        let below = mouse.y - size.height - 16
        var origin = atMouse
            ? NSPoint(x: mouse.x - size.width / 2, y: below >= vf.minY + 8 ? below : mouse.y + 16)
            : NSPoint(x: vf.midX - size.width / 2, y: vf.minY + vf.height * 0.66)
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)

        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.handle(e) ?? e }
        }
    }

    func close() {
        panel.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    func controlTextDidChange(_ obj: Notification) {
        if !manual, let url = parse(field.stringValue), let i = index(of: preselect(url)) { select(i) } else { updateDetail() }
    }

    // MARK: Selection & keys

    private func index(of target: Target?) -> Int? {
        guard let target else { return nil }
        // Exact profile first; a profile-less target (rule, fallback) falls back to the browser's first tile.
        return choices.firstIndex { $0.target.app == target.app && $0.target.profile == target.profile }
            ?? choices.firstIndex { $0.target.app == target.app }
    }

    private func select(_ i: Int) {
        guard !choices.isEmpty else { return }
        selected = (i + choices.count) % choices.count
        (launcher ? smallRow : bigRow).select(selected)
        updateDetail()
    }

    private func updateDetail() {
        guard choices.indices.contains(selected) else { return }
        let name = choices[selected].name
        guard launcher else { pickerDetail.stringValue = name; return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLink = Links.webURL(text) != nil
        symbol.image = NSImage(systemSymbolName: isLink || text.isEmpty ? "globe" : "magnifyingglass", accessibilityDescription: nil)
        launcherDetail.stringValue = text.isEmpty ? "Opens in \(name)"
            : isLink ? "Open \(Self.short(text)) in \(name)"
            : "Search “\(text)” in \(name)"
    }

    private static let digits: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
    ]
    private static let edits: [String: Selector] = [
        "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
    ]

    private func handle(_ e: NSEvent) -> NSEvent? {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = f.contains(.command), shift = f.contains(.shift)
        // Mid-composition (Japanese, Chinese…), ↵/esc/⇥ belong to the input method.
        if launcher, (field.currentEditor() as? NSTextView)?.hasMarkedText() == true { return e }
        switch Int(e.keyCode) {
        case kVK_Escape: close()
        case kVK_Return, kVK_ANSI_KeypadEnter: choose(selected, save: cmd, priv: shift)
        case kVK_Tab: manual = true; select(selected + (shift ? -1 : 1))
        case kVK_LeftArrow where !launcher: manual = true; select(selected - 1)
        case kVK_RightArrow where !launcher: manual = true; select(selected + 1)
        case let k where Self.digits[k] != nil && (!launcher || cmd):
            choose(Self.digits[k]! - 1, save: cmd && !launcher, priv: shift)
        default:
            let key = e.charactersIgnoringModifiers?.lowercased()
            if launcher {
                // No main menu in an agent app, so route the edit shortcuts to the field ourselves.
                if cmd, let key, let action = Self.edits[key] { NSApp.sendAction(action, to: nil, from: self); return nil }
                return e
            }
            if cmd, key == "c", !urls.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
                close()
            }
        }
        return nil
    }

    private func choose(_ i: Int, save: Bool, priv: Bool) {
        guard choices.indices.contains(i) else { return }
        // Never fall back to a normal window when a private one was asked for (Safari, Arc…).
        if priv && !Browsers.supportsPrivate(choices[i].target.app) { NSSound.beep(); return }
        let typed = parse(field.stringValue)
        let targets = launcher ? typed.map { [$0] } ?? [] : urls
        guard !targets.isEmpty else { NSSound.beep(); return }
        // "Always" only makes sense for a link, not for a search.
        let save = save && (!launcher || Links.webURL(field.stringValue) != nil)
        close()
        onChoose(targets, choices[i], save, priv)
    }

    // MARK: Building

    private func makeLauncherView() -> NSView {
        let input = NSStackView(views: [symbol, field])
        input.spacing = 10
        let line = NSBox()
        line.boxType = .separator
        let bottom = NSStackView(views: [launcherDetail, NSView(), smallRow])
        bottom.spacing = 12
        let view = stack([input, line, bottom, launcherFooter], spacing: 10, insets: 16, minWidth: 600)
        view.alignment = .leading
        for v in [input, line, bottom] {
            v.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -32).isActive = true
        }
        view.setCustomSpacing(12, after: input)
        return view
    }

    private func stack(_ views: [NSView], spacing: CGFloat, insets: CGFloat, minWidth: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.spacing = spacing
        s.edgeInsets = NSEdgeInsets(top: insets, left: insets, bottom: insets - 2, right: insets)
        s.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
        for v in views where v is NSTextField {
            v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            v.widthAnchor.constraint(lessThanOrEqualTo: s.widthAnchor, constant: -2 * insets).isActive = true
        }
        return s
    }

    private func style(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    /// "github.com/swiftlang/swift": host in label color, the rest muted. "+2 more" for several links.
    private static func headline(_ url: URL, more: Int) -> NSAttributedString {
        let text = short(url.absoluteString) + (more > 0 ? "  +\(more) more" : "")
        let host = Links.host(url) ?? ""
        let s = NSMutableAttributedString(string: text, attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 13)])
        if let r = text.range(of: host) {
            s.addAttributes([.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)], range: NSRange(r, in: text))
        }
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineBreakMode = .byTruncatingMiddle
        s.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: s.length))
        return s
    }

    private static func short(_ link: String) -> String {
        link.replacingOccurrences(of: "^https?://(www\\.)?", with: "", options: .regularExpression)
    }

    /// "↵ Open    ⇧ Private": keys in secondary, labels in tertiary.
    private static func keys(_ pairs: [(String, String)]) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let key: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor]
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]
        for (i, (k, l)) in pairs.enumerated() {
            if i > 0 { s.append(NSAttributedString(string: "    ", attributes: label)) }
            s.append(NSAttributedString(string: k + " ", attributes: key))
            s.append(NSAttributedString(string: l, attributes: label))
        }
        return s
    }
}

// MARK: - Tiles

final class TileRow: NSStackView {
    var onClick: (Int, NSEvent.ModifierFlags) -> Void = { _, _ in }
    var onHover: (Int) -> Void = { _ in }
    private let iconSize: CGFloat
    private var tiles: [Tile] = []

    init(iconSize: CGFloat) {
        self.iconSize = iconSize
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = iconSize > 40 ? 4 : 2
        if iconSize > 40 { edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ choices: [Choice]) {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = choices.enumerated().map { i, choice in
            let tile = Tile(choice, iconSize: iconSize)
            tile.onClick = { [weak self] flags in self?.onClick(i, flags) }
            tile.onHover = { [weak self] in self?.onHover(i) }
            addArrangedSubview(tile)
            return tile
        }
    }

    func select(_ index: Int) {
        for (i, tile) in tiles.enumerated() { tile.isSelected = i == index }
    }
}

final class Tile: NSView {
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onHover: () -> Void = {}
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }

    init(_ choice: Choice, iconSize: CGFloat) {
        let pad = (iconSize * 0.18).rounded()
        super.init(frame: NSRect(x: 0, y: 0, width: iconSize + 2 * pad, height: iconSize + 2 * pad))
        wantsLayer = true
        layer?.cornerRadius = (iconSize * 0.3).rounded()
        toolTip = choice.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(choice.name)

        let image = NSImageView(frame: NSRect(x: pad, y: pad, width: iconSize, height: iconSize))
        image.image = choice.icon
        image.imageScaling = .scaleProportionallyUpOrDown
        addSubview(image)

        if let badge = choice.badge {
            let d = (iconSize * 0.4).rounded()
            let dot = NSView(frame: NSRect(x: pad + iconSize - d * 0.8, y: pad - d * 0.15, width: d, height: d))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = badge.color.cgColor
            dot.layer?.cornerRadius = d / 2
            dot.layer?.borderWidth = 1.5
            dot.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            let letter = NSTextField(labelWithString: badge.letter)
            letter.font = .systemFont(ofSize: d * 0.55, weight: .bold)
            letter.textColor = .white
            letter.alignment = .center
            letter.sizeToFit()
            letter.frame = NSRect(x: 0, y: (d - letter.frame.height) / 2, width: d, height: letter.frame.height)
            dot.addSubview(letter)
            addSubview(dot)
        }
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: frame.width).isActive = true
        heightAnchor.constraint(equalToConstant: frame.height).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = isSelected ? NSColor.labelColor.withAlphaComponent(0.12).cgColor : nil
    }

    override func mouseDown(with event: NSEvent) { onClick(event.modifierFlags) }
    override func mouseMoved(with event: NSEvent) { onHover() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onClick([]); return true }
}
