import AppKit
import ApplicationServices

/// Reads the macOS menu bar via the Accessibility API.
///
/// Every running process exposes its status items through the
/// `AXExtrasMenuBar` attribute of its application element.
/// Nest uses this to:
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
            $0.activationPolicy == .regular || $0.bundleIdentifier?.hasPrefix("com.apple") == true
        }
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let barRef = element(appElement, kAXExtrasMenuBarAttribute),
                  CFGetTypeID(barRef) == AXUIElementGetTypeID() else { continue }
            let bar = barRef as! AXUIElement
            guard let kidsRef = element(bar, kAXChildrenAttribute),
                  let children = kidsRef as? [AXUIElement] else { continue }
            for child in children {
                guard let pos = point(child), let size = sizeOf(child) else { continue }
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

    // MARK: - AX helpers

    private static func element(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        element(el, attr) as? String
    }

    private static func point(_ el: AXUIElement) -> CGPoint? {
        guard let ref = element(el, kAXPositionAttribute) else { return nil }
        let axValue = ref as! AXValue
        var p = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &p) else { return nil }
        return p
    }

    private static func sizeOf(_ el: AXUIElement) -> CGSize? {
        guard let ref = element(el, kAXSizeAttribute) else { return nil }
        let axValue = ref as! AXValue
        var s = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &s) else { return nil }
        return s
    }

    @discardableResult
    static func setPosition(_ el: AXUIElement, _ p: CGPoint) -> Bool {
        var point = p
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, value) == .success
    }
}
