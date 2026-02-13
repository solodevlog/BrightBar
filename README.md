# BrightBar

**Control your external monitor's brightness with native macOS hotkeys.**

BrightBar is a lightweight menu bar utility for macOS that lets you adjust external monitor brightness using the built-in brightness keys (F1/F2) — just like a built-in display. It communicates directly with your monitor over DDC/CI, changing real hardware brightness (not software gamma).

## Features

- **Hardware brightness keys** — F1/F2 control your external monitor, with native macOS OSD
- **Menu bar slider** — Click the sun icon for precise brightness control
- **Multi-monitor support** — Select between multiple external monitors
- **DDC/CI protocol** — Real hardware brightness via I2C, not software overlay
- **Zero config** — Auto-detects DDC-capable displays on launch
- **Native & lightweight** — Pure Swift, no Electron, minimal resource usage

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (M1 / M2 / M3 / M4)
- External monitor with DDC/CI support (most modern monitors)
- DisplayPort, HDMI, USB-C, or Thunderbolt connection

## Install

### Download

1. Download the latest `BrightBar.dmg` from [Releases](../../releases)
2. Open the DMG and drag **BrightBar** to your Applications folder
3. **Before first launch**, remove the quarantine flag (the app is not notarized with Apple):
   ```bash
   xattr -cr /Applications/BrightBar.app
   ```
4. Launch BrightBar from Applications

> **Why is this needed?** macOS Gatekeeper blocks apps that aren't signed with a paid Apple Developer certificate. BrightBar is open-source and ad-hoc signed. The command above tells macOS you trust this app. Alternatively, right-click the app → **Open** → **Open** in the dialog.

### Build from source

```bash
git clone https://github.com/solodevlog/BrightBar.git
cd BrightBar
bash Scripts/build.sh
```

The `.app` bundle and `.dmg` installer are created in `.build/`.

## Setup

On first launch, BrightBar will request **Accessibility** permission to intercept brightness keys:

1. Open **System Settings > Privacy & Security > Accessibility**
2. Toggle on **BrightBar**
3. You may need to restart the app after granting permission

> Without Accessibility permission, the menu bar slider still works — only hardware key interception requires it.

## Usage

| Action | Description |
|--------|-------------|
| **F1 / F2** | Decrease / increase brightness (6.25% steps, 16 segments) |
| **Click menu bar icon** | Open brightness slider popover |
| **Right-click menu bar icon** | Switch monitors, view display info, quit |

## How it works

BrightBar uses Apple Silicon's private `IOAVService` I2C interface to send DDC/CI VCP commands directly to your monitor:

1. **Discovery** — Enumerates `DCPAVServiceProxy` IOKit services and matches them to connected external displays via EDID
2. **Key interception** — A `CGEventTap` intercepts system-defined media key events before macOS handles them
3. **DDC/CI writes** — VCP Set (opcode 0x03) commands are sent to VCP code 0x10 (Luminance) with retry logic
4. **OSD** — A custom `NSWindow` displays a system-style brightness indicator

## Troubleshooting

**"Cannot verify that this app is free from malware"**
This is expected — the app is ad-hoc signed, not notarized with Apple. Run:
```bash
xattr -cr /Applications/BrightBar.app
```
Or: right-click BrightBar.app → Open → Open.

**"No DDC display" in popover**
Your monitor may not support DDC/CI, or the connection doesn't pass DDC signals. Try:
- A different cable (DisplayPort/USB-C tend to work best)
- Enabling "DDC/CI" in your monitor's OSD settings
- Checking that the monitor is detected in System Settings > Displays

**Brightness keys don't work**
- Grant Accessibility permission in System Settings > Privacy & Security > Accessibility
- Restart BrightBar after granting permission

**App doesn't appear in menu bar**
- BrightBar runs as a menu bar app (no Dock icon). Look for the sun icon in the menu bar.

## Supported monitors

Any monitor with DDC/CI support should work. Tested with:
- ASUS XG27ACS
- Most Dell UltraSharp displays
- LG UltraFine series
- BenQ PD / EW series

> If your monitor works (or doesn't), please open an issue to help expand this list.

## License

[MIT](LICENSE)
