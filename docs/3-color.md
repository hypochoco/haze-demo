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

## Gradient

The **Gradient** tool (`G`) fills a linear or radial colour ramp along a drag.

- **Draw:** select the Gradient tool (tool rail, **Tools ▸ Gradient**, or `G`), pick a **Type** (Linear / Radial) in the Gradient panel, then drag start → end on the canvas. Linear runs the ramp along the drag; Radial runs it outward from the start. A guide line tracks the drag while you draw.
- **Colour ramp:** the panel has a multi-stop ramp — click the bar or **+** to add stops, drag the handles to reposition, and set each stop's colour and opacity. **Reset** returns to the classic Foreground → Transparent ramp.
- **Reverse** mirrors the ramp.
- The fill is **clipped to the active selection** (whole layer if none), applied to the active layer, and lands as a single undoable step.
