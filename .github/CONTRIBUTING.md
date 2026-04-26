# Contributing

Thanks for wanting to contribute to Scry! Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before getting started.

## Setup

1. Fork and clone the repo. Make sure you have [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [SwiftLint](https://github.com/realm/SwiftLint) installed:

    ```sh
    brew install xcodegen swiftlint
    ```

    > **Optional:** If you use [mise](https://mise.jdx.dev), run `mise install` first to
    > provision the pinned versions from `mise.toml`.

2. Generate the Xcode project and open it:

    ```sh
    cd app
    xcodegen generate
    open Scry.xcodeproj
    ```

3. Build and run with `Cmd+R` in Xcode, or from the command line:

    ```sh
    xcodebuild -scheme Scry -configuration Debug build
    ```

4. Before pushing, run the full CI check locally:

    ```sh
    cd app && xcodegen generate && xcodebuild -scheme Scry -configuration Debug build test && swiftlint
    ```

    This generates the project, builds, runs tests, and lints — the same pipeline as CI.

## Tooling

- **Project generation**: [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the Xcode project is generated from `app/project.yml`
- **Linting**: [SwiftLint](https://github.com/realm/SwiftLint) — config in `app/.swiftlint.yml`
- **Dependencies**: Swift Package Manager (Sparkle, TOMLKit)
- **Auto-updates**: [Sparkle](https://sparkle-project.org)

## Good to know

- **Never edit `Scry.xcodeproj` directly** — it's generated from `app/project.yml` and gitignored. Edit the YAML instead.
- **Re-run `xcodegen generate`** when you add, remove, or rename source files, or change project settings. Code-only changes don't require regeneration.
- **Versions come from git tags** (`v*`), not source files. The CI pipeline auto-tags on main pushes based on conventional commit history.
- **The marketing site** lives in `site/` (Next.js) and also serves the Sparkle appcast. It's a separate concern from the app.

## Conventions

- Branch names: `feat/`, `fix/`, `docs/`, `refactor/`, `test/`, `chore/`
- Commits: [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`)
- `fix:` bumps patch, `feat:` bumps minor — only use when the change genuinely warrants a release
- `feat!:` / `BREAKING CHANGE` bumps major — never use without maintainer approval
