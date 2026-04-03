# taigrteam — style guide

A single-file HTML design system reference for the `taigrteam` brand — a company in the energy/grid sector. Documents the visual language used across their products.

---

## Architecture

Single file (`style.html`) — all CSS and markup in one place, no build step, no framework dependencies. Only external dependency is Google Fonts (Orbitron + Roboto).

The nav bar background (`#05100E`) is the inverse of Phantom's bg/text pairing, signalling a dark theme is intended as a companion.

---

## Design System: "Phantom" theme

Currently one theme is defined, described as *light · orange-primary · baseline*.

| Token | Value | Role |
|---|---|---|
| `--bg` | `#F0F6F7` | Off-white background |
| `--text` | `#05100E` | Near-black text |
| `--accent` | `#EC6D26` | Orange — primary CTA |
| `--accent2` | `#0D8C80` | Teal — secondary / info |
| `--error` | `#C0392B` | Red |
| `--success` | `#2D9E72` | Green — success states |

The CSS custom properties are scoped per `#section-id`, meaning additional themes are additive — new section + new `--var` overrides + nav link.

---

## Notable design choices

- **Zero border-radius** — sharp corners throughout, consistent with an industrial/technical brand
- **Offset box-shadow** (`6px 6px 0`) — flat/brutalist aesthetic rather than diffuse drop shadows
- **Orbitron** for headings (geometric, techy), **Roboto** for body
- **`clamp()` on headings** — fluid typography that scales with viewport width
- **CSS custom properties per theme** — fully token-driven, easy to fork new variants

---

## Component inventory

| Category | Components |
|---|---|
| Typography | h1–h3, label, body, muted, accent, code |
| Buttons | primary, accent, outline, ghost × sm/md/lg + disabled states |
| Inputs | text, email, select, textarea, disabled + field/hint/error wrappers |
| Selection | checkbox, radio, toggle |
| Cards | standard, shadow, accent, inverted, stat card |
| Feedback | badges (6 variants), progress bars (2), alerts (info/success/warning/error) |
| Layout | dividers (3 variants + labelled), data table with row hover |

---

## TODO

> Reviewed from the perspective of a UX designer with a focus on neo-brutalist design systems.

### Themes

- [ ] **Dark "Specter" theme** — invert Phantom's palette: `#05100E` bg, `#F0F6F7` text, same orange/teal accents. The nav is already dark; the full dark theme is the obvious companion and the one most likely to be default in the actual product
- [ ] **High-contrast accessibility variant** — pure black/white base with full-saturation accent, targeting WCAG AAA. Neo-brutalism and accessibility are natural allies here — the hard edges and solid fills already do most of the work
- [ ] **Theme switcher** — a JS-powered `data-theme` toggle on `<body>` with smooth transition. The swatch strip in each section header could double as the toggle

### Typography

- [ ] **Type scale documentation** — publish the explicit scale (`0.65rem` → `4.5rem`) as a reference table so developers aren't guessing intermediate steps
- [ ] **Display / hero size** — a step above `tt-h1` for landing page moments: `clamp(3.5rem, 10vw, 7rem)`, Orbitron 900, possibly with a 2px text-stroke in the accent colour for a raw, industrial feel
- [ ] **Mono code blocks** — `tt-code` is inline only. Add a block-level `tt-code-block` with line numbers, horizontal scroll, and the same sharp border + offset shadow treatment. Courier New should go; bring in a proper mono webfont (JetBrains Mono or IBM Plex Mono suit the brand)
- [ ] **Truncation utility** — single-line ellipsis and multi-line `-webkit-line-clamp` helper classes for table cells and card bodies

### Buttons

- [ ] **Icon button** — square, 40×40, border-only variant for toolbar actions. The 3px border and sharp corners give it instant visual weight without a label
- [ ] **Loading state** — a CSS-only animated border (rotating dashed outline or a fill sweep) in place of a spinner. Should feel mechanical, not bouncy
- [ ] **Destructive variant** — `tt-btn-danger`: `--error` background, `--accent-fg` text, same offset shadow in error colour on hover. Distinct enough that you can't accidentally click it
- [ ] **Button group** — adjacent buttons sharing a single outer border (collapsed internal borders). Useful for segmented controls and filter bars
- [ ] **Anchor `<a>` parity** — confirm all button classes render correctly on `<a>` tags, not just `<button>`

### Inputs & Forms

- [ ] **Input prefix/suffix slots** — icon or unit label (e.g. `MW`, `kWh`, `£`) inside the input border, separated by an internal divider. Critical for the energy domain
- [ ] **Search input** — full-width, with a stylised `▸` submit arrow on the right, replacing the default browser `[x]` clear behaviour
- [ ] **Date/range input** — custom-styled, since the native date picker is browser-inconsistent and clashes badly with sharp-corner aesthetics
- [ ] **Inline validation** — real-time field feedback with border colour transition (neutral → error → success) and a small icon in the suffix slot. The focus `box-shadow: 4px 4px 0` already does the heavy lifting; success state just needs a teal equivalent
- [ ] **Form layout grid** — a two-column form grid (`tt-form-grid`) with consistent label alignment. Right now fields are stacked; a grid layout is needed for denser data-entry screens

