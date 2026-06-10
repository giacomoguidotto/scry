# Scry

macOS Swift app built with XcodeGen and SwiftLint.

## Workflow

Run all three checks and fix any failures before considering the task done:

```sh
cd app && xcodegen generate && xcodebuild -scheme Scry -configuration Debug build test && swiftlint
```

The Xcode project is generated from `app/project.yml`. Re-run `xcodegen` from `app/` when you add, remove, or rename source files, or change project settings. Code-only changes do not require regeneration.

## Further reading

- [Versioning & commits](docs/versioning.md)

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: read `CONTEXT.md` and relevant ADRs before architecture work. See `docs/agents/domain.md`.
