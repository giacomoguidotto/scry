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
