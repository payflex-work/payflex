# PayFlex — UI/UX & Motion Design Brief (v2 — matched to logo, no glow)

> Added as a follow-up to [`BUILD_PROMPT.md`](BUILD_PROMPT.md) once Phases 1-5
> were scaffolded and implemented. This is the source of truth for visual
> design and motion once implementation starts — see the "Status" note at
> the bottom for what's actually been built against it so far.

Add this section to the main build prompt in Claude Code, or paste it in as a follow-up once Phase 1 is scaffolded. This version replaces the earlier design brief — it's built directly off the approved logo (QR-corners + flowing arrow mark, blue-to-emerald gradient) and removes all glow/neon effects.

---

## 1. Design direction

**Feel:** premium private-bank meets modern fintech — closer to Wise, Revolut, or Cash App than to a typical microfinance app. Confident, quiet, uncluttered. The business should feel bigger and more trustworthy than it is, without lying about what it does.

**Not this:** default Material Design blue, bootstrap-looking buttons, cluttered dashboards with too many colored cards, comic/cartoon iconography, and — explicitly — **no glow, no neon bloom, no soft-glow drop shadows on icons/buttons/text anywhere in the app.** The logo's gradient is vivid but flat and clean, not glowing; the app must match that, not drift toward a "gamer app" or neon-cyberpunk look. Any shadow used must be a soft, low-opacity, close, realistic elevation shadow — never a colored glow radiating outward from an element.

