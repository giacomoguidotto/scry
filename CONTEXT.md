# Scry Context

Scry is a native macOS app that replaces the system Look Up flow with a floating search and answer panel. The product goal is instant, in-place understanding without leaving the current app.

## Terms

- **Scry** - the macOS app and product surface.
- **Trigger** - the user action that opens Scry, currently force-click or the configured hotkey.
- **Look Up** - the built-in macOS behavior Scry asks users to disable because it conflicts with force-click.
- **Search Panel** - the floating native panel shown near the selected text or screen location.
- **Provider** - a search or answer backend surfaced in Scry, such as Google, DuckDuckGo, Wikipedia, AI, or Ollama.
- **Native Result** - a non-AI search result rendered directly in the panel.
- **AI Answer** - the model-generated answer for the user's selected text or screen context.
- **Permission** - a macOS capability Scry needs, especially Accessibility and Screen Recording.
- **Appcast** - the Sparkle update feed served by the Next.js site at `scry.guidotto.dev/appcast.xml`.
- **Release DMG** - the user-installable macOS artifact created by CI and attached to GitHub Releases.

## Boundaries

- The app lives in `app/` and is generated from `app/project.yml`; do not edit `Scry.xcodeproj` directly.
- The marketing site lives in `site/` and serves the Sparkle appcast.
- Versions come from git tags, not source files.
- Architecture decisions that are hard to reverse should be recorded as ADRs under `docs/adr/`.
