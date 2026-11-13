import Cocoa
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window: two shelves of app icons. Stays holds Resident apps; Flickable holds every other app
/// the Dock shows as running. Clicking an icon flicks it to the other shelf.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView())
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "Flick Settings"
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Model

struct ShelfApp: Identifiable, Equatable {
    let id: String // bundle ID
    let name: String
    let icon: NSImage
    let isRunning: Bool
}

private final class ShelvesModel: ObservableObject {
    @Published private(set) var stays: [ShelfApp] = []
    @Published private(set) var flickable: [ShelfApp] = []
    private var tokens: [NSObjectProtocol] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reload() })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: .residentsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        })
        reload()
    }

    deinit {
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
    }

    func reload() {
        let selfID = Bundle.main.bundleIdentifier
        var running: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !Rules.isExcluded(app) {
            if let id = app.bundleIdentifier, id != selfID, running[id] == nil { running[id] = app }
        }
        let residents = Residents.shared.bundleIDs
        // A resident that is neither running nor installed (Tailscale's other bundle) has nothing to show.
        stays = residents.compactMap { id in
            if let app = running[id] { return ShelfApp(id: id, name: app.localizedName ?? id, icon: app.icon ?? Self.icon(id), isRunning: true) }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return ShelfApp(id: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                            icon: NSWorkspace.shared.icon(forFile: url.path), isRunning: false)
        }
        flickable = running.filter { !residents.contains($0.key) }
            .map { ShelfApp(id: $0.key, name: $0.value.localizedName ?? $0.key, icon: $0.value.icon ?? Self.icon($0.key), isRunning: true) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func icon(_ id: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func keep(_ id: String) { Residents.shared.add(id) }
    func letGo(_ id: String) { Residents.shared.remove(id) }

    /// Adds apps picked in Finder, by their bundle IDs.
    func keep(appsAt urls: [URL]) {
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            keep(id)
        }
    }

    func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps that stay"
        panel.prompt = "Keep Running"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        keep(appsAt: panel.urls)
    }
}

// MARK: - Views

private let flick = Animation.spring(response: 0.42, dampingFraction: 0.68)
/// Residents are always on, so their shelf and running lights take the colour of a power LED.
private let alwaysOn = Color(nsColor: .systemGreen)
private let tileWidth: CGFloat = 84
private let iconSize: CGFloat = 56

private struct SettingsView: View {
    @StateObject private var model = ShelvesModel()
    @Namespace private var shelves
    @AppStorage(SwitcherController.hideOnQuickTapKey) private var hideOnQuickTap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Who stays?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("When an app has no windows open, ⌘Tab still lists it so Q can quit it. Apps on the Stays shelf are always running for a reason, so they are left off that list.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 26)

            Shelf(kind: .stays, apps: model.stays, namespace: shelves, model: model)
                .padding(.bottom, 22)
            Shelf(kind: .flickable, apps: model.flickable, namespace: shelves, model: model)

            Label("Click an app to flick it to the other shelf. Drag apps from Finder onto Stays.", systemImage: "hand.tap")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 18)

            Divider()
                .padding(.vertical, 20)

            Toggle(isOn: $hideOnQuickTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Skip the Switcher on a quick tap")
                        .font(.system(size: 13, weight: .medium))
                    Text("Waits \(Int(SwitcherController.showDelay * 1000)) ms before showing it, so a quick ⌘Tab back to the last window doesn't flash the list. Tab or an arrow shows it at once.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(alwaysOn)
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 600)
        .background(WindowMaterial().ignoresSafeArea())
    }
}

private enum ShelfKind {
    case stays, flickable

    var title: String { self == .stays ? "Stays" : "Flickable" }
    var subtitle: String {
        self == .stays ? "Always running, never offered to quit" : "Q quits them from ⌘Tab once their windows close"
    }
    var empty: String {
        self == .stays ? "Nothing stays. Every app with no windows can be quit from ⌘Tab."
            : "No other apps are running."
    }
}

private struct Shelf: View {
    let kind: ShelfKind
    let apps: [ShelfApp]
    let namespace: Namespace.ID
    @ObservedObject var model: ShelvesModel
    @State private var targeted = false

