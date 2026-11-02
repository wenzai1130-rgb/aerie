# Aerie 🐦 *(archived)*

> **The aerie at the top of your screen** — a macOS menu bar manager that
> never touches what you keep visible.

**Status: archived.** Aerie worked as designed on macOS 13–15, but macOS 26
(Tahoe) redesigned the menu bar in a way that removes every mechanism
third-party hiders relied on. This repository is kept as a field report of
what we measured, so the next person doesn't have to spend a day
re-discovering it. On macOS 26+, use the built-in
**System Settings → Menu Bar → "Allow in the Menu Bar"** per-app toggles —
that is now the only reliable way to hide menu bar icons, and it's official.

---

## What Aerie tried, and what macOS 26 actually allows

We verified each mechanism empirically on macOS 26.5 (probe app + screen
captures), not by reading blog posts:

| Mechanism | Result on macOS 26.5 |
|---|---|
| Move/resize another app's status item via Accessibility (`AXUIElementSetAttributeValue` on position/size) | ❌ Rejected for **every** item with `kAXErrorCannotComplete` (-25200); `AXUIElementIsAttributeSettable` reports *not settable* for all |
| Widen your own `NSStatusItem` to push neighbours off-screen (the Hidden Bar / Ice / Dozer trick) | ❌ The wide item simply extends leftward and clips *itself*; neighbours don't move (verified by before/after screen captures) |
| Write `NSStatusItem Visible <key>` into `com.apple.controlcenter` defaults | ❌ No effect observed immediately, even after restarting ControlCenter |
| Read the menu bar via `AXExtrasMenuBar` | ✅ Still works (slow; set `AXUIElementSetMessagingTimeout`) |
| System-wide AX hit test on menu bar coordinates | ✅ Works |
| AX notifications (`AXObserver` + value/title change) for "message arrived" detection | ✅ Works |

Other quirks we hit, in case you are debugging the same things:

- On macOS 26 **all status-item windows are owned by the ControlCenter
  process**, not by the app that created them — window-list-based detection
  by pid does not work.
- AX-reported positions of menu bar items can be **stale/wrong** (an icon
  visibly at x≈1250 reported at x=-48). Never trust AX geometry for hit
  testing; use `AXUIElementCopyElementAtPosition` instead.
- Ad-hoc signed helper apps can lose their Accessibility trust after each
  rebuild; a stable signing identity avoids re-authorising constantly.
- macOS 26's System Settings gained per-app **"Allow in the Menu Bar"**
  toggles for third-party icons — the platform's answer to this whole
  category of tools.

## The v0.1–v0.2 design (still instructive)

- **Whitelist philosophy**: install changes nothing; only icons you
  explicitly tuck are affected.
- **Explicit restore**: quitting always returned every icon; no stranded
  off-screen items, ever.
- **BlinkWatcher**: AX observers on tucked icons revealed the drawer for 5 s
  when an icon's label changed (i.e. a message arrived) — the one feature
  that still works on macOS 26 and that no shipping tool does well.

## License

MIT
