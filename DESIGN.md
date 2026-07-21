# DESIGN — PR Review

> Locked design-system source of truth. Every decision here is **frozen for v1**
> unless a follow-up phase explicitly re-opens it. The executable token layer
> lives in `src/styles/tokens.css`; this document is the contract behind it.

---

## 1. Design Read

GitHub PR review automation tool for developers. Genre: **modern-minimal /
cockpit** (Raycast + Linear school). GitHub Dark palette intent preserved,
Geist type, motion reserved for compositor-only micro-interactions. Desktop-only,
dark-mode locked for v1. The product is a status cockpit: the user glances at it
to know *what is being reviewed right now* and *what needs their attention*, then
acts via terse, keyboard-first chrome. Density is high (many rows per viewport),
decoration is low (no marketing surfaces, no hero gradients), and every accent of
color carries meaning (severity, daemon state, focus). P0 codifies that intent as
tokens so later phases can swap the skin without re-arguing the system.

---

## 2. Dials

| Dial | Value | Rationale |
| --- | --- | --- |
| **VARIANCE** | 3 | One palette (GitHub Dark), one typeface family (Geist), one elevation model. Components reuse a small fixed token set; no per-screen theming. |
| **MOTION** | 4 | Compositor-only micro-interactions (opacity/transform on hover, focus, overlay in/out). No narrative or scroll-driven motion; nothing that blocks first paint or the main thread. |
| **DENSITY** | 7 | Cockpit: dense list rows, tight padding, small body type (14px base, 12px/11px secondary). Information-per-pixel is the priority over breathing room. |

---

## 3. Decision Drivers

- **D1 — Dark-mode lock (resolved).** v1 ships dark-only. OKLCH tokens are
  structured so a future light theme is a *token-swap*, not a re-skin. See §13.
- **D2 — Base UI scoped (resolved).** Base UI primitives are adopted where they
  solve real interaction problems (focus management, overlays). The token layer
  is framework-agnostic so it survives any primitive-set decision.
- **D3 — Korean-primary + English chrome (resolved).** Product UI labels are
  English; user-facing copy / hints / command-palette hints are Korean-primary
  (e.g. `hint: "즉시 폴링"`). The token layer is language-agnostic; the type scale
  and line-heights are tuned for mixed CJK/Latin line metrics (Geist + system CJK
  fallback), so no separate CJK scale is introduced in P0.

---

## 4. Palette

All color is **OKLCH**, round-trip-verified (each conversion reproduces its source hex byte-for-byte via the canonical Ottosson M1+M2 matrices).
17 color tokens (surfaces + borders + text + accents + status). Tint/glow/backdrop
aliases carry explicit alpha and live in §"tints" of `tokens.css`.

| Token | OKLCH value | Original hex | Usage |
| --- | --- | --- | --- |
| `--bg` | `oklch(17.63% 0.014 258.4)` | `#0d1117` | App / viewport background |
| `--surface` | `oklch(22.02% 0.016 256.8)` | `#161b22` | Cards, sidebar, panels |
| `--surface-2` | `oklch(24.58% 0.015 256.8)` | `#1c2128` | Raised surface (inputs, popovers) |
| `--surface-hover` | `oklch(26.66% 0.015 256.8)` | `#21262d` | Row / item hover |
| `--bg-deep` | `oklch(10.39% 0.019 248.4)` | `#010409` | `.log-stream` background |
| `--border` | `oklch(33.0% 0.015 252.4)` | `#30363d` | Standard 1px borders, `--shadow` ring |
| `--border-muted` | `oklch(26.57% 0.012 248.3)` | `#21262b` | Subtle dividers |
| `--text` | `oklch(94.25% 0.011 243.9)` | `#e6edf3` | Primary text |
| `--muted` | `oklch(66.25% 0.018 251.0)` | `#8b949e` | Secondary text, meta |
| `--muted-2` | `oklch(56.28% 0.02 256.4)` | `#6e7681` | Tertiary text, placeholders |
| `--on-accent` | `oklch(100% 0 0)` | `#ffffff` | Text/icon on accent background |
| `--on-success` | `oklch(17.63% 0.014 258.4)` | `#0d1117` | Text on success background |
| `--accent` | `oklch(61.82% 0.194 258.34)` | `#2f81f7` | Primary action, links, focus ring |
| `--accent-hover` | `oklch(66.32% 0.169 255.9)` | `#4493f8` | Accent interactive hover |
| `--success` | `oklch(69.51% 0.181 145.6)` | `#3fb950` | Running / ok state |
| `--warning` | `oklch(71.95% 0.14 79.9)` | `#d29922` | Paused / medium severity |
| `--error` | `oklch(66.51% 0.205 26.9)` | `#f85149` | Failed / high severity |

