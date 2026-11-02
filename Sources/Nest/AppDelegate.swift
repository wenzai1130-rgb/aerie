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
    private var snapshot: [MenuBarItem] = []
    private var drawerItems: [MenuBarItem] = []

    private let imposterRestingWidth: CGFloat = 10
    private let collapseWidth: CGFloat = 1800

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        BlinkWatcher.shared = watcher
        watcher.onAttention = { [weak self] in self?.autoReveal() }
        watcher.onQuiet = { [weak self] in self?.autoTuckBack() }

        handleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureHandleButton()

        imposterItem = NSStatusBar.system.statusItem(withLength: imposterRestingWidth)
        imposterItem.button?.title = ""

        placeImposterLeftOfHandle()
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
        b.image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Nest")
        b.image?.size = NSSize(width: 18, height: 18)
        b.target = self
        b.action = #selector(handleClicked)
        b.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateHandleIcon() {
        guard let b = handleItem.button else { return }
        let symbol = isCollapsed ? "bird.fill" : "bird"
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Nest")
        b.image?.size = NSSize(width: 18, height: 18)
    }

    @objc private func handleClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            isCollapsed ? expand() : collapse()
        }
    }

    // MARK: - Drawer

    /// Tuck the drawer: widen the invisible wall so every icon left
    /// of it slides out of the visible bar. Icons are never moved by
    /// Nest itself — the wall simply grows, and macOS tucks them away.
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

    /// Nest owns two status items: the bird (has an image → wider)
    /// and the invisible drawer wall (narrow). Pick the narrow one.
    private func findImposter(in items: [MenuBarItem]) -> MenuBarItem? {
        let mine = items.filter { $0.pid == getpid() }
        guard mine.count >= 2 else { return nil }
        return mine.min { $0.size.width < $1.size.width }
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

        let quit = NSMenuItem(title: "退出 Nest Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        handleItem.menu = m
        handleItem.button?.performClick(nil)
        handleItem.menu = nil
    }

    @objc private func toggleFromMenu() { isCollapsed ? expand() : collapse() }

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
