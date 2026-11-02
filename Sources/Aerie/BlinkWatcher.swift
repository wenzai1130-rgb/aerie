import AppKit
import ApplicationServices

/// Watches icons that are tucked inside the drawer and pops the
/// drawer open when one of them "flaps its wings" — i.e. when its
/// accessibility label changes, which most menu bar apps do when a
/// new message, event or state arrives.
///
/// Implementation: AXObserver on kAXValueChangedNotification /
/// kAXTitleChangedNotification for every tucked icon element.
/// No Screen Recording permission needed.
final class BlinkWatcher {
    static var shared: BlinkWatcher?

    private var observers: [(observer: AXObserver, elements: [AXUIElement])] = []
    private var watchedKeys = Set<String>()
    private(set) var isRunning = false

    var onAttention: (() -> Void)?
    var onQuiet: (() -> Void)?

    /// Cooldown so a burst of events triggers a single reveal.
    private var lastEvent = Date.distantPast
    private var rehideWork: DispatchWorkItem?

    func start(watched: [MenuBarItem]) {
        stop()
        guard Permissions.hasAccessibility else { return }
        BlinkWatcher.shared = self

        var byPid: [pid_t: [AXUIElement]] = [:]
        for item in watched {
            let key = "\(item.pid)|\(item.position.x)|\(item.title)"
            guard watchedKeys.insert(key).inserted else { continue }
            byPid[item.pid, default: []].append(item.element)
        }

        for (pid, elements) in byPid {
            var observer: AXObserver?
            let result = AXObserverCreate(pid, { _, _, _, _ in
                BlinkWatcher.shared?.handleEvent()
            }, &observer)
            guard result == .success, let obs = observer else { continue }
            for el in elements {
                for note in [kAXValueChangedNotification, kAXTitleChangedNotification] {
                    AXObserverAddNotification(obs, el, note as CFString, nil)
                }
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
            observers.append((obs, elements))
        }
        isRunning = !observers.isEmpty
    }

    func stop() {
        for (obs, _) in observers {
            let src = AXObserverGetRunLoopSource(obs)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        observers.removeAll()
        watchedKeys.removeAll()
        isRunning = false
    }

    private func handleEvent() {
        let now = Date()
        guard now.timeIntervalSince(lastEvent) > 0.4 else { return }
        lastEvent = now
        onAttention?()

        rehideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onQuiet?()
        }
        rehideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
}