> Alpha-bearing aliases (`--accent-faint`, `--accent-tint-faint`, the `*-glow` /
> `*-tint` / `*-tint-faint` / `--backdrop` / `--overlay`) and the shadow inner
> color are defined verbatim in `tokens.css` with `oklch(... / alpha)` — **never
> `color-mix()`**, which re-composites and is not byte-identical to the original
> rgba literals.

**WCAG AA contrast** for every realistic text-on-background pair is audited in §14.

---

## 5. Token Naming Canon (LOCKED)

Executors in any phase MUST NOT rename the following. Renaming silently breaks
30+ references in `App.css`.

**Canonical — preserved verbatim** (referenced directly from `App.css`):
`--bg`, `--surface`, `--surface-2`, `--surface-hover`, `--border`,
`--border-muted`, `--text`, `--muted`, `--muted-2`, `--accent`, `--accent-hover`,
`--accent-faint`, `--success`, `--warning`, `--error`, `--r-card`, `--r-input`,
`--r-container`, `--shadow`, `--shadow-lg`.

**New additive namespaces — no collision with existing names**:
`--space-N`, `--fs-*`, `--lh-*`, `--ls-*`, `--fw-*`, `--font-*`, `--dur-*`,
`--ease-*`, `--z-*`, `--ring*`, `--on-*`, `--info`, `--backdrop`, `--overlay`,
`--bg-deep`, and the `*-glow` / `*-tint` / `*-tint-faint` severity aliases.
The `--icon-*` namespace (`--icon-sm/md/lg`) is additive (P6 SVG icon sizes).

**Values are not locked, only names.** A token's NAME is canonical (do not
rename); its VALUE may be adjusted additively in a later phase. **Phase 5**
promoted `--z-toast` `50`→`300` (NAME unchanged — `tooltip.css` still consumes
it) so toasts render above every overlay; see §10.

**Reference grep for parity** (run from repo root):

```sh
# Every var(--name) referenced by App.css must resolve to a --name: definition
# in tokens.css. Left = names consumed; right = names defined.
diff \
  <(grep -oE 'var\(--[a-z0-9-]+\)' src/App.css | sed 's/var(\(.*\))/\1/' | sort -u) \
  <(grep -oE '\-\-[a-z0-9-]+:' src/styles/tokens.css | sed 's/://' | sort -u)
```

The "consumed" side must be a **subset** of the "defined" side → zero unresolved
`<` lines that have no matching `>` line. (The literal plan command compares
`var(--x)` strings against `--x` strings; strip the `var(...)` wrapper on the left
for a meaningful subset check. P0 self-check confirms all 19 App.css `var()`
references resolve.)

## Cascade shadowing (P0 → P1 transition)

Until P1 migrates the App.css `:root` block, both tokens.css and App.css define the 20 shared token names. App.css is imported AFTER tokens.css (src/App.tsx L34 tokens, L35 App.css), so App.css wins the cascade. The two files define IDENTICAL source hex values, so P0 rendering is byte-identical regardless. The shadowing matters for the P1 migration: when P1 removes the App.css `:root` block, the rendered values flip from App.css's hex to tokens.css's OKLCH; the round-trip verification above guarantees those are byte-identical. Until then, edits to shared tokens in tokens.css alone are no-ops at runtime.

