# fabaka.dev: shared spec for the five design alternatives

Each design is one self-contained page at `site/designs/<n>-<slug>/index.html`: inline CSS and JS, no build step, no framework. Allowed external requests: Google Fonts only. Shared images are in `site/assets/` (reference them as `../../assets/...`):

- `fabaka-icon.webp` / `fabaka-icon.png`: the real app icon (a border collie peeking over an edge, on periwinkle, in a macOS rounded tile). `favicon.png`: 64 px.
- `collie-art.webp`: the same artwork, full-bleed square, no rounded tile.

## Who and what

Visitors are Mac users fed up with the built-in ⌘Tab who mostly don't know a window switcher exists. They arrive from a chat link or a tweet, decide in seconds, and the one action is copying the install command. Read `PRODUCT.md` at the repo root for the product record.

The single idea: **a better ⌘Tab for Mac: fast and minimal.** Those two qualities are the only things the page markets. The demo must make them felt before anyone reads a sentence: the list is there the instant ⌘Tab goes down (no fade, no delay), the switch lands immediately, and the switcher is nothing but a clean list.

Not marketed, never framed as a selling point: "⌘Tab switches apps, Fabaka switches windows" or any apps-vs-windows contrast with the built-in switcher (don't build the page on a side-by-side with it); and Settings of any kind (Resident apps / "Stay", the quick-tap wait, "open the app again for Settings").

## Facts you may use (each at most once on the page; never invent others)

- Hold ⌘ and press Tab: every window is listed, most recent first. Release ⌘ to jump to the selected one.
- Every Space, every screen, minimized and hidden windows included.
- While the list is open: W closes the selected window, Q quits its app.
- Apps left running with no windows are listed too, so Q cleans them up.
- Speed, measured on the author's M3 Pro over 617 presses in a week: the list is ready 1.6 ms after ⌘Tab (median; 16 ms at the 95th percentile); the chosen window is on top 50 ms after you let go (median). If you show a number, show where it comes from in a short footnote.
- No Screen Recording permission, ever: Accessibility only (icons and titles, no window thumbnails).
- Free, open source (MIT). No account, no telemetry, no menu-bar icon.
- Needs macOS 26 on Apple silicon.
- Install: `brew install --cask zmievsa/tap/fabaka` with a copy button. Source: https://github.com/zmievsa/fabaka

Forbidden: testimonials, user counts, star counts, benchmarks, "trusted by", press, pricing, any claim not listed above, and the old name.

## What the built-in ⌘Tab looks like (only if a design still needs it; it is no longer the point)

A dark translucent rounded strip centered on screen with one large icon per running app in a single row, the selected app's icon on a lighter rounded highlight, and the app name under it. One icon per app, however many windows the app has; no window titles; minimized windows and other Spaces are not represented. Draw it as a stylised illustration, not a copy of Apple artwork, and never show an Apple logo.

## What Fabaka's switcher looks like

A dark translucent rounded panel, ~640 px wide, centered, a vertical list of rows ~40 px tall: app icon (28 px) on the left, the window title in medium weight, the app name small and right-aligned in secondary colour. The selected row has a filled accent highlight (rounded 8 px) with white text. Minimized windows have dimmed icons and a small "minus in a square" glyph; windows of hidden apps a small "eye with slash" glyph; apps with no windows show "No windows" where the app name goes.

## Demo content (fictional, consistent across designs)

Use generic apps drawn by you as simple flat rounded-square SVG icons, each with its own colour and a simple drawn glyph (never emoji, never real brand logos): Browser, Mail, Editor, Terminal, Notes, Music, Chat, Design, Calendar. Example windows: Browser "Flights to Lisbon", Browser "PR #212 · fix login", Browser "Docs · Getting started"; Editor "app.swift", Editor "README.md"; Terminal "~/code · zsh"; Mail "Inbox (3)"; Notes "Groceries" (minimized); Design "Logo v4"; Chat "Team" (on another Space). One windowless leftover: Music, "No windows". Built-in ⌘Tab shows only one icon per app.

## Craft rules (all designs)

- Very minimal, little text, nothing said twice. The demo carries the argument.
- Read `/Users/zmievsa/.claude/skills/impeccable/reference/craft-floor.md` and `/Users/zmievsa/.claude/skills/impeccable/reference/mode-persuade.md` before writing code and follow them. In particular: no eyebrow/kicker label above a headline, no gradient text, no emoji as icons, no generic three-card feature grid, no glass/blur as decoration (the switcher panels themselves are translucent because the real ones are).
- Don't reach for these faces: Fraunces, Playfair Display, Cormorant, Lora, Crimson, Newsreader, Syne, Space Grotesk, Space Mono, IBM Plex, Inter as display, DM Sans, DM Serif, Outfit, Plus Jakarta Sans, Instrument Sans.
- The install command and copy button are visible without hunting; the copy button confirms ("Copied").
- Motion: one authored signature moment, not scattered effects. Content is visible without JS and with `prefers-reduced-motion` (show a settled still).
- Works at 1440 px desktop and 390 px phone width with no horizontal scroll. On a phone the demo still reads.
- Keyboard and focus states styled; text contrast at least 4.5:1.
- `<title>Fabaka: ⌘Tab for windows</title>`-style title (you may phrase it), the favicon, a meta description, and an og:image pointing at `../../assets/fabaka-icon.png`.

## Verify before you report

Screenshot with headless Chrome using a throwaway profile (never the user's):

```sh
T=$(mktemp -d); "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars --user-data-dir=$T --virtual-time-budget=6000 --window-size=1440,900 --screenshot=<out.png> "file://<abs path to index.html>"; rm -rf $T
```

Capture 1440x900 (first viewport), a full-page shot (tall window size such as 1440x3000), and 390x844. Open each PNG, fix what's wrong, re-shoot once. Then run `/Users/zmievsa/.claude/skills/impeccable/scripts/impeccable detect --json <your index.html>` and fix mechanical findings. Save final screenshots next to the page as `shot-desktop.png`, `shot-full.png`, `shot-phone.png`.
