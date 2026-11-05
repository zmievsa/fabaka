import Cocoa

private let width: CGFloat = 640
private let rowHeight: CGFloat = 40
private let padding: CGFloat = 8
private let iconSize: CGFloat = 28

/// The Switcher's window: a list of rows that never takes keyboard focus.
final class SwitcherPanel: NSPanel {
    var onClick: ((Int) -> Void)? {
        get { rows.onClick }
        set { rows.onClick = newValue }
    }

    private let rows = RowsView()
    private let scroll = NSScrollView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        contentView = background

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.documentView = rows
        background.addSubview(scroll)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ windows: [TrackedWindow], selection: Int) {
        rows.items = windows.map(Row.init)
        rows.selection = selection
        let screen = Self.activeScreen()
        let contentHeight = CGFloat(windows.count) * rowHeight
        let maxHeight = screen.visibleFrame.height * 0.8 - padding * 2
        let height = min(contentHeight, maxHeight) + padding * 2
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.midY - height / 2,
                           width: width, height: height)
        setFrame(frame, display: false)
        scroll.frame = NSRect(x: padding, y: padding, width: width - padding * 2, height: height - padding * 2)
        rows.frame = NSRect(x: 0, y: 0, width: width - padding * 2, height: contentHeight)
        rows.needsDisplay = true
        rows.scrollToSelection()
        orderFrontRegardless()
    }

    func select(_ index: Int) {
        rows.selection = index
        rows.needsDisplay = true
        rows.scrollToSelection()
    }

    /// The screen of the focused window, or the screen under the mouse.
    private static func activeScreen() -> NSScreen {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let front = WindowTracker.cgWindows(onScreenOnly: true).first(where: { $0.pid == pid }) {
            // WindowServer coordinates start top-left; AppKit's start bottom-left.
            let center = NSPoint(x: front.bounds.midX, y: primaryHeight - front.bounds.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return screen }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private struct Row {
    let icon: NSImage?
    let title: String
    let appName: String
    let isMinimized: Bool
    let isHidden: Bool

    init(_ window: TrackedWindow) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        icon = app?.icon
        appName = app?.localizedName ?? ""
        title = window.title.isEmpty ? appName : window.title
        isMinimized = window.isMinimized
        isHidden = app?.isHidden ?? false
    }
}

private final class RowsView: NSView {
    var items: [Row] = []
    var selection = 0
    var onClick: ((Int) -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(point.y / rowHeight)
        if items.indices.contains(index) { onClick?(index) }
    }

    func scrollToSelection() {
        scrollToVisible(NSRect(x: 0, y: CGFloat(selection) * rowHeight, width: bounds.width, height: rowHeight))
    }

    override func draw(_ dirtyRect: NSRect) {
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        for (index, item) in items.enumerated() {
            let rect = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: bounds.width, height: rowHeight)
            guard rect.intersects(dirtyRect) else { continue }
            let selected = index == selection
            if selected {
                NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 1), xRadius: 8, yRadius: 8).fill()
            }
            let dim = item.isMinimized || item.isHidden
            item.icon?.draw(in: NSRect(x: rect.minX + 8, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize),
                            from: .zero, operation: .sourceOver, fraction: dim ? 0.5 : 1, respectFlipped: true, hints: nil)

            let primary: NSColor = selected ? .white : (dim ? .secondaryLabelColor : .labelColor)
            let secondary: NSColor = selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
            let appAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondary, .paragraphStyle: truncating]
            let appText = NSAttributedString(string: item.appName, attributes: appAttrs)
            let appWidth = min(ceil(appText.size().width), 160)
            let appRect = NSRect(x: rect.maxX - 12 - appWidth, y: rect.midY - 7, width: appWidth, height: 16)
            appText.draw(with: appRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

            var titleMaxX = appRect.minX - 12
            if let symbol = item.isMinimized ? "minus.square" : (item.isHidden ? "eye.slash" : nil),
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                   .withSymbolConfiguration(.init(pointSize: 11, weight: .regular).applying(.init(paletteColors: [secondary]))) {
                let size = image.size
                titleMaxX -= size.width
                image.draw(in: NSRect(x: titleMaxX, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                titleMaxX -= 8
            }

            let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: primary, .paragraphStyle: truncating]
            let titleX = rect.minX + 8 + iconSize + 10
            NSAttributedString(string: item.title, attributes: titleAttrs)
                .draw(with: NSRect(x: titleX, y: rect.midY - 8, width: max(0, titleMaxX - titleX), height: 18),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}