---

## 6. Type Scale

New additive namespace. P0 defines the scale; P1+ binds components to it
(`App.css` still carries the legacy `font-size: 14px` on `:root`).

| Token | Value | Usage |
| --- | --- | --- |
| `--font-sans` | `'Geist Variable', -apple-system, …` | Default UI font stack |
| `--font-mono` | `'Geist Mono Variable', 'SF Mono', …` | Code, PR numbers, diffs, logs |
| `--fs-display` | `2rem` (32px) | Reserved — not used in v1 chrome |
| `--fs-h1` | `1.5rem` (24px) | Modal / overlay titles |
| `--fs-h2` | `1.15rem` (~18px) | Section headers |
| `--fs-h3` | `0.95rem` (~15px) | Card titles, list-group headers |
| `--fs-body` | `0.875rem` (14px) | Body text (base) |
| `--fs-sm` | `0.75rem` (12px) | Secondary text, meta, table cells |
| `--fs-xs` | `0.6875rem` (11px) | Labels, eyebrows, shortcuts |
| `--lh-tight` | `1.1` | Headings |
| `--lh-snug` | `1.3` | Compact rows, titles |
| `--lh-base` | `1.5` | Body (default) |
| `--lh-relaxed` | `1.6` | Long-form / settings copy |
| `--ls-tight` | `-0.01em` | Headings |
| `--ls-display` | `-0.02em` | Display sizes |
| `--ls-label` | `0.04em` | Form labels, small caps |
| `--ls-eyebrow` | `0.18em` | Eyebrows (uppercase) |
| `--fw-regular` | `400` | Body |
| `--fw-medium` | `500` | Emphasized body, active nav |
| `--fw-semibold` | `600` | Card titles, buttons |
| `--fw-bold` | `700` | Severity badges, numbers |

> **Geist prerequisite (P1).** Geist Variable and Geist Mono Variable woff2 assets are a P1 prerequisite. Until P1 adds them under `src/styles/fonts/` with `@font-face` in `base.css`, the first family in `--font-sans` / `--font-mono` falls through to the system fallback stack — Geist does NOT render until P1.

---

## 7. Spacing Scale (8px grid)

| Token | Value | Token | Value |
| --- | --- | --- | --- |
| `--space-1` | `4px` | `--space-7` | `48px` |
| `--space-2` | `8px` | `--space-8` | `64px` |
| `--space-3` | `12px` | `--space-9` | `80px` |
| `--space-4` | `16px` | `--space-10` | `96px` |
| `--space-5` | `24px` | `--space-11` | `128px` |
| `--space-6` | `32px` | `--space-12` | `160px` |

All layout padding/gap in new components resolves through `--space-*`. `--space-1`
(4px) is the intentional half-step of the 8px grid for tight controls.

---

## 8. Radii Scale

| Token | Value | Usage |
| --- | --- | --- |
| `--r-input` | `4px` | Inputs, buttons, chips |
| `--r-card` | `6px` | Cards, panels, list rows |
| `--r-container` | `12px` | Overlays, modals, large containers |
| (literal, untokenized in P0) | `9999px` | Pill — badges / icon buttons. **Promoted to a token in P4.** |

`--r-input`, `--r-card`, `--r-container` are CANONICAL and MUST NOT be renamed.

---

## 9. Motion Tokens

Motion is **compositor-only**: `opacity` and `transform` only, never `width` /
`height` / `top` / `left`. Durations are short; easings are gentle.

