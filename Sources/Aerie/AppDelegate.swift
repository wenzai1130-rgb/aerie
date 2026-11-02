import AppKit
import ApplicationServices
import ServiceManagement

/// Aerie — the aerie at the top of your screen.
///
/// Mechanism (the only one macOS 26 actually allows):
/// every app owns its own status items and may resize *them*; no app
/// may move or resize anyone else's (verified: AX writes return
/// -25200 / kAXErrorCannotComplete for every foreign item). So the
/// nest is made of our own two items:
///
///     [ tucked icons ]  ❘  🐦
///
/// The `❘` is our wall. Its resting width is a hairline; clicking the
/// bird stretches it to thousands of points, which pushes everything
/// to its left off the screen edge — macOS does the hiding for us.
/// Click again and the wall shrinks, so those icons slide back.
///
/// Nothing of anyone else's is ever touched. No icon can get lost.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var birdItem: NSStatusItem!      // the handle you click
    private var wallItem: NSStatusItem!      // the hairline that hides
    private let watcher = BlinkWatcher()

    private var isCollapsed = false
    private var peekReturn: DispatchWorkItem?

    /// Wide enough to push anyone's icons off the left edge of any
    /// display. The system clips whatever no longer fits.
    private let collapsedWallWidth: CGFloat = 3000

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        BlinkWatcher.shared = watcher
        watcher.onAttention = { [weak self] in self?.peek() }
        watcher.onQuiet = { [weak self] in self?.endPeek() }

        // Order matters: macOS inserts newer status items to the LEFT,
        // so creating the wall after the bird puts it exactly where the
        // drawer's edge belongs — right beside the bird, with no setup.
        birdItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = birdItem.button {
            b.image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Aerie")
            b.image?.size = NSSize(width: 17, height: 17)
            b.target = self
            b.action = #selector(birdClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.toolTip = "Aerie — 点我收起/展开，右键看巢里有什么"
        }

        wallItem = NSStatusBar.system.statusItem(withLength: 16)
        if let w = wallItem.button {
            w.image = Self.wallImage()
            w.target = self
            w.action = #selector(birdClicked)
            w.sendAction(on: [.leftMouseUp, .rightMouseUp])
            w.toolTip = "抽屉门 — ⌘ 把想收起的图标拖到我这根线左边，点小鸟收起它们"
        }

        if !Permissions.hasAccessibility {
            Permissions.promptAccessibility()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            MenuBarScanner.diagnose()
            self.refreshWatcher()
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        // Never quit with the wall stretched wide — that is exactly how
        // icons get stranded off-screen.
        if isCollapsed {
            wallItem?.length = 16
        }
    }

    // MARK: - Click

    @objc private func birdClicked() {
        NSLog("[Aerie] 收到点击（%@），当前=%@，墙宽=%.0f",
              NSApp.currentEvent?.type == .rightMouseUp ? "右键" : "左键",
              isCollapsed ? "收起" : "展开",
              wallItem.length)
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            isCollapsed ? expand() : collapse()
        }
    }

    /// A crisp hairline drawn as a template image: text glyphs at
    /// ultra-light weight were nearly invisible in the menu bar.
    private static func wallImage() -> NSImage {
        let size = NSSize(width: 12, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.move(to: NSPoint(x: 6, y: 2))
        path.line(to: NSPoint(x: 6, y: 14))
        path.stroke()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    // MARK: - Collapse / expand

    private func collapse() {
        guard !isCollapsed else { return }
        isCollapsed = true
        peekReturn?.cancel()
        // A widened item centres its content, which would leave the
        // hairline floating somewhere mid-bar — hide it while closed.
        wallItem.button?.image = nil
        wallItem.length = collapsedWallWidth
        NSLog("[Aerie] 收起：墙撑到 %.0f，左侧图标滑出屏幕", collapsedWallWidth)

        // Self-check: what is still visible half a second later?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.isCollapsed else { return }
            let all = MenuBarScanner.allItems()
            let visible = all.filter {
                $0.size.width > 4 && $0.position.y < 60 && $0.position.x > -10
            }
            let names = visible.map { "\(Int($0.position.x)):\($0.title.isEmpty ? "?" : $0.title)" }
            NSLog("[Aerie][验证] 收起后仍可见 %d 项 — %@", visible.count, names.joined(separator: "  "))
            for own in all where own.pid == getpid() {
                NSLog("[Aerie][验证] 自己的项 x=%.0f y=%.0f w=%.0f", own.position.x, own.position.y, own.size.width)
            }
        }
    }

    private func expand() {
        guard isCollapsed else { return }
        isCollapsed = false
        peekReturn?.cancel()
        wallItem.length = 16
        wallItem.button?.image = Self.wallImage()
        NSLog("[Aerie] 展开：墙恢复成一条细线")
        refreshWatcherSoon()
    }

    /// A tucked icon changed its label (new message / new state):
    /// let the drawer slide open for a few seconds, then close again.
    private func peek() {
        guard isCollapsed else { return }
        wallItem.length = 16
        wallItem.button?.image = Self.wallImage()
        NSLog("[Aerie] 巢里有图标动了，探出头 5 秒")
        peekReturn?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endPeek() }
        peekReturn = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func endPeek() {
        guard isCollapsed, !(peekReturn?.isCancelled ?? true) else { return }
        wallItem.button?.image = nil
        wallItem.length = collapsedWallWidth
        NSLog("[Aerie] 探头结束，重新收好")
    }

    // MARK: - What lives in the nest

    /// Everything currently to the left of the wall, i.e. everything the
    /// wall will push away. Zero-size entries are the corpses older menu
    /// bar managers left off-screen; they are not in the nest.
    private func nestItems() -> [MenuBarItem] {
        let items = MenuBarScanner.allItems()
        let ours = items.filter { $0.pid == getpid() }.sorted { $0.position.x < $1.position.x }
        guard let wall = ours.first else { return [] }
        return items.filter { it in
            it.pid != getpid()
                && it.size.width > 4
                && it.position.y < 60
                && it.position.x + it.size.width <= wall.position.x + 2
        }
    }

    private func refreshWatcherSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshWatcher()
        }
    }

    private func refreshWatcher() {
        // While collapsed the icons sit off-screen; their elements stay
        // valid, so we keep watching the drawer we already registered.
        guard !isCollapsed else { return }
        let hidden = nestItems()
        watcher.start(watched: hidden)
        NSLog("[Aerie] 巢里现有 %d 个图标", hidden.count)
        for own in MenuBarScanner.allItems() where own.pid == getpid() {
            NSLog("[Aerie] 自己的项 x=%.0f y=%.0f w=%.0f title=%@",
                  own.position.x, own.position.y, own.size.width,
                  own.title.isEmpty ? "(空)" : own.title)
        }
    }

    // MARK: - Menu

    private func showMenu() {
        // Icons only have real coordinates while the drawer is open.
        if isCollapsed {
            expand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.presentMenu()
            }
        } else {
            presentMenu()
        }
    }

    private func presentMenu() {
        let m = NSMenu()
        let hidden = nestItems()

        if hidden.isEmpty {
            let hint = NSMenuItem(title: "巢是空的 — ⌘ 把图标拖到小鸟左边的竖线外",
                                  action: nil, keyEquivalent: "")
            hint.isEnabled = false
            m.addItem(hint)
        } else {
            let head = NSMenuItem(title: "🐦 巢里的图标（点一下打开）", action: nil, keyEquivalent: "")
            head.isEnabled = false
            m.addItem(head)
            for it in hidden {
                let app = NSRunningApplication(processIdentifier: it.pid)
                let name = it.title.isEmpty ? (app?.localizedName ?? "pid \(it.pid)") : it.title
                let mi = NSMenuItem(title: name, action: #selector(openNested(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = Int(it.pid)
                mi.image = app?.icon
                m.addItem(mi)
            }
        }

        m.addItem(.separator())

        let toggle = NSMenuItem(title: isCollapsed ? "展开图标 Expand" : "收起图标 Tuck",
                                action: #selector(toggleFromMenu), keyEquivalent: "")
        toggle.target = self
        m.addItem(toggle)

        let launch = NSMenuItem(title: "登录时启动 Launch at Login",
                                action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        m.addItem(launch)

        let help = NSMenuItem(title: "怎么用：⌘ 拖图标到 ❘ 左边 → 点小鸟收起",
                              action: nil, keyEquivalent: "")
        help.isEnabled = false
        m.addItem(help)

        m.addItem(.separator())

        let quit = NSMenuItem(title: "退出 Aerie Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        birdItem.menu = m
        birdItem.button?.performClick(nil)
        birdItem.menu = nil
    }

    @objc private func openNested(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int,
              let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return }
        if !app.activate() {
            // Some helper items have no windows of their own.
            NSSound.beep()
        }
    }

    @objc private func toggleFromMenu() {
        isCollapsed ? expand() : collapse()
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
