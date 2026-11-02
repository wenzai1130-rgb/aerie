import AppKit
import ApplicationServices

/// Detects the user ⌘-dragging another app's menu bar icon onto the
/// bird. We poll the window list: when a foreign status-item window's
/// center sits inside the bird's bounds for two consecutive polls,
/// we translate that window back into its AX element and hand it to
/// the app delegate to tuck away.
final class DropDetector {

    var onTuck: ((_ pid: pid_t, _ element: AXUIElement) -> Void)?

    private var timer: Timer?
    private var pendingPid: pid_t = 0
    private var pendingX: CGFloat = -1
    private var lastTuck = Date.distantPast

    private struct Win {
        let pid: pid_t
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        var centerX: CGFloat { x + w / 2 }
        var centerY: CGFloat { y + h / 2 }
    }

    func start() {
        stop()
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingPid = 0
    }

    private func poll() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return }

        var bird: Win?
        var candidates: [Win] = []

        for w in list {
            guard let layer = (w["kCGWindowLayer"] as? NSNumber)?.intValue, layer == 25 else { continue }
            guard let pidNum = w["kCGWindowOwnerPID"] as? NSNumber else { continue }
            let pid = pidNum.int32Value
            let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
            let x = CGFloat((b["X"] as? NSNumber)?.doubleValue ?? 0)
            let y = CGFloat((b["Y"] as? NSNumber)?.doubleValue ?? 0)
            let wd = CGFloat((b["Width"] as? NSNumber)?.doubleValue ?? 0)
            let ht = CGFloat((b["Height"] as? NSNumber)?.doubleValue ?? 0)
            let win = Win(pid: pid, x: x, y: y, w: wd, h: ht)

            if pid == getpid() {
                // Our bird: a mid-width status window (the thin wall is ~12pt).
                if wd > 18 && wd < 70 { bird = win }
            } else if wd > 6 && wd < 90 && ht > 10 && y < 60 {
                candidates.append(win)
            }
        }

        guard let bird = bird else { pendingPid = 0; return }

        // Tolerance: the drop zone is the bird widened by 8pt on each side.
        var hit: Win?
        for c in candidates {
            if c.centerX >= bird.x - 8 && c.centerX <= bird.x + bird.w + 8 &&
               c.centerY >= bird.y - 8 && c.centerY <= bird.y + bird.h + 8 {
                hit = c
                break
            }
        }

        guard let hit = hit else { pendingPid = 0; return }

        // Debounce: must still be there on the next poll (~300ms total).
        if pendingPid == hit.pid && abs(pendingX - hit.x) < 3 {
            guard Date().timeIntervalSince(lastTuck) > 1.2 else { return }
            lastTuck = Date()
            pendingPid = 0
            resolve(pid: hit.pid, at: CGPoint(x: hit.x, y: hit.y))
        } else {
            pendingPid = hit.pid
            pendingX = hit.x
        }
    }

    private func resolve(pid: pid_t, at position: CGPoint) {
        guard let el = MenuBarScanner.element(at: position, inApp: pid) else { return }
        onTuck?(pid, el)
    }
}