| Token | Value | Usage |
| --- | --- | --- |
| `--dur-fast` | `120ms` | Hover, toggle, micro state |
| `--dur-base` | `200ms` | Default transition (overlay fade, row hover) |
| `--dur-slow` | `400ms` | Modal in/out, large surface |
| `--ease-out` | `cubic-bezier(0.16, 1, 0.3, 1)` | Default decelerate (entering) |
| `--ease-spring` | `cubic-bezier(0.32, 0.72, 0, 1)` | Spring-like affordances |

**Banned:** spring physics libraries, layout-thrashing transitions, `transition:
all`, and any motion triggered by scroll.

---

## 10. Z-Index Ladder

Fixed ladder; new layers MUST pick the nearest rung, never a raw integer.

| Token | Value | Usage |
| --- | --- | --- |
| `--z-base` | `0` | Default content |
| `--z-sticky` | `10` | Sticky headers, sticky toolbar |
| `--z-dropdown` | `20` | Menus, command palette, popovers |
| `--z-overlay` | `30` | Settings overlay backdrop |
| `--z-modal` | `40` | Modal dialogs |
| `--z-toast` | `300` | Toasts (render above all overlays). **Phase 5** promoted `50`→`300` — the NAME is shared with `tooltip.css` (`.tooltip`), so the bump also raises tooltips to 300; benign because tooltips only render on hover of a visible trigger. |
| `--z-wizard` | `50` | First-run Wizard fullscreen overlay |
| `--z-slide-over` | `90` | Monitoring PR-detail slide-over |
| `--z-settings` | `100` | Settings overlay |
| `--z-palette` | `200` | Command palette |

> The four overlay tokens (`--z-wizard` / `--z-slide-over` / `--z-settings` /
> `--z-palette`) pre-existed in `tokens.css` but were undocumented in this
> ladder until the Phase 5 reconciliation pass; recorded here for parity.

---

## 11. 8-State Rule

Every interactive primitive (button, nav item, input, tab, row, badge-as-button)
MUST ship CSS for all eight states:

`default` · `hover` · `active` · `focus-visible` · `focus-within` · `disabled` ·
`loading` · `error`

P0 defines the **rule and the focus ring tokens** (`--ring`, `--ring-offset`).
The **coverage table** — mapping each primitive to the eight states and the file
line where each is implemented — is populated in **P2**. P0's contract is that no
new primitive may land without all eight states; missing states are a P2 defect,
not a P0 defect.

---

## 12. Banned Patterns

| Pattern | Why banned | Do instead |
| --- | --- | --- |
| AI purple gradient | Off-genre; reads as marketing, not cockpit | Flat surface tokens; accent only for meaning |
| Italic headings | Off-genre; hurts CJK legibility | Upright headings, weight-based hierarchy |
| Glow-as-affordance | Accessibility: glow must not be the only signal that something is interactive | Pair glow with shape/color/label change |
| `h-screen` / `100vh` | Mis-measures mobile browser chrome; desktop is fine but consistency wins | `100dvh` |
| Serif display defaults | Off-genre | Geist sans / mono only |
| `color-mix()` for existing rgba tints | Re-composites; **not byte-identical** to the original GitHub Dark rgba literals | `oklch(... / alpha)` with the exact alpha preserved |

---

## 13. Dark-Mode Lock

v1 is **dark-only**. There is no `prefers-color-scheme` branch and no `.light`
class. The entire palette is expressed as OKLCH tokens in `tokens.css`; a future
light theme is a **token-swap** (re-define `--bg`, `--surface*`, `--text`,
`--muted*`, etc. in a `:root.light` override) — no component CSS changes required.
Because every chromatic value is OKLCH (perceptually uniform), a light-theme swap
will keep perceived lightness relationships intact, which hex/sRGB swaps do not
guarantee.

---

## 14. WCAG AA Contrast Audit

Every realistic text-on-background pair. Verified measurements (P0 records the
audit; **does not fix in P0**). Classification:

- **AA-body-pass** — contrast ≥ 4.5:1 (safe for body text).
- **AA-large/UI-pass-only** — 3.0:1 ≤ contrast < 4.5:1 (passes for ≥18px /
  ≥14px-bold text and for UI component boundaries; **not** for small body text).
