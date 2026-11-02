import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var handleItem: NSStatusItem!      // the bird (handle)
    private var imposterItem: NSStatusItem!    // the drawer wall
    private var isCollapsed = false
    private var isAutoRevealed = false

    private let watcher = BlinkWatcher()
    private let detector = DropDetector()
    private var snapshot: [MenuBarItem] = []
    private var drawerItems: [MenuBarItem] = []

    private let imposterRestingWidth: CGFloat = 10
    private let collapseWidth: CGFloat = 1800

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        BlinkWatcher.shared = watcher
        watcher.onAttention = { [weak self] in self?.autoReveal() }
        watcher.onQuiet = { [weak self] in self?.autoTuckBack() }

        detector.onTuck = { [weak self] pid, el in
            self?.tuck(pid: pid, element: el)
        }
        detector.start()

        handleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureHandleButton()

        imposterItem = NSStatusBar.system.statusItem(withLength: imposterRestingWidth)
        if let b = imposterItem.button {
            b.image = Self.wallImage()
            b.image?.size = NSSize(width: 5, height: 18)
            b.accessibilityLabel = "Aerie wall"
        }

        refreshDrawerAndWatcher()

        if !Permissions.hasAccessibility {
            Permissions.promptAccessibility()
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        // Always put every icon back before leaving.
        expandNow()
        restoreSnapshot()
    }

    // MARK: - Handle

    private func configureHandleButton() {
        guard let b = handleItem.button else { return }
        b.image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Aerie")
        b.image?.size = NSSize(width: 18, height: 18)
        b.target = self
        b.action = #selector(handleClicked)
        b.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateHandleIcon() {
        guard let b = handleItem.button else { return }
        let symbol = isCollapsed ? "bird.fill" : "bird"
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Aerie")
        b.image?.size = NSSize(width: 18, height: 18)
    }

    @objc private func handleClicked() {
        showMenu()
    }

    // MARK: - Tucking (drag onto the bird)

    /// The user dropped an icon onto the bird: slide it to the far
    /// side of the wall, then widen the wall so it disappears inside.
    private func tuck(pid: pid_t, element: AXUIElement) {
        let items = MenuBarScanner.allItems()
        guard let wall = findImposter(in: items) else { return }
        let drawer = items.filter { $0.position.x + $0.size.width <= wall.position.x + 2 }
        let targetRight = (drawer.map { $0.position.x }.min() ?? wall.position.x) - 2
        let size = MenuBarScanner.size(of: element) ?? CGSize(width: 30, height: 24)
        let x = targetRight - size.width
        _ = MenuBarScanner.setPosition(element, CGPoint(x: x, y: wall.position.y))
        NSSound(named: "Pop")?.play()
        refreshDrawerAndWatcher()
        collapse()
    }

    // MARK: - Drawer

    /// Tuck the drawer: widen the invisible wall so every icon left
    /// of it slides out of the visible bar. Icons are never moved by
    /// Aerie itself — the wall simply grows, and macOS tucks them away.
    private func collapse() {
        guard !isCollapsed else { return }
        refreshDrawerAndWatcher()
        imposterItem.length = collapseWidth
        isCollapsed = true
        isAutoRevealed = false
        updateHandleIcon()
    }

    private func expand(auto: Bool = false) {
        guard isCollapsed else { return }
        imposterItem.length = imposterRestingWidth
        isCollapsed = false
        isAutoRevealed = auto
        updateHandleIcon()
        refreshDrawerAndWatcher()
    }

    private func expandNow() {
        imposterItem.length = imposterRestingWidth
        isCollapsed = false
        updateHandleIcon()
    }

    private func autoReveal() {
        guard isCollapsed else { return }
        expand(auto: true)
    }

    private func autoTuckBack() {
        // Only re-tuck if the reveal was ours, not the user's.
        if isAutoRevealed { collapse() }
    }

    // MARK: - Scanning

    private func refreshDrawerAndWatcher() {
        let items = MenuBarScanner.allItems()
        snapshot = items
        guard let imposter = findImposter(in: items) else { return }
        // Everything resting left of the wall belongs to the drawer.
        drawerItems = items.filter { $0.position.x + $0.size.width <= imposter.position.x + 2 }
        watcher.start(watched: drawerItems)
    }

    /// Aerie owns two status items: the bird (has an image → wider)
    /// and the invisible drawer wall (narrow). Pick the narrow one.
    private func findImposter(in items: [MenuBarItem]) -> MenuBarItem? {
        let mine = items.filter { $0.pid == getpid() }
        guard mine.count >= 2 else { return nil }
        return mine.min { $0.size.width < $1.size.width }
    }

    /// A short visible line so the wall can be seen and ⌘-dragged.
    private static func wallImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 5, height: 18))
        img.lockFocus()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2, width: 2, height: 14), xRadius: 1, yRadius: 1).fill()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    /// On first launch, slide the wall just left of the bird so the
    /// drawer is ready to use. Self-AX does not require permissions.
    private func placeImposterLeftOfHandle() {
        let items = MenuBarScanner.allItems().filter { $0.pid == getpid() }
        guard items.count >= 2,
              let handle = items.max(by: { $0.size.width < $1.size.width }),
              let imp = items.min(by: { $0.size.width < $1.size.width }),
              imp.element !== handle.element else { return }
        let targetX = handle.position.x - imp.size.width - 4
        _ = MenuBarScanner.setPosition(imp.element, CGPoint(x: targetX, y: handle.position.y))
    }

    // MARK: - Panic restore

    private func restoreSnapshot() {
        guard Permissions.hasAccessibility else { return }
        let current = MenuBarScanner.allItems()
        for old in snapshot {
            guard let now = current.first(where: { $0.pid == old.pid && $0.title == old.title }) else { continue }
            _ = MenuBarScanner.setPosition(now.element, old.position)
        }
    }

    // MARK: - Menu

    private func showMenu() {
        let m = NSMenu()

        let drawer = drawerItems
        if drawer.isEmpty {
            let hint = NSMenuItem(title: "抽屉是空的 — 按住 ⌘ 把图标拖到小鸟上即可收藏",
                                  action: nil, keyEquivalent: "")
            hint.isEnabled = false
            m.addItem(hint)
        } else {
            let title = NSMenuItem(title: "🐦 巢里的图标（点击打开）",
                                   action: nil, keyEquivalent: "")
            title.isEnabled = false
            m.addItem(title)
            for it in drawer {
                let app = NSRunningApplication(processIdentifier: it.pid)
                let name = it.title.isEmpty ? (app?.localizedName ?? "pid \(it.pid)") : it.title
                let mi = NSMenuItem(title: name,
                                    action: #selector(openDrawerApp(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = Int(it.pid)
                mi.image = app?.icon
                m.addItem(mi)
            }
        }

        m.addItem(.separator())

        let toggle = NSMenuItem(title: isCollapsed ? "展开抽屉 Expand Drawer" : "收起抽屉 Tuck Icons",
                                action: #selector(toggleFromMenu), keyEquivalent: "")
        toggle.target = self
        m.addItem(toggle)

        m.addItem(.separator())

        let launch = NSMenuItem(title: "登录时启动 Launch at Login",
                                action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        m.addItem(launch)

        let restore = NSMenuItem(title: "恢复菜单栏布局 Restore Layout",
                                 action: #selector(restoreLayout), keyEquivalent: "")
        restore.target = self
        m.addItem(restore)

        m.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Aerie Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        handleItem.menu = m
        handleItem.button?.performClick(nil)
        handleItem.menu = nil
    }

    @objc private func toggleFromMenu() { isCollapsed ? expand() : collapse() }

    @objc private func openDrawerApp(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int,
              let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return }
        app.activate()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister()
            default: try service.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func restoreLayout() {
        restoreSnapshot()
        refreshDrawerAndWatcher()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
