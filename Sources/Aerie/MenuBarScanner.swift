import AppKit
import ApplicationServices

/// Reads the macOS menu bar via the Accessibility API.
///
/// Every running process exposes its status items through the
/// `AXExtrasMenuBar` attribute of its application element.
/// Aerie uses this to:
///  - snapshot the original layout (so we can always restore it),
///  - list icons for the panic "restore menu bar" action,
///  - watch tucked-away icons for attention (BlinkWatcher).
struct MenuBarItem {
    let pid: pid_t
    let appElement: AXUIElement
    let element: AXUIElement
    let title: String
    let position: CGPoint
    let size: CGSize
}

enum MenuBarScanner {

    static func allItems() -> [MenuBarItem] {
        var result: [MenuBarItem] = []
        let apps = NSWorkspace.shared.runningApplications.filter {
            // Include ourselves: as an LSUIElement app we are .accessory,
            // yet our bird/wall items are exactly what we need to see.
            $0.activationPolicy == .regular
                || $0.processIdentifier == getpid()
                || $0.bundleIdentifier?.hasPrefix("com.apple") == true
        }
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.5)
            guard let barRef = element(appElement, kAXExtrasMenuBarAttribute),
                  CFGetTypeID(barRef) == AXUIElementGetTypeID() else { continue }
            let bar = barRef as! AXUIElement
            guard let kidsRef = element(bar, kAXChildrenAttribute),
                  let children = kidsRef as? [AXUIElement] else { continue }
            for child in children {
                guard let pos = point(child), let size = size(of: child) else { continue }
                let title = string(child, kAXTitleAttribute)
                    ?? string(child, kAXDescriptionAttribute)
                    ?? ""
                result.append(MenuBarItem(
                    pid: app.processIdentifier,
                    appElement: appElement,
                    element: child,
                    title: title,
                    position: pos,
                    size: size
                ))
            }
        }
        return result.sorted { $0.position.x < $1.position.x }
    }

    /// One-shot probe: is the Accessibility API usable at all?
    /// .apiDisabled (-25211) means macOS revoked/never granted trust.
    static func diagnose() {
        let sysWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(sysWide, "AXFocusedApplication" as CFString, &value)
        NSLog("[Aerie][诊断] AXIsProcessTrusted=%@ AX 探针错误码=%d (%@)",
              Permissions.hasAccessibility ? "true" : "false",
              err.rawValue,
              err == .success ? "正常" : err == .apiDisabled ? "⚠️ 无辅助功能权限" : "其他错误")
        // Keep every AX call snappy — a hung app must not stall the event tap.
        AXUIElementSetMessagingTimeout(sysWide, 0.5)
    }

    /// Debug: dump everything we can see in the menu bar.
    static func dumpItems() {
        let t0 = Date()
        let items = allItems()
        NSLog("[Aerie][dump] 共 %d 项，耗时 %.2fs（本进程 pid=%d）", items.count, Date().timeIntervalSince(t0), getpid())
        for it in items {
            NSLog("[Aerie][dump]   pid=%-6d x=%7.0f y=%4.0f w=%5.0f h=%4.0f  title=%@",
                  it.pid, it.position.x, it.position.y, it.size.width, it.size.height, it.title)
        }
    }

    /// Diagnostic: for every menu bar item, try a no-op write to the
    /// position and size attributes and report the AX error code.
    /// This tells us whether macOS 26 lets third-party apps move or
    /// hide *other* apps' status items at all.
    static func probeWritability() {
        let items = allItems()
        NSLog("[Aerie][probe] 共 %d 项，本进程 pid=%d", items.count, getpid())
        for it in items {
            var p = it.position
            let posValue = AXValueCreate(.cgPoint, &p)
            let ePos = posValue.map {
                AXUIElementSetAttributeValue(it.element, kAXPositionAttribute as CFString, $0).rawValue
            } ?? -999
            var s = it.size
            let sizeValue = AXValueCreate(.cgSize, &s)
            let eSize = sizeValue.map {
                AXUIElementSetAttributeValue(it.element, kAXSizeAttribute as CFString, $0).rawValue
            } ?? -999
            var posSettable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(it.element, kAXPositionAttribute as CFString, &posSettable)
            var sizeSettable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(it.element, kAXSizeAttribute as CFString, &sizeSettable)
            let role = string(it.element, kAXRoleAttribute) ?? "?"
            let sub = string(it.element, kAXSubroleAttribute) ?? "?"
            NSLog("[Aerie][probe] pid=%-6d x=%6.0f y=%4.0f w=%4.0f setPos=%d setSize=%d posOK=%@ sizeOK=%@ role=%@/%@ title=%@",
                  it.pid, it.position.x, it.position.y, it.size.width,
                  ePos, eSize,
                  posSettable.boolValue ? "Y" : "N",
                  sizeSettable.boolValue ? "Y" : "N",
                  role, sub,
                  it.title.isEmpty ? "(空)" : it.title)
        }
    }

    // MARK: - AX helpers

    static func element(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        element(el, attr) as? String
    }

    static func point(_ el: AXUIElement) -> CGPoint? {
        guard let ref = element(el, kAXPositionAttribute) else { return nil }
        let axValue = ref as! AXValue
        var p = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &p) else { return nil }
        return p
    }

    static func size(of el: AXUIElement) -> CGSize? {
        guard let ref = element(el, kAXSizeAttribute) else { return nil }
        let axValue = ref as! AXValue
        var s = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &s) else { return nil }
        return s
    }

    /// Find the status item of process `pid` that currently sits at
    /// `position` (top-left, within a few pixels) — used to translate
    /// a dropped window back into its AX element.
    static func element(at position: CGPoint, inApp pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        guard let barRef = element(appEl, kAXExtrasMenuBarAttribute),
              CFGetTypeID(barRef) == AXUIElementGetTypeID() else { return nil }
        let bar = barRef as! AXUIElement
        guard let kidsRef = element(bar, kAXChildrenAttribute),
              let children = kidsRef as? [AXUIElement] else { return nil }
        for child in children {
            if let p = point(child), abs(p.x - position.x) < 4, abs(p.y - position.y) < 4 {
                return child
            }
        }
        return nil
    }

    @discardableResult
    static func setPosition(_ el: AXUIElement, _ p: CGPoint) -> Bool {
        var point = p
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        let err = AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, value)
        if err != .success { NSLog("[Aerie][AX] setPosition 失败 err=%d", err.rawValue) }
        return err == .success
    }

    @discardableResult
    static func setSize(_ el: AXUIElement, _ s: CGSize) -> Bool {
        var size = s
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        let err = AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, value)
        if err != .success { NSLog("[Aerie][AX] setSize 失败 err=%d", err.rawValue) }
        return err == .success
    }

    static func parent(of el: AXUIElement) -> AXUIElement? {
        guard let ref = element(el, kAXParentAttribute),
              CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return ref as! AXUIElement
    }

    /// Debug: print the role chain from this element up to the app.
    static func logRoleChain(_ el: AXUIElement, tag: String) {
        var current = el
        for depth in 0..<5 {
            let role = string(current, kAXRoleAttribute) ?? "?"
            let subrole = string(current, kAXSubroleAttribute) ?? "?"
            let desc = string(current, kAXDescriptionAttribute) ?? ""
            NSLog("[Aerie][链][%@] #%d role=%@ subrole=%@ desc=%@", tag, depth, role, subrole, desc)
            guard let p = parent(of: current) else { break }
            current = p
        }
    }

    /// System-wide hit test: which accessibility element lives at this
    /// screen point? immune to stale reported positions — the system
    /// resolves the element for us. Normalized to the direct child of
    /// a menu bar (the status item itself).
    static func hitTest(at p: CGPoint) -> AXUIElement? {
        let sysWide = AXUIElementCreateSystemWide()
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sysWide, Float(p.x), Float(p.y), &el) == .success,
              let hit = el else { return nil }
        return normalizeToMenuBarItem(hit)
    }

    /// Climb parents until `current` is a direct child of an AXMenuBar
    /// (the extras menu bar counts as one), so we operate on the item
    /// itself rather than an inner button/image.
    private static func normalizeToMenuBarItem(_ el: AXUIElement) -> AXUIElement {
        var current = el
        for _ in 0..<6 {
            guard let parentRef = element(current, kAXParentAttribute),
                  CFGetTypeID(parentRef) == AXUIElementGetTypeID() else { break }
            let parent = parentRef as! AXUIElement
            guard string(parent, kAXRoleAttribute) == "AXMenuBar" else {
                current = parent
                continue
            }
            break
        }
        return current
    }
}