- **Fail** — contrast < 3.0:1.

| Foreground | Background | Ratio | Class | Note |
| --- | --- | --- | --- | --- |
| `--text` | `--bg` | 13.65 | body-pass | Primary text on viewport |
| `--text` | `--surface` | 11.34 | body-pass | Primary text on cards |
| `--text` | `--surface-2` | 10.05 | body-pass | Primary text on raised surface |
| `--text` | `--bg-deep` | 15.30 | body-pass | Primary text on log stream |
| `--muted` | `--bg` | 6.34 | body-pass | Secondary text |
| `--muted` | `--surface` | 5.27 | body-pass | Secondary text on cards |
| `--muted` | `--surface-2` | 4.67 | body-pass | Secondary text on raised surface |
| `--muted-2` | `--bg` | 4.12 | **large/UI-pass only — ATTENTION** | placeholder/hint text borderline |
| `--muted-2` | `--surface` | 3.77 | **large/UI-pass only — ATTENTION** | placeholder/hint on cards |
| `--muted-2` | `--surface-2` | 3.52 | **large/UI-pass only — ATTENTION** | placeholder/hint on raised surface |
| `--muted-2` | `--bg-deep` | 4.47 | **large/UI-pass only — borderline body** | placeholder/hint on log stream |
| `--accent` | `--bg` | 5.49 | body-pass | Links on viewport |
| `--accent` | `--surface` | 4.56 | body-pass | Links on cards |
| `--accent` | `--surface-2` | 4.32 | **large/UI-pass only — ATTENTION** | `.pr-number`, `.tab-item.active` are usually bold/medium |
| `--on-accent` | `--accent` | 3.75 | **large/UI-pass only — BY DESIGN** | Button text is 14px+ medium/bold |
| `--on-success` | `--success` | 6.30 | body-pass | Text on success badge bg |
| `--success` | `--bg` | 5.34 | body-pass | Success status text |
| `--warning` | `--bg` | 6.46 | body-pass | Warning status text |
| `--error` | `--bg` | 4.77 | body-pass | Error status text |
| `--error` | `--surface` | 3.96 | **large/UI-pass — BY DESIGN** | Severity badge text is small-caps bold on tint bg |

**Follow-up (P4, not P0):** the `--muted-2` family and `--accent` on
`--surface-2` are borderline for *small body text*. If real small-body-text usage
is found during P2 coverage mapping, P4 may introduce a slightly lightened
`--muted-2` (or a dedicated `--hint` token) and nudge `--accent`-on-`--surface-2`
usage toward `--text` / `--muted`. P0 records; it does not change values.

---

## 14b. 8-State Coverage Matrix

Per §11, every interactive primitive MUST ship CSS for all eight states:
`default` · `hover` · `active` · `focus-visible` · `focus-within` · `disabled`
· `loading` · `error`.

The `default` state is the rule itself; `focus-visible` is provided globally
in `src/styles/base.css` via the `:focus-visible` ring (`--ring` /
`--ring-offset`). This matrix records, per primitive, which of the remaining
states have explicit CSS today (Phase 2 Slice B) and which are tracked as
P4 follow-ups. CSS file locations are under `src/styles/components/`.

Legend: ✅ = explicit CSS today · ◻ = deferred to P4.

