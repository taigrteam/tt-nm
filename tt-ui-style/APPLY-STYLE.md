# Prompt: Apply taigrteam design system and accessibility fixes

Use this prompt verbatim when asking Claude to audit and update another project to match the taigrteam style guide.

---

## PROMPT START

You are applying the taigrteam design system to this project. Work through every section below in order. Read each relevant file before editing it. Make all changes — do not stop to ask for confirmation on individual items unless something is genuinely ambiguous.

---

### 1. Design tokens

Find where CSS custom properties or design tokens are defined (could be a `:root {}` block, a CSS file, a Tailwind config, a JS theme object, or inline `style` attributes). Replace or reconcile them with the following canonical values:

```
--bg:         #F0F6F7   (off-white background)
--text:       #05100E   (near-black text)
--text-muted: rgba(5,16,14,0.65)   ← must be 0.65 or higher, NOT 0.45 or below
--border-col: #05100E
--accent:     #EC6D26   (orange — primary CTA, hover states, focus rings)
--accent-fg:  #F0F6F7   (text on orange backgrounds)
--accent2:    #0D8C80   (teal — secondary / info)
--shadow-col: #EC6D26
--input-bg:   #F0F6F7
--card-bg:    #F0F6F7
--code-bg:    #E4EDEF
--error:      #C0392B
--success:    #2D9E72
--row-hover:  rgba(236,109,38,0.06)
```

**Critical:** `--text-muted` at opacity 0.45 fails WCAG AA contrast (4.5:1) against `--bg`. It must be 0.65 or expressed as a solid hex equivalent. If the project uses a different variable name for muted/secondary text, apply the same rule: the rendered colour must achieve at least 4.5:1 against its background.

If the project uses Tailwind, map these to the `theme.colors` or `theme.extend.colors` block in `tailwind.config`. If it uses a JS/TS theme object, update the equivalent keys.

---

### 2. Typography

Ensure these two Google Fonts are loaded. Add to `<head>` or the global CSS `@import` if missing:

```html
<link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@700;900&family=Roboto:wght@400;700&display=swap" rel="stylesheet"/>
```

Apply the following font rules:
- **Headings (h1–h3, display text):** `font-family: 'Orbitron', sans-serif`
- **All other text (body, labels, buttons, inputs):** `font-family: 'Roboto', sans-serif`
- **Code / monospaced:** `font-family: 'Courier New', monospace` (or JetBrains Mono if already present)

Heading sizes must use `clamp()` for fluid scaling — no fixed `px` or `rem` sizes on headings:
- h1: `clamp(1.6rem, 4vw, 2.8rem)`
- h2: `clamp(1.1rem, 2.5vw, 1.6rem)`
- h3: `0.95rem` (fixed is acceptable at this size)

---

### 3. Borders, corners, and shadows

**Every** interactive and container element must have:
- `border-radius: 0` — no rounded corners anywhere, including buttons, inputs, cards, badges, checkboxes, toggles, modals, dropdowns
- Borders use `var(--border-col)` or `var(--accent)` — no grey system colours
- Elevated elements use offset box-shadow: `box-shadow: 6px 6px 0 var(--shadow-col)` — not `blur` or `spread` shadows
- Button borders are `3px solid` for default/large, `2px solid` for small variants

Search for and remove: `border-radius`, `rounded`, `shadow-sm`, `shadow-md`, `shadow-lg`, `drop-shadow` — replace with the offset shadow pattern above where elevation is needed.

---

### 4. Buttons

Ensure the following button variants exist and follow these rules exactly:

| Variant | Background | Text | Border |
|---|---|---|---|
| primary | `var(--text)` | `var(--bg)` | `3px solid var(--border-col)` |
| accent | `var(--accent)` | `var(--accent-fg)` | `3px solid var(--accent)` |
| outline | `transparent` | `var(--text)` | `3px solid var(--border-col)` |
| ghost | `transparent` | `var(--text)` | `3px solid transparent` |

Hover rules:
- **primary / outline / ghost:** `opacity: 0.85` — nothing else
- **accent:** `opacity: 1; box-shadow: 4px 4px 0 var(--text)` — the offset shadow appears on hover only

Disabled state: `opacity: 0.4; cursor: not-allowed; pointer-events: none` — no other styling change.

Size variants: `sm` uses `padding: 7px 14px; font-size: 0.78rem; border-width: 2px`. `lg` uses `padding: 16px 36px; font-size: 1rem`.

All buttons: `font-weight: 700; letter-spacing: 0.05em; transition: opacity 0.15s ease, box-shadow 0.15s ease`.

---

### 5. Inputs and selects

All inputs, selects, and textareas must have:
- `border-radius: 0; -webkit-appearance: none; appearance: none`
- `border: 2px solid var(--border-col)`
- `background: var(--input-bg)`
- Focus state: `box-shadow: 4px 4px 0 var(--accent); border-color: var(--accent); outline: none`
- Disabled state: `opacity: 0.4; cursor: not-allowed`
- Placeholder: `color: var(--text-muted)`