    private var tint: Color { kind == .stays ? alwaysOn : .primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(kind.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(kind.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if kind == .stays {
                    Button(action: model.chooseApps) {
                        Label("Add App", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("Choose apps in Finder that should stay")
                }
            }

            ZStack(alignment: .topLeading) {
                if apps.isEmpty {
                    Text(kind.empty)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 104)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth), spacing: 6)], alignment: .leading, spacing: 8) {
                    ForEach(apps) { app in
                        Tile(app: app, kind: kind) {
                            withAnimation(flick) { kind == .stays ? model.letGo(app.id) : model.keep(app.id) }
                        }
                        .matchedGeometryEffect(id: app.id, in: namespace)
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ShelfBackground(tint: tint, highlighted: targeted))
            .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: $targeted, perform: drop)
        }
    }

    /// Accepts icons dragged from the other shelf (as bundle IDs) and, on Stays, apps dragged from Finder.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                guard kind == .stays else { continue }
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension == "app" else { return }
                    DispatchQueue.main.async { withAnimation(flick) { model.keep(appsAt: [url]) } }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                accepted = true
                _ = provider.loadObject(ofClass: NSString.self) { id, _ in
                    guard let id = id as? String else { return }
                    DispatchQueue.main.async {
                        withAnimation(flick) { kind == .stays ? model.keep(id) : model.letGo(id) }
                    }
                }
            }
        }
        return accepted
    }
}

/// A Dock-like shelf: a tinted tray with a lit top edge and a soft shadow underneath, so icons sit on it.
private struct ShelfBackground: View {
    let tint: Color
    let highlighted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(tint.opacity(highlighted ? 0.18 : 0.08))
            .overlay(shape.strokeBorder(tint.opacity(highlighted ? 0.7 : 0.22), lineWidth: 1))
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.09), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
            .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

private struct Tile: View {
    let app: ShelfApp
    let kind: ShelfKind
    let action: () -> Void
    @State private var hovering = false
    @State private var wiggle = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(app.isRunning ? 1 : 0.55)
                    .rotationEffect(.degrees(wiggle ? 3.5 : (hovering && kind == .flickable ? -3.5 : 0)))
                    .scaleEffect(hovering ? 1.08 : 1)
                    .shadow(color: .black.opacity(hovering ? 0.25 : 0.12), radius: hovering ? 6 : 3, y: hovering ? 4 : 2)
                    .overlay(alignment: .topTrailing) {
                        if hovering {
                            Image(systemName: kind == .stays ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .font(.system(size: 18))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, kind == .stays ? Color.secondary : alwaysOn)
                                .offset(x: 6, y: -6)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                Text(app.name)
                    .font(.system(size: 11))
                    .foregroundStyle(app.isRunning ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // The Dock's running dot; on Stays it's a lit pilot light.
                Circle()
                    .fill(kind == .stays ? alwaysOn : Color.primary.opacity(0.55))
                    .frame(width: kind == .stays ? 5 : 4, height: kind == .stays ? 5 : 4)
                    .shadow(color: kind == .stays ? alwaysOn.opacity(0.9) : .clear, radius: 3)
                    .opacity(app.isRunning ? 1 : 0)
            }
            .frame(width: tileWidth)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(kind == .stays ? "\(app.name) stays. Click to let ⌘Tab offer to quit it."
                             : "Click to keep \(app.name) running: ⌘Tab won't offer to quit it.")
        .accessibilityLabel(app.name)
        .accessibilityHint(kind == .stays ? "Moves it to Flickable" : "Moves it to Stays")
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
            // Flickable icons come loose under the pointer, like the Dock's jiggle.
            if kind == .flickable {
                if inside {
                    withAnimation(.easeInOut(duration: 0.11).repeatForever(autoreverses: true)) { wiggle = true }
                } else {
                    withAnimation(.easeOut(duration: 0.1)) { wiggle = false }
                }
            }
        }
        .onDrag { NSItemProvider(object: app.id as NSString) }
    }
}

private struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
