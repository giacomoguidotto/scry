# Domain Docs

Scry uses a single-context documentation layout.

## Read Before Architecture Work

- `CONTEXT.md` for product and codebase language.
- `docs/adr/` for hard-to-reverse decisions, when present.
- `docs/release-setup.md` and `docs/versioning.md` before release or update work.

If one of these files does not exist yet, proceed silently. Create ADRs only when a decision is hard to reverse or likely to be revisited.

## Use Project Language

Use the terms from `CONTEXT.md` in issue titles, refactor plans, tests, and review notes. If a needed term is missing, name the gap instead of inventing a parallel vocabulary.

## Flag Conflicts

If a proposed change contradicts an existing ADR or release rule, surface the conflict explicitly before changing code.
