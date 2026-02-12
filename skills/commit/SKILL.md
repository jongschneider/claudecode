---
name: commit
description: Create a conventional commit from staged or unstaged changes
---

Create a conventional commit for the current changes.

## Conventional Commit Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `docs` | Documentation only changes |
| `style` | Formatting, missing semicolons, etc. (no logic change) |
| `perf` | Performance improvement |
| `build` | Build system or external dependencies |
| `ci` | CI configuration changes |
| `chore` | Maintenance tasks, tooling, config |
| `revert` | Reverting a previous commit |

### Rules

- **type** is required, lowercase
- **scope** is optional but encouraged — use the package, module, or area changed (e.g. `api`, `auth`, `workvivo`, `graphapi`)
- **description** is required, lowercase, imperative mood ("add" not "added"), no period at end
- **body** is optional — use for explaining *why*, not *what* (the diff shows what)
- Keep description under 72 characters

## Workflow

1. Run `git status` and `git diff --staged` to see what's staged
2. If nothing is staged, run `git diff` to see unstaged changes and ask the user if they want to stage all or select files
3. Analyze the changes to determine:
   - The correct **type** based on what changed
   - An appropriate **scope** from the package/module/directory
   - A concise **description** in imperative mood
4. Present the proposed commit message to the user for approval
5. If the user provides guidance via $ARGUMENTS, use it to inform the type, scope, or description
6. Only commit after user approves the message

## Examples

```
feat(workvivo): add article lifecycle tracking
fix(graphapi): handle nil response from site pages endpoint
refactor(auth): extract token refresh into dedicated handler
test(ingester): add coverage for duplicate message detection
chore(deps): bump common module to v1.4.2
docs(readme): add setup instructions for local development
perf(collector): batch webhook processing to reduce API calls
feat(api)!: change response format for pagination endpoints

BREAKING CHANGE: pagination now uses cursor-based format instead of offset
```

## Guidance

$ARGUMENTS