| Primitive | default | hover | active | focus-visible | focus-within | disabled | loading | error | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `.btn` (primary/secondary) | ✅ buttons.css | ✅ `:hover:not(:disabled)` | ◻ | ✅ base.css | ◻ | ✅ `:disabled` | ✅ `.btn[data-loading]` (P5 transform-only spinner) | ◻ | loading now covered generically via `[data-loading]` (P5); bound on Approve/Reject/Save/AlertDialog-confirm |
| `.link-btn` (Clear / Reset) | ✅ buttons.css | ✅ `:hover` | ◻ | ✅ base.css | ◻ | ◻ | ◻ | ◻ | destructive Clear is gated by AlertDialog (Phase 2 Slice B); not a CSS state |
| `.sidebar-item` (nav) | ✅ sidebar.css | ✅ `:hover` | ✅ `.active` / `:active` | ✅ base.css | ◻ | ◻ | ◻ | ◻ | active state = current tab |
| `.tab-item` (Base UI Tabs) | ✅ tabs.css | ✅ `:hover` | ✅ `.active` (selected) | ✅ base.css + Base UI roving tabindex | ◻ | ◻ | ◻ | ◻ | Base UI provides arrow-key nav + roving tabindex + aria-selected (Slice B) |
| `.filter-chip` | ✅ tabs.css | ✅ `:hover` | ✅ `.active` | ✅ base.css | ◻ | ◻ | ◻ | ◻ | |
| `.poll-now-btn` (DaemonStatusBadge) | ✅ daemon-status-badge.css | ✅ `:hover` | ◻ | ✅ base.css | ◻ | ✅ `:disabled` | ✅ busy glyph swap (`<Icon name="hourglass"/>`, P6) | ◻ | aria-label="즉시 폴링"; await-driven in P5 |
| `.pr-row` (Monitoring list) | ✅ monitoring.css | ✅ `:hover` | ◻ | ✅ base.css | ◻ | ◻ | ◻ | ◻ | opens slide-over (Base UI Dialog) on click |
| `.slide-over-close` (✕) | ✅ slide-over.css | ✅ `:hover` | ◻ | ✅ base.css | ◻ | ◻ | ◻ | ◻ | aria-label="닫기" added in Slice B |
| `.settings-overlay-close` (✕) | ✅ settings.css | ✅ `:hover` | ◻ | ✅ base.css | ◻ | ◻ | ◻ | ◻ | aria-label="닫기" added in Slice B |
| `.finding-code-toggle` (code/edit) | ✅ pending.css | ◻ | ✅ `aria-pressed` | ✅ base.css | ◻ | ◻ | ◻ | ◻ | toggle button (aria-pressed conveys state) |
| `.palette-item` (CommandPalette) | ✅ command-palette.css | ✅ `:hover` / `.selected` | ◻ | ✅ base.css | ◻ | ◻ | ◻ | ◻ | hand-rolled Tab focus-trap preserved (Slice B adds focus-restore) |
| `.test-btn` (Settings/Wizard) | ✅ forms.css | ◻ | ◻ | ✅ base.css | ◻ | ✅ `:disabled` | ✅ testing glyph (`state-msg`) | ✅ `state-msg` fail | state-driven via TestState; not pure CSS |
| `.segmented-control button` | ✅ tabs.css | ✅ `:hover:not(.active)` | ✅ `.active` | ✅ base.css | ◻ | ◻ | ◻ | ◻ | review-mode toggle |
| `.severity-badge` (Pending) | ✅ pending.css | ◻ | ◻ | n/a (display only) | ◻ | ◻ | ◻ | ✅ sev-high/error tint | severity = `error` analog for display badges |
| `.badge` (status counts) | ✅ badges.css | ◻ | ◻ | n/a (display only) | ◻ | ◻ | ◻ | ◻ | static; state-bearing via `.badge-active/-success/-error/-idle` |
| `.summary-card` / `.pr-row` (display) | ✅ cards.css / monitoring.css | ◻ | ◻ | n/a (display only) | ◻ | ◻ | ◻ | ◻ | not interactive |
| `.alert-dialog-confirm` (Base UI AlertDialog) | ✅ alert-dialog.css | ✅ `:hover` filter | ◻ | ✅ base.css | ◻ | ✅ `disabled` (P5) | ✅ `data-loading` (P5 async-aware confirm) | ✅ destructive `--error` bg | P5: confirm = plain `<button>` (async-aware; closes on success, stays open on failure) |
| `.toast` (ToastProvider item) | ✅ toast.css (P5) | n/a (dismiss-on-click) | n/a | ✅ base.css | ◻ | n/a | n/a | ✅ `.toast--error` variant | display+dismiss; `aria-live` region; sticky for error |
| `.toast-close` (✕) | ✅ toast.css (P5) | ✅ `:hover` | ◻ | ✅ base.css | ◻ | ◻ | ◻ | ◻ | aria-label="알림 닫기" |