Custom select: wrap in a relative container. Add `::after { content: '▾'; position: absolute; right: 12px; top: 50%; transform: translateY(-50%); pointer-events: none; }` on the wrapper.

---

### 6. Accessibility — contrast (CRITICAL)

Search the entire codebase for these patterns and fix each one:

**Pattern to find:** any muted, secondary, placeholder, helper, or caption text colour with an opacity below 0.65 on a light background, or any grey text that may fail 4.5:1 contrast.

**How to check:** if the colour is expressed as `rgba(r,g,b,a)` with `a < 0.65` against a near-white background (`#F0F6F7`, `#fff`, `#f8f8f8`, etc.), it likely fails. Fix by raising `a` to `0.65` minimum, or replace with a solid hex that passes 4.5:1.

**Common failing patterns to search for:**
```
rgba(*,*,*,0.4
rgba(*,*,*,0.45
rgba(*,*,*,0.5
color: #999
color: #aaa
color: #bbb
color: gray
color: grey
opacity: 0.4   (on text elements)
opacity: 0.45  (on text elements)
opacity: 0.5   (on text elements)
```

Fix each instance: raise the opacity to at least 0.65, or switch to a solid colour. Verify against the specific background it appears on.

---

### 7. Accessibility — toggle inputs (CRITICAL)

Search for any toggle/switch component that hides its underlying `<input>` with `display: none`. This removes the input from the accessibility tree entirely, breaking keyboard navigation and screen reader support.

**Pattern to find:**
```css
.toggle input { display: none; }
.switch input { display: none; }
input[type="checkbox"].visually-hidden-wrong { display: none; }
```
Or any rule that applies `display: none` to an `<input>` that is the functional control for a visible toggle/switch UI.

**Fix — replace with the visually-hidden pattern:**
```css
.tt-toggle-wrap input {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0,0,0,0);
  white-space: nowrap;
  border: 0;
}
```

This keeps the input in the accessibility tree and focusable by keyboard, while remaining visually invisible. The CSS sibling selectors (`input:checked + .track`) continue to work unchanged.

Also ensure the `<label>` wrapping the toggle contains meaningful visible text so screen readers can announce what the toggle controls.

---

### 8. Accessibility — label associations (CRITICAL)

Search for every `<label>` element in the project. Every label that describes an input, select, or textarea must be programmatically associated with it. There are two acceptable patterns:

**Pattern A — explicit `for`/`id` (preferred):**
```html
<label for="field-email">Email address</label>
<input id="field-email" type="email" .../>
```

**Pattern B — wrapping (only if `for`/`id` cannot be used):**
```html
<label>
  Email address
  <input type="email" .../>
</label>
```

**What to search for and fix:**
```html
<!-- BAD — label has no for, input has no id -->
<label class="field-label">Email address</label>
<input type="email" .../>

<!-- BAD — for doesn't match any id -->
<label for="email">Email</label>
<input type="text" .../>   <!-- no id="email" -->
```

Go through every form field in the project. Add a unique `id` to each input/select/textarea, and a matching `for` attribute to its label.

---

### 9. Accessibility — error fields

Any field that shows a validation error message must have:
- `aria-invalid="true"` on the `<input>`
- `aria-describedby="[error-message-id]"` on the `<input>`
- A matching `id` on the error message element

```html
<!-- CORRECT -->
<input
  id="field-email"
  type="email"
  aria-invalid="true"
  aria-describedby="field-email-error"
  style="border-color: var(--error);"
/>
<span id="field-email-error" class="field-error">Invalid email address</span>
```

Search for elements with class names containing `error`, `invalid`, `validation` that are siblings of inputs, and apply this pattern.

---

### 10. Focus-visible ring

Remove any `outline: none` or `outline: 0` rules that apply globally or to interactive elements without a replacement. Add a custom `:focus-visible` ring:

```css
:focus-visible {
  outline: 3px solid var(--accent);
  outline-offset: 2px;
}
```

This applies only when navigating by keyboard (not on mouse click), matching the accent colour. Do not suppress focus indicators without replacing them.

---

### 11. Verify

After making all changes, check:
- [ ] No `border-radius` values remain on interactive or container elements
- [ ] No `display: none` on toggle/switch inputs
- [ ] Every `<label>` has a `for` attribute matched to an input `id`
- [ ] Every error message has `id` + the input has `aria-invalid` + `aria-describedby`
- [ ] `--text-muted` (or equivalent) opacity is ≥ 0.65
- [ ] Focus styles are visible and use `var(--accent)` colour
- [ ] Orbitron is used on all headings, Roboto on all body/UI text

## PROMPT END