### Core visual identity (pulled directly from the logo)
- **Primary gradient:** deep royal blue (`#0B2FBE`-ish, matching the logo's top-left blue) transitioning to emerald/spring green (`#1FD65F`-ish, matching the logo's bottom-right green). Use this gradient sparingly and intentionally — the splash screen, the primary CTA button, the balance card background — not smeared across every surface.
- **Base background:** a deep navy (`#0A1330`-ish, sampled from the logo's dark QR-code background) for dark-mode key screens (wallet home, splash, onboarding). This is a flat dark navy, not black, and not glowing.
- **Light mode base:** off-white (`#F7F7F5`), same blue→green gradient reserved for accents and CTAs only.
- **Accent usage:** the blue→green gradient is the *only* strong color move in the app. Everything else — text, icons, dividers, secondary surfaces — stays white, off-white, or muted grey/navy. This restraint is what makes the gradient feel premium instead of loud.
- **Typography:** one confident geometric display face for balances/headers (Inter, General Sans, or Satoshi at heavier weights), clean readable body face. Large, generous type for money amounts — the balance number is the visual anchor of wallet home.
- **Iconography:** custom-drawn line icons in flat white or navy, consistent stroke weight, no mixed icon packs, no glow or neon outlines on icons.
- **Cards/surfaces:** rounded corners (match the logo's rounded-square container radius proportionally — pick one radius scale, e.g. 12/16/24px, and stick to it). Elevation via soft, tight, realistic shadow only — flat design, no glow, no glassmorphism blur-glow combo.

### The signature motif (from the logo)
The logo's core shape — the flowing arrow/ribbon cutting through the QR corners — is the app's recurring visual signature. Reuse it deliberately:
- As a subtle, low-opacity watermark shape in the corner of the wallet home background (flat, not glowing).
- As the shape the loading indicator draws itself from (see motion section).
- As the "success" mark shape during transfer confirmation — the ribbon/arrow completing its path, not a generic checkmark.
- As a thin accent line on receipts and section headers.

Do not scatter QR-corner brackets or the arrow shape decoratively everywhere — use it in these specific, meaningful places so it stays a signature rather than becoming visual noise.

---

## 2. Motion & animation requirements

Motion communicates money moving with weight and confidence — never bouncy/cartoonish, never instant/jarring, and **never accompanied by glow/bloom effects** (no pulsing light auras, no neon trails). Aim for physically-plausible, restrained motion (200–400ms, ease-out curves), the way Apple Pay or Wise transitions feel — clean and flat, not gamer-app or sci-fi.

Build these as first-class, reusable animation components (Flutter: `Hero`, `AnimatedContainer`/`AnimatedSwitcher`, `Rive` or `Lottie` for the more complex sequences) — not one-off animations bolted onto individual screens.

**Required signature animations:**
1. **Balance reveal** — on wallet home load, the balance number counts up/settles into place (subtle, ~400ms, once per session).
2. **Transfer confirmation** — the single most important animation in the app. The logo's ribbon/arrow motif draws itself along its path and settles, in flat gradient color, no glow or particle burst. This is the emotional payoff moment — get it right before anything else.
3. **QR scan → confirm transition** — the scanner view morphs into the confirm-payment sheet via a shared-element/Hero transition on the QR frame, not a hard page cut.
4. **Card/screen transitions** — consistent shared-axis or fade-through transitions between major sections, no default platform slide-in used inconsistently.
5. **Loading states** — a custom branded loader built from the arrow/ribbon motif tracing itself in a loop, flat gradient stroke, no glow — never the default spinner.
6. **Split-bill progress** — a ring or bar filling in flat gradient color as each contributor's share lands, no glow pulse.

**Explicitly avoid:** glow/bloom/neon effects of any kind, excessive bounce/spring easing, confetti/emoji bursts, more than one attention-grabbing animation on screen at once, animations that block the user from proceeding (always allow skip/tap-through).

---

## 3. "Business touch" — details that read as trustworthy and grown-up

- **Empty states and errors are designed, not default.** Real copy plus a simple flat icon in the brand style — never a bare "No data" or an unstyled red error box.
- **Receipts feel official.** Clear amount hierarchy, reference number, timestamp, status badge, logo mark small and flat at the top — never a wall of raw JSON-looking fields, never glowing text.
- **Numbers are formatted with care.** Currency symbol/code, thousands separators, and consistent decimal handling app-wide via a single shared money-formatting utility.
- **Onboarding/KYC doesn't feel like paperwork.** Clear step progress ("Step 2 of 5"), one action per screen, encouraging micro-copy — this is the part of a microfinance app users trust least, so it needs the most design care.
- **Dark mode and light mode both fully designed**, not auto-inverted — dark-default for wallet home/splash, light-default for forms, per section 1.
- **A real settings/profile screen** with account tier, verification status badge, and support access clearly visible.

---

## 4. Implementation notes for Claude Code

- Set up a single `AppTheme`/design-tokens file (exact hex values sampled from the logo, spacing scale, radius scale, type scale, motion durations/curves) referenced everywhere — no inline hex codes or magic numbers in widget code.
- Add a lint/review checklist item: **no `BoxShadow` with spread/blur used to fake a glow, no colored shadows, no `Container` decorations simulating neon.** If a shadow is used, it must be a small, low-opacity, neutral-dark elevation shadow only.
- Build a small internal component library first (`BalanceCard`, `PrimaryButton`, `TransferConfirmationAnimation`, `BrandedLoader`, `ReceiptView`) before wiring up full screens, so the look is consistent by construction rather than retrofitted later.
- If using Rive/Lottie for the signature animations, keep source files in `/design/animations` in the repo and document how to swap them.
- After each phase in the main build prompt, check screens against sections 1–3 here — specifically confirm no glow effects have crept in — before calling that phase done.

---

## Status

Not yet implemented. Phases 1-5 (see `BUILD_PROMPT.md`) were built with
plain Material 3 defaults (`colorSchemeSeed: Colors.indigo`) and no design
system — every screen currently uses stock `Scaffold`/`Card`/`FilledButton`
widgets with no shared tokens file, no custom motion, and no logo/brand
assets. Applying this brief means a real visual pass across every screen
built so far, plus:

- **No logo file has been provided yet** — the hex values above are
  written as approximations ("-ish") in the brief itself. Get the actual
  logo asset (SVG/PNG) before building `AppTheme` so the sampled colors
  are exact, not guessed twice.
- **This environment cannot visually verify Flutter UI** — no display,
  no emulator. A theme/component pass can be written and can pass
  `flutter analyze`, but someone needs to actually look at it on a device
  before calling the visual design "done," the same caveat that's applied
  to every other Flutter change in this project.
- Custom Rive/Lottie motion (signature animations in section 2) is a
  meaningfully larger lift than the static theme/token work — recommend
  sequencing tokens → component library → static screen restyle → motion,
  matching this brief's own section 4 advice, rather than attempting all
  of it in one pass.
