# Selections & transform

Selections constrain painting and can be modified by the Move tool and Transforms.

## Making selections

- **Lasso** (`L`) - freehand
- **Polygon Lasso** (`⇧L`) - click to place points; the shape closes into a selection

Coverage is anti-aliased, and painting is clipped to the selection.

## Boolean modifiers

Hold a modifier as you start a new selection to combine it with the current one:

- **Shift** - add
- **Option** - subtract
- **Shift + Option** - intersect

## Whole-selection commands

- **Select All** (`⌘A`)
- **Deselect** (`⌘D`)
- **Invert Selection** (`⇧⌘I`)

## Move

**Move** (`V`) lifts the selected pixels into a floating piece you can drag, then commits on release.

## Free transform

**Free Transform** (`⌘T`) scales, rotates, translates, and flips the selected pixels:

- **Shift** / **Option** modify the drag (constrain / from-center)
- **Flip Horizontal / Vertical** are available while a transform is in progress

> Selection feathering and additional selection tools (marquee, magic wand, refine-edge) in progress.