**State implementation summary**

- **default** — every primitive has its base rule (✅ across the board).
- **hover** — covered for all interactive primitives that are pointer-driven.
  ◻ on `.finding-code-toggle`, `.test-btn` (low-traffic); P4 may add `:hover`
  tints via `--accent-tint-faint` for parity.
- **active** — covered where `.active` is a selection state (sidebar, tab,
  filter-chip, segmented-control). `:active` (press) is intentionally not
  styled separately; the global `:focus-visible` ring + the `.active` class
  together convey press/selection.
- **focus-visible** — provided globally by `:focus-visible { outline: 2px
  solid var(--ring); outline-offset: var(--ring-offset); }` in
  `src/styles/base.css`. No primitive needs to redeclare it; per-primitive
  overrides are tracked as P4 polish.
- **focus-within** — not used today; relevant only for composite containers
  (e.g. `.pending-finding`). ◻ across the board; revisit if a container needs
  to surface focus on a child.
- **disabled** — covered on `.btn`, `.poll-now-btn`, `.test-btn`.
- **loading** — explicit CSS is rare: `.poll-now-btn` swaps glyph; `.test-btn`
  is driven by component state. Other primitives have no async work, so the
  state is n/a.
- **error** — covered where it is semantically a color (`.severity-badge`
  sev-high = `--error-tint`; `.alert-dialog-confirm` uses `--error` bg;
  `.test-btn` fail state via `state-msg`). General input-error styling is a
  P4 polish pass.

**Phase 2 Slice B additions (this slice)**

1. `@base-ui-components/react@1.0.0-rc.0` installed; thin wrappers created at
   `src/components/ui/{AlertDialog,Dialog,Tabs,Tooltip}.tsx`.
2. AlertDialog wires destructive confirms (Pending 리뷰 거부 / Monitoring
   기록 삭제 / Logs 로그 삭제); confirm button uses `--error`.
3. Monitoring tabs use Base UI Tabs (arrow-key nav, roving tabindex,
   `aria-selected`).
4. Slide-over + Settings overlay use Base UI Dialog (focus trap + restore,
   Escape, backdrop click).
5. CommandPalette focus-restore-on-close (WCAG 2.4.3); hand-rolled Tab trap
   preserved.
6. `aria-label` on every icon-only button (poll / slide-over close / settings
   close).
7. CSS for the alert-dialog + tooltip surfaces added at
   `src/styles/components/alert-dialog.css` and `tooltip.css`, imported from
   `src/styles/index.css`. Existing CSS untouched; no token renamed.

---


## 15. Out of Scope for v1

- Light theme (token-swap is mechanically possible; not shipped).
- Tailwind / utility-CSS migration (CSS is now token-based vanilla CSS, split across `src/styles/components/`; not migrated to Tailwind).
- i18n framework (Korean-primary copy is authored inline; no `react-intl` etc.).
- Mobile responsive design (desktop Tauri only; no breakpoints in P0).
- Automated `jest-axe` accessibility tests (manual WCAG audit in §14 is the v1
  bar; automated a11y is deferred).
- Icon library — a hand-rolled `src/components/ui/Icon.tsx` with inlined
  Lucide/Feather (MIT/ISC) path data is the v1 system. `lucide-react` was
  evaluated and rejected: named imports pull the whole set in Vite DEV (no
  tree-shaking), adding a runtime dep + ESM-resolution surface in the Tauri
  webview for ~12 icons.

