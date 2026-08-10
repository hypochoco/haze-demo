# Color

Haze works in **8-bit sRGB**. A single, shared **foreground color** is used by the brush, the color control, and the eyedropper.

## The Color panel

- **HSV picker** - a saturation/value square plus hue and alpha sliders
- **Hex** input and a swatch (shown over a checkerboard so alpha is visible)

## Eyedropper

The **Eyedropper** (`I`) samples the *composited* color under the cursor (not just the active layer) into the foreground color. Picked colors are opaque.

## Color fidelity & management

This build is 8-bit sRGB end to end. 

> Higher color depth (16-bit) and a wider-gamut Display P3 working space are in progress.

Documents in 16-bit or P3 will **open** - Haze converts to 8-bit sRGB on import and shows a notice describing the
conversion. See [Files](6-files.md).
