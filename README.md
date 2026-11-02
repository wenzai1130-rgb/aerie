# Aerie

**The aerie at the top of your screen.** 🐦

A menu bar manager for macOS built on a simple promise: **your menu bar is not Aerie's to rearrange.** Install it, and nothing changes. Tuck only the icons you don't need into the aerie — the rest (your messaging apps, reminders, anything you care about) stays exactly where it is, permanently visible.

An *aerie* is the nest of a bird of prey, built high on a cliff ledge. Your menu bar is that ledge; your icons are the birds perched on it. Aerie just decides who stays out in the open and who rests inside.

## Why another menu bar manager?

Because every existing one betrays you the same way:

| The usual experience | Aerie's answer |
|---|---|
| Take over and collapse *everything* on first launch | **Zero changes by default.** Only icons you explicitly tuck are hidden |
| A separator whose "hidden" side points the *wrong* way | One rule: **⌘-drag left of the wall = tucked**. That's it |
| Icons shoved off-screen and "forgotten", even after quitting | Quitting or restoring always **puts every icon back** |
| No story for messages | **Flap detection**: when a tucked icon's accessibility label changes (new message, new event…), Aerie pops the drawer open for 5 seconds, then quietly tucks it back |

## Requirements

- macOS 13 (Ventura) or later
- Accessibility permission (for flap detection & layout restore). Tucking itself needs no permissions at all.

## Build

No Xcode required — Command Line Tools + Swift Package Manager are enough:

```bash
./scripts/build.sh
# → build/Aerie.app
```

Or grab a build from [Releases](../../releases).

## Usage

1. Launch Aerie. A small **bird** appears in your menu bar.
2. Hold **⌘** and drag the icons you *don't* need to the **left of the invisible wall** (it sits just left of the bird).
3. **Click the bird** → the wall widens and tucked icons slide out of sight. Click again → they come back.
4. While tucked, if one of them gets a message, **the aerie opens by itself** for 5 seconds. The bird icon switches from 🐦 to a filled one while the drawer is closed.

Right-click the bird for the menu:

- **展开抽屉 / Tuck Icons** — toggle the drawer
- **登录时启动 / Launch at Login**
- **恢复菜单栏布局 / Restore Layout** — panic button: puts every icon back to where it was when Aerie launched
- **退出 / Quit** — always restores the layout first

## FAQ

**I tucked an icon and can't find it.**
Click the bird. Tucked icons live left of the wall. If the bird itself went missing, log out and back in — Aerie never pushes icons into positions apps remember as broken.

**Does Aerie move my icons?**
Almost never. Tucking works by widening Aerie's own invisible wall; your icons simply run out of room. Aerie only touches icon positions when you use *Restore Layout*, and then it puts them back to the snapshot taken at launch.

**Why does the drawer open by itself?**
Flap detection heard a tucked icon update its label — usually a new message or event. It closes again after 5 seconds.

## Roadmap

- [ ] Floating panel mode (notch-friendly)
- [ ] Per-app rules (auto-tuck on launch)
- [ ] Global hotkey
- [ ] Menu bar spacing tweaks

## License

MIT — see [LICENSE](LICENSE).