---

## Changelog

- **Phase 0** — Initial locked design contract. Created `DESIGN.md` and
  `src/styles/tokens.css`; added the `tokens.css` import to `src/App.tsx`.
  Additive only: no existing `App.css` rule modified. `shared/src/ipc-contract.ts`
  and `src-tauri/` untouched. (G007 correction: re-derived all OKLCH values via
  canonical Ottosson M1+M2; accent precision fix H 258.3→258.34.)
- **Phase 1** — Geist self-host (`@fontsource-variable/geist` + `geist-mono`);
  `src/styles/base.css` created (font-display: optional, :focus-visible ring);
  `App.css` :root stripped of 20 token definitions (tokens.css sole source);
  ALL hex/rgba/font-family literals replaced with token references;
  tabular-nums on 9 numeric selectors; Korean 해요체 normalized.
- **Phase 2 Slice A** — Mechanical CSS split: `src/App.css` (1971 lines)
  deleted and split into 18 per-component files under `src/styles/components/`
  + `src/styles/reset.css` + `src/styles/index.css` (entry). Rule-equivalence
  verified: 266 rule bodies byte-identical as multiset; @media order preserved
  (980px before 720px in monitoring.css); @keyframes count 3 (spin/fade-in
  in shell.css, slide-in in slide-over.css). `100vh`→`100dvh` (2 occurrences).
  `App.tsx` L36 now imports `./styles/index.css`.
- **Phase 2 Slice B** — Base UI integration + a11y: `@base-ui-components/react`
  installed; 4 wrapper components (`AlertDialog`, `Dialog`, `Tabs`, `Tooltip`)
  in `src/components/ui/`; destructive actions (Pending Reject, Monitoring
  Clear history, Logs Clear) wrapped in AlertDialog (해요체 Korean copy,
  `--error` confirm); Monitoring tabs → Base UI Tabs (arrow-key + roving
  tabindex); slide-over + Settings → Base UI Dialog (focus trap/restore);
  CommandPalette focus-restore-on-close (WCAG 2.4.3); aria-labels on all
  icon-only buttons; 8-State Coverage Matrix added to DESIGN.md §14b.
- **Phase 5** — Feedback layer: `src/components/ui/Toast.tsx` (`ToastProvider`
  + `useToast()` + body-end `aria-live` portal + single `daemon://error`
  subscription — the FIRST and ONLY consumer of that event) +
  `src/styles/components/toast.css`; `src/lib/toastQueue.ts` pure reducer +
  tests; `AlertDialog` made async-aware (confirm = plain `<button>`,
  `onConfirm: () => void | Promise<void>`, closes on success / stays open on
  failure); `.btn[data-loading]` spinner (buttons.css); `--z-toast` value
  promoted `50`→`300` (NAME unchanged; §10 reconciled incl. the 4 drifted
  overlay tokens). Bug fix: `usePendingReviews.approve/reject` are now
  `async` + await-then-remove-on-success + `submitting` state (cleared on
  `onDaemonReady`, M9) — eliminates the silent optimistic-remove-on-failure.
  DevDeps `happy-dom` + `@testing-library/react` added (race coverage).
- **Phase 6** — i18n unification (D3) + SVG icon system: hand-rolled
  `src/components/ui/Icon.tsx` (22-name `IconName` union, `currentColor`
  inline SVG, Lucide/Feather MIT path data; `lucide-react` rejected — Vite
  DEV tree-shaking) + additive `--icon-sm/md/lg`; ALL pictographic emoji
  icons replaced across App/routes/components; Korean-primary user-facing
  copy normalized in Pending / Monitoring slide-over / Logs /
  DaemonStatusBadge (chrome labels stay English). Deviations (recorded): no
  test-connection toasts (inline `TestState` already covers); no Wizard
  `saveConfig` toast (local `setError` banner, first-run context).
