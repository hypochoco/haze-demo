# Files & formats

Haze's working document format is **Photoshop PSD**. It can also open and export flat raster images (PNG / JPEG).

## Open

**File ▸ Open** (`⌘O`) accepts:

- **PSD** - layers and **nested groups** are rebuilt, with blend modes and opacity preserved
- **PNG / JPEG** - imported as a single layer

### What happens to non-8-bit-sRGB documents

This demo works in 8-bit sRGB, so on import Haze coerces other formats and notifies via notice:

- **16-bit** documents are converted to 8-bit
- **Display P3** documents are converted to sRGB
- **Layer masks** in a PSD are skipped, with a notice reporting how many were dropped

## Save

- **Save** (`⌘S`) writes back to the associated `.psd` (quick-save), or prompts if the document has no file yet
- **Save As…** (`⇧⌘S`) always prompts for a destination
- A flat raster opened as PNG/JPEG does **not** associate for quick-save - `⌘S` will Save-As a `.psd` so layers aren't lost.

## Export

**File ▸ Export As…** writes a flat copy in **PNG** or **JPEG** via a format popup. JPEG quality is configurable in Settings.
