---
name: Xray for Omarchy
description: A bar widget and panel that inherit the Omarchy shell theme completely.
colors:
  foreground: "#cacccc"
  background: "#101315"
  accent: "#cacccc"
  urgent: "#a55555"
typography:
  display:
    fontFamily: "monospace (Omarchy system font, e.g. JetBrainsMono Nerd Font)"
    fontSize: "24px"
  body:
    fontFamily: "monospace (Omarchy system font)"
    fontSize: "12px"
  body-small:
    fontFamily: "monospace (Omarchy system font)"
    fontSize: "11px"
  caption:
    fontFamily: "monospace (Omarchy system font)"
    fontSize: "10px"
rounded:
  corner: "0px"
spacing:
  xs: "4px"
  sm: "6px"
  md: "8px"
  lg: "12px"
  row-padding-x: "12px"
  control-padding-x: "10px"
components:
  text-action-button:
    textColor: "{colors.foreground}"
    typography: "{typography.caption}"
    rounded: "{rounded.corner}"
  row-field:
    textColor: "{colors.foreground}"
    typography: "{typography.caption}"
    rounded: "{rounded.corner}"
  node-row:
    textColor: "{colors.foreground}"
    typography: "{typography.body}"
    rounded: "{rounded.corner}"
---

# Design System: Xray for Omarchy

## Overview

**Creative North Star: "The Native Guest"**

The widget has no visual identity of its own. It lives inside the Omarchy shell and takes everything from it: colors from the active theme, the monospace system font, spacing from `Style.space()`, corner radius from Hyprland's `decoration:rounding`. A user who changes the Omarchy theme changes this panel with it, with no exceptions.

Brand shows only in behavior and precise detail: the shield glyph in the bar, the keyboard legend, the fixed latency column. The panel is text-first. Controls are words, not boxes, and fill appears only as a response to hover, focus or selection.

The hex values in the frontmatter are the default Omarchy theme (Vantablack) and are samples only. The code reads them from `Color.*` and the bar at runtime and never hard-codes them.

**Key Characteristics:**
- Every color, font and size comes from `qs.Commons` (`Color`, `Style`).
- Text-first controls, flat surfaces, no shadows.
- One status signal is loud: protection state (shield and switch).
- Keyboard cursor and mouse hover share the same fill language.

## Colors

The palette is the Omarchy theme, used by role.

### Primary
- **Theme Foreground** (`foreground`): all text, icons and the shield. It comes from the bar when present, else `Color.foreground`.

### Neutral
- **Theme Background** (`background`): panel surface, owned by the shell's `Panel`, never painted by the widget.
- **Dim Grey**: secondary text and hints. Computed as `Qt.darker(foreground, 1.4)`, not a separate token.
- **State Fills**: hover, selected and focus fills come from `Style.hoverFillFor`, `Style.selectedFillFor` and `Style.focusFillFor`. They are the foreground or accent at a low alpha.

### Tertiary
- **Theme Urgent** (`urgent`): errors, the armed Remove button and the kill-switch state. When the theme's urgent is nearly grey (HSL saturation < 0.2), the panel uses foreground instead so errors stay readable.

### Named Rules
**The Borrowed Palette Rule.** The widget never declares a color literal. A new color is a role taken from `Color`/`Style`, or it does not ship.

**Open decision: status colors.** The user wants status colors for connection states and latency (for example good, slow, failed). They must still come from the theme (for example the theme's terminal green and yellow), not hard-coded hex. Not implemented yet.

## Typography

**Body Font:** Omarchy system monospace (`Style.font.family`, resolved by fontconfig, for example JetBrainsMono Nerd Font). The bar's `fontFamily` wins when present.

**Character:** One monospace family for everything. Hierarchy comes from size and dim color, never from a second typeface.

### Hierarchy
- **Display** (24px, `Style.font.display`): the power-switch shield icon only.
- **Body** (12px, `Style.font.body`): node names, status line, empty state.
- **Body Small** (11px, `Style.font.bodySmall`): setting labels, subscription details, key legend.
- **Caption** (10px, `Style.font.caption`): chips, action buttons, latency values, field text.

### Named Rules
**The Token Size Rule.** Font sizes come only from `Style.font.*`. A user's font token overrides must reach every text in the panel.

**The Fixed Column Rule.** Latency sits in a right-aligned cell sized by the widest label (`latencyCellWidth`), so results line up and never move the name.

## Layout

A single column inside the shell `Panel`: about 400 units wide, up to 620 units tall (`fittedContentWidth/Height`).

- **Pinned top:** power switch, status line, key legend. It does not scroll.
- **Scrolling list:** settings rows (mode, route, regions, adblock), then nodes grouped per subscription, then the subscriptions footer and the import field.
- **Rhythm:** `Style.space()` steps of 1, 3, 4, 6, 8 and 12. Rows use 4 between items, 12 between sections; groups get 6 extra top padding.
- **Text inset:** row text aligns to `8 + glyph width + 8`, so icons and text form two clean columns.

## Elevation & Depth

Flat. The widget draws no shadows and no borders. Depth comes only from state fills: hover, selected and focus each have their own low-alpha fill from `Style`. Tooltips use the shell's `PanelToolTip`.

**The Flat Until Touched Rule.** A surface has no fill at rest. Fill appears only for hover, keyboard cursor, focus or selection.

## Shapes

Corners follow Hyprland's `decoration:rounding` through `Style.cornerRadius` (0 on the default theme). The widget never sets its own radius. Hit areas of thin strips extend 6 units above and below the visible text.

## Components

### Text Action Buttons
Quiet word buttons ("Update", "Remove", chips such as TUN, Proxy, ALL, RU DIRECT).
- **Shape:** `Style.cornerRadius`.
- **Rest:** foreground text, caption size, no fill.
- **Hover / Cursor:** hover fill. **Selected:** selected fill.
- **Destructive:** Remove arms on the first click, the text turns urgent, the second click confirms.

### Inputs / Fields (RowField)
- **Style:** icon glyph plus text, no stroke, caption size.
- **Focus:** focus fill. **Hover:** hover fill.
- Secrets typed here travel by environment variable, never argv (see PRODUCT.md).

### Node Row
- Icon, name, fixed latency cell. "Auto" shows its member count instead of latency.
- **Connected:** marked as current. **Fastest:** noted in the tooltip.
- Left click connects; right click tests latency.

### Power Switch
- The shield glyph at display size plus a `ToggleSwitch`. The state shows as filled (TUN), half-filled (proxy) or outline (off).
- While connecting, the shield pulses opacity between 1.0 and 0.45 (700 ms, InOutSine).

### Bar Icon (XrayIcon)
- The shield only, in bar foreground. Click opens the panel, right-click toggles, middle-click refreshes.

## Do's and Don'ts

### Do:
- **Do** read every color from `Color`, the bar, or `Style.*FillFor`.
- **Do** take every size from `Style.font.*` and `Style.space()`.
- **Do** give the keyboard cursor the same fill as mouse hover.
- **Do** keep protection state the loudest signal in the panel.

### Don't:
- **Don't** declare hex colors, custom fonts or a custom radius in QML.
- **Don't** add shadows, borders or filled buttons at rest.
- **Don't** add status colors as hard-coded hex. Take them from the theme.
