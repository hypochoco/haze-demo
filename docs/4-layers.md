# Layers & groups

Haze has a full layer tree with nested groups in the Layers panel.

## Layers

- **Add**, **Duplicate**, and **Delete** layers
- **Opacity** and **Visibility** per layer, with a live opacity preview
- **Reorder** by dragging
- **Rename** inline by double-clicking a row
- **Multi-select** with ⌘-click (toggle) and ⇧-click (range)

## Groups

- **Group Selection** (`⌘G`) and **Ungroup** (`⇧⌘G`)
- Groups nest and have their own opacity, visibility, and blend mode; a group composites its children in isolation, then draws into its parent

## Blend modes

Per layer and per group: **Normal**, **Multiply**, **Screen**. Normal uses the hardware over-blend; Multiply and Screen composite against the backdrop.

> More blend modes are in progress.

## Merging

- **Merge Down** (`⌘E`) merges the selected layer into the one directly below it, baking blend + opacity.

> Merge Visible, Flatten Group, and Flatten Image are in progress.

## Masks

> Non-destructive layer masks are in progress. 

Opening a PSD that contains layer masks skips them on import and shows a notice.
