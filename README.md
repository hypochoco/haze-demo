# Haze

Haze is intended to be a native macOS photo-editing and painting app, built with Swift + Metal. This repo is a **public demo**, shared to gather feedback.

> ⚠️ **Alpha software (v0.1.0).** Haze is under active development. It may crash, and file formats or behavior may change between builds. **Do not use it for important work, and keep backups of anything you care about.**

_Screenshots coming soon._
<!-- TODO (maintainers): drop a hero screenshot / short GIF here and under docs/. -->

## Features

- **Brush** - GPU accelerated brush engine 
  - Pressure, Size, Flow, Opacity
  - Shape scatter, Jitter
  - Presets
  - Round and textured (Chalk, Spatter, Sqaure) brushes
    - Shape scatter
    - Jitter
  - Eraser
  - Pressure sensitivity (tablet) support
- **Undo** - pixel-diff and action history for performant undo
- **Layers & groups** - Add, Delete, Duplicate, Drag-to-reorder, Opacity, Visibility, Inline Rename, Nested groups, Multi-select, Merge down
  - **Blend modes (per layer and group)** - Normal, Multiply, Screen (per layer and group)
- **Selections & transforms**
  - Lasso and polygon-lasso 
    - Add (⇧), Subtract (⌥), Intersect (⇧⌥)
  - Select all, Deselect, Invert
  - Move
  - Free transform (scale / rotate / flip)
- **Color** - HSV-square picker (8-bit sRGB) with hex, swatches, eyedropper
- **Canvas**
  - Canvas creation with size, backgroun, resolution, DPI
  - Resize (crop, extend, resampling)
  - Flip horizontal / vertical
- **Files**
  - Open and export to **PNG** and **JPEG**
  - Open and save in Photoshop **`.psd`**
    - Nested layer groups, blend modes, opacity
  - 16-bit and P3 converted to 8-bit sRGB on import
- **Desktop workflow**
  - Toggle-able and reorderable panels
  - Command palette (⌘⇧P)
  - Configurable keyboard shortcuts
  - Trackpad pan and zoom
  - Settings panel

For more in depth info on features, see the [**`docs/`**](docs/) folder.

## Requirements

- macOS 14 (Sonoma) or later
- **Apple silicon** Mac (M1 or later; Intel unsupported)

## Download & install

1. Download the latest `Haze.app` (zipped `.dmg`) from the
   [Releases](https://github.com/hypochoco/haze-demo/releases) page.
2. Open the `.dmg` and move `Haze.app` to your **Applications** folder.

### Opening the app the first time

Haze is **not signed with an Apple Developer ID nor notarized** (this is a free demo release), so macOS Gatekeeper will block it on first launch with the message
>  *"Haze can't be opened because Apple cannot check it for malicious software."* 

To allow it (only needed to be done once), there are two options.

> ⚠️ Per general security practice, only run the following steps for apps you trust. The Haze Demo makes no connection to the internet and does not/should not send your data anywhere (see [Privacy](#privacy)). The demo is open source - feel free to look or [build it yourself](#building-from-source). 

**Option 1 - System Settings:**
1. Try to open Haze once and dismiss the dialog
2. Open **System Settings → Privacy & Security**
3. Scroll to the Security section, find the "Haze was blocked" notice, and click **Open Anyway**

**Option 2 - Terminal:**

1. In a terminal, run the following to remove the quarantine flag

```sh
xattr -dr com.apple.quarantine /Applications/Haze.app
```

## Future

This is an early demo focused on getting the core digital painting features right. Familiar tools are in **progress and coming soon**. 

- **Layer masks**
- **16-bit & P3 color management**
- **Custom brush tips** - import PNG/JPEG stamps for brushes
- **Multi-canvas**
- **Selections** - feathering, marquee, magic wand
- **Adjustments** - curves, levels, hue/saturation, blur, liquify
- **Fill, gradient, clone, and heal**
- **More blend modes**

## Feedback

The goal of the demo is to gather feedback - any comments on what's done well, poorly, or which features to prioritize are greatly appreciated. 

- Provide feedback by opening an issue at <https://github.com/hypochoco/haze-demo/issues>
  - If reporting a bug, please include the following:
    - **macOS version**
    - what was expected vs what happened
    - **diagnostics** in the app, choose **Help ▸ Reveal
  Diagnostics in Finder** to open the folder Haze writes local logs to, and attach the
  most recent file to your issue. (Nothing is sent anywhere automatically - see
  [Privacy](#privacy).)

## Privacy

The Haze Demo runs entirely on your machine. It makes **no network connections** and collects **no telemetry or analytics**. Any diagnostic or crash information stays in a local folder on your machine unless you choose to share it in a bug report.

## Building from source

Requirements: a recent Xcode (macOS 14 SDK or newer).

```sh
# Build (Release), or just open Haze.xcodeproj and build the "Haze" scheme in Xcode.
xcodebuild -project Haze.xcodeproj -scheme Haze \
  -destination 'platform=macOS' -configuration Release build
```

The project has no external package dependencies - a standard Xcode toolchain is all that's required.

## License

Haze is released under the [MIT License](LICENSE).

---

*Photoshop is a trademark of Adobe Inc.; Procreate is a trademark of Savage Interactive
Pty Ltd. Haze is not affiliated with, endorsed by, or sponsored by either. "PSD" refers
only to the file format, for interoperability.*