### Cards & Data Display

- [ ] **Horizontal stat card** — stat value left, label + sparkline right, full-width. More useful for dashboard rows than the current square stat card
- [ ] **KPI trend indicator** — `▲ +12%` / `▼ −3%` in accent/error colour inside stat cards. A core pattern for any energy dashboard
- [ ] **Expandable / accordion card** — click header to reveal body. The header bottom-border already doubles as a click target visually; add a `▾` toggle that rotates on open
- [ ] **Skeleton / loading placeholder** — animated diagonal-stripe fill using a CSS gradient, consistent with the angular brand language. No rounded shimmer — this should look like a technical loading state

### Badges & Status

- [ ] **Dot indicator** — 8px filled circle prefix for inline status (`● online`, `● degraded`, `● offline`). More compact than a full badge in dense tables
- [ ] **Pill vs. sharp toggle** — currently all badges are sharp. Consider documenting when (if ever) a `border-radius: 99px` pill is acceptable vs. the default hard rectangle
- [ ] **Animated "live" badge** — pulsing border-glow using `outline` animation, no border-radius, for real-time data indicators

### Alerts & Notifications

- [ ] **Dismissible alert** — `✕` close button, right-aligned, same weight as the alert icon
- [ ] **Toast / notification stack** — fixed bottom-right stack, max 3 visible, each with the same 4px left-border treatment. Auto-dismiss with a CSS progress bar draining across the bottom edge
- [ ] **Inline banner** — full-width, sits directly below the nav, for system-level notices (maintenance windows, outage alerts). Left-border only, no padding top/bottom — tight and urgent

### Navigation & Layout

- [ ] **Sidebar nav** — vertical nav with section groupings, active-state left border in accent colour (4px, full height of the item), and collapsible sub-items. The energy product probably needs this more than a top nav
- [ ] **Breadcrumb** — `NW-GRID-01  /  substations  /  detail` in `tt-mono`, separated by `  ·  ` in muted colour. Tight, technical, no chevrons
- [ ] **Pagination** — numbered pages as bordered squares, active page filled in accent. Previous/next as ghost buttons
- [ ] **Tabs** — horizontal tab bar where the active tab has a 3px bottom border in accent colour and full background fill. Inactive tabs are ghost. No rounded corners anywhere

### Data & Tables

- [ ] **Sortable column headers** — `▲▼` toggles, active direction highlighted in accent colour
- [ ] **Fixed header on scroll** — `position: sticky; top: 0` on `<thead>` for long tables, with a bottom border that matches the section nav's 3px orange line
- [ ] **Row selection** — checkbox in first column, selected row gets a 2px left border in accent + subtle `--row-hover` fill. Bulk-action bar appears above table when rows are selected
- [ ] **Empty state** — full-width placeholder row with a centre-aligned message and a CTA button. Should maintain the table's column borders so the grid structure is visible even when empty
- [ ] **Inline editable cells** — click to edit, confirm with `↵`, cancel with `Esc`. Input appears inline with the same `tt-input` styling, matching cell height exactly

### Motion & Interaction

- [ ] **Interaction audit** — current transitions are `0.15s ease` throughout. Nail down a motion scale: `instant (0ms)` for state toggles, `fast (100ms)` for micro-interactions, `normal (200ms)` for panels, `slow (400ms)` for page-level. Neo-brutalism favours snappy, mechanical motion — no easing on linear state changes
- [ ] **Focus-visible ring** — custom `:focus-visible` outline: `3px solid var(--accent); outline-offset: 2px`. Remove the default browser ring. Keyboard navigation must be at least as clear as hover states
- [ ] **Reduced motion** — wrap all CSS transitions in `@media (prefers-reduced-motion: no-preference)`. The pulsing and sweep animations especially

### Spacing & Layout Utilities

- [ ] **Spacing scale** — define and document the spacing tokens: `4 / 8 / 12 / 16 / 24 / 32 / 48 / 64 / 96px`. The `gap-*` utility classes exist but aren't documented and only cover column direction
- [ ] **Layout primitives** — `tt-stack` (vertical flex), `tt-cluster` (wrapping flex), `tt-sidebar` (two-column with fixed-width sidebar). These three cover most layout patterns without reaching for a full grid framework
- [ ] **Max-width container** — `tt-container`: `max-width: 1280px; margin-inline: auto; padding-inline: 24px`. The style guide sections currently stretch full-width; the production UI will need a centred container

### Accessibility

- [ ] **ARIA audit** — add `role`, `aria-label`, and `aria-checked` attributes to all custom controls (toggle, checkbox, radio). The CSS-only implementations look correct visually but are invisible to screen readers
- [x] **Colour contrast pass** — `--text-muted` raised from `rgba(5,16,14,0.45)` to `rgba(5,16,14,0.65)` to clear WCAG AA 4.5:1 threshold
- [x] **`<label>` association** — all field labels now have explicit `for`/`id` pairing; error field also gets `aria-describedby` + `aria-invalid="true"`
