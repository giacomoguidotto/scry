# Issue Tracker

Issues and PRDs for this repo live as GitHub Issues. Use the `gh` CLI for issue operations.

## Commands

- Create: `gh issue create --title "..." --body "..."`
- Read: `gh issue view <number> --comments`
- List: `gh issue list --state open --json number,title,body,labels,comments`
- Comment: `gh issue comment <number> --body "..."`
- Label: `gh issue edit <number> --add-label "..."`
- Close: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically inside the clone.

When a skill says to publish to the issue tracker, create a GitHub issue.
