# Product

<!-- impeccable:product-schema 1 -->

## Platform

web (fabaka.dev, the product's one-page site). The product itself is a native macOS 26 app.

## Stack

Static HTML/CSS/JS, one self-contained page, no build step.

## Users

Mac users who switch with the built-in ⌘Tab and are fed up with it, mostly without knowing a window switcher exists. They decide in seconds whether the page shows something ⌘Tab can't do.

## Product Purpose

Fabaka replaces ⌘Tab with a window switcher: hold ⌘, press Tab, and every window (every Space, every screen, minimized and hidden ones included) is listed by recency; release ⌘ to focus the selected one. Success for the site: a visitor understands the difference from ⌘Tab at a glance and copies the install command.

## Positioning

A better ⌘Tab for Mac. Fabaka is marketed on two things only: speed and minimalism. Speed: the list is on screen the moment you press ⌘Tab and the switch lands immediately (measured on the author's M3 Pro over 617 presses: list ready in 1.6 ms median, 16 ms p95; the chosen window on top in 50 ms median). Minimalism: a plain list of windows, nothing else on screen, nothing to learn, no menu-bar icon, no account, Accessibility only. Not marketed: "windows vs apps" as a contrast with the built-in switcher, and Settings of any kind (Resident apps, the quick-tap wait). Those exist but are never selling points.

## Operating Context

Used dozens of times an hour with one hand on ⌘. The page is visited from a link in a chat, a tweet or GitHub, usually on a Mac.

## Capabilities and Constraints

Confirmed behavior (README): Tab/⇧Tab and arrows move the selection; Return focuses; Esc cancels; click a row to focus; W closes the selected window; Q quits its app. Running apps with no windows are listed below the windows so Q can quit leftovers; Resident apps (Finder, Tailscale, Ghostty by default) are left out. An optional 0–300 ms wait hides the list on a quick tap. Needs macOS 26 on Apple silicon and the Accessibility permission only. No menu-bar icon: opening the app again shows Settings. Starts at login. No telemetry, no auto-updates.

Install: `brew install --cask zmievsa/tap/fabaka` (not in Homebrew's official casks yet). Source: https://github.com/zmievsa/fabaka. Formerly named Flick.

## Brand Commitments

Name: Fabaka. Mascot and app icon: a minimal black-and-white border collie peeking over an edge with two paws, on periwinkle (`Resources/icon-art.png`, `Resources/AppIcon.icns`). Settings copy uses dog commands: shelves are "Stay" and "Free to go".

## Evidence on Hand

The app icon. Real screenshots can be taken from the running app. No testimonials, user counts, benchmarks or press: none exist and none may be invented. One internal measurement exists (546 switches of its author: 71% released within 100 ms), not a claim about users.

## Product Principles

- Show, don't claim: the switcher demonstrated beats any sentence about it.
- Instant over clever: nothing in the product or page makes you wait.
- Windows, not apps: the one idea that separates it from ⌘Tab.
- Small and honest: no accounts, no tracking, no upsell.
