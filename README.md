<p align="center">
  <img src="https://github.com/solodevlog/BrightBar/releases/download/v1.0.0/AppIcon.png" width="128" alt="BrightBar Icon">
</p>

<h1 align="center">BrightBar</h1>
<p align="center"><strong>Control external monitor brightness with native macOS hotkeys</strong></p>

<p align="center">
  <a href="https://github.com/solodevlog/BrightBar/releases/latest"><img src="https://img.shields.io/github/v/release/solodevlog/BrightBar?style=flat-square&label=Download&color=blue" alt="Download"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey?style=flat-square" alt="macOS 13+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  <a href="https://buymeacoffee.com/solodevlog"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-donate-yellow?style=flat-square&logo=buy-me-a-coffee&logoColor=white" alt="Buy Me a Coffee"></a>
</p>

---

<p align="center">
  <img src="assets/demo.gif" width="600" alt="BrightBar Demo">
</p>

## Features

- **F1 / F2 hotkeys** — adjust brightness just like the built-in display
- **Interactive OSD** — native-looking overlay with drag-to-set slider
- **Menu bar control** — quick slider in the status bar popover
- **Multi-monitor** — select between external displays with resolution and refresh rate info
- **DDC/CI** — communicates directly with your monitor over I2C (Apple Silicon)
- **Lightweight** — pure Swift, no Electron, no dependencies

## Install

### Download DMG

1. Go to [**Releases**](https://github.com/solodevlog/BrightBar/releases/latest) and download `BrightBar.dmg`
2. Open the DMG and drag **BrightBar** to Applications
3. Launch BrightBar and grant **Accessibility** permission when prompted

> **Note:** If macOS says the app can't be verified, run:
> ```bash
> xattr -cr /Applications/BrightBar.app
> ```

<details>
<summary><strong>Build from source</strong></summary>

```bash
git clone https://github.com/solodevlog/BrightBar.git
cd BrightBar
bash Scripts/build.sh
open .build/BrightBar.app
```

Requires Xcode Command Line Tools and macOS 13+.

</details>

## Usage

| Action | How |
|--------|-----|
| Decrease brightness | Press **F1** |
| Increase brightness | Press **F2** |
| Drag to set brightness | Click and drag on the OSD bar |
| Open slider | Click the menu bar icon |
| Switch monitor | Right-click the menu bar icon |

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon (M1 / M2 / M3 / M4)
- External monitor with DDC/CI support (most monitors via HDMI/DisplayPort/USB-C)

## How It Works

BrightBar intercepts hardware brightness keys via `CGEventTap`, then sends DDC/CI commands over I2C using `IOAVService` private API. The VCP code `0x10` controls the backlight. A custom `NSPanel` renders the macOS-style OSD with interactive segments.

## Support

If BrightBar saves you time, consider supporting development:

<p>
  <a href="https://github.com/sponsors/solodevlog"><img src="https://img.shields.io/badge/GitHub%20Sponsors-Support-ea4aaa?style=for-the-badge&logo=github-sponsors&logoColor=white" alt="GitHub Sponsors"></a>
  <a href="https://buymeacoffee.com/solodevlog"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me a Coffee"></a>
  <a href="https://ko-fi.com/solodevlog"><img src="https://img.shields.io/badge/Ko--fi-Support-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
</p>

## License

[MIT](LICENSE) — free and open source.
