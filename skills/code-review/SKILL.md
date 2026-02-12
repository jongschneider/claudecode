---
name: code-review
description: Review changes with parallel reviewer subagents and oracle validation
---

Review the code changes using THREE (3) parallel reviewer subagents and correlate results into a summary ranked by severity. Use the provided user guidance to steer the review and focus on specific code paths, changes, and/or areas of concern.

Guidance: $ARGUMENTS

Review uncommitted changes by default. If no uncommitted changes, review the last commit.

## Step 1: Gather the Diff

```bash
# Check for uncommitted changes first
git diff --stat
git diff --staged --stat
# If no uncommitted changes, use last commit
git log -1 --format="%H %s"
git diff HEAD~1
```

## Step 2: Launch Three Parallel Reviewers

Launch THREE Task agents in a single message for parallel execution. Each gets the full reviewer prompt:

```
Task(
  description="Code review #1",
  subagent_type="general-purpose",
  prompt="You are a code reviewer. Review the following changes for bugs, security issues, and code quality.

**Diffs alone are not enough.** Read the full file(s) being modified to understand context.

Focus on:
- **Bugs**: Logic errors, off-by-one, incorrect conditionals, missing guards, broken error handling, edge cases (null/empty, race conditions), security (injection, auth bypass, data exposure)
- **Structure**: Follows existing patterns? Uses established abstractions? Excessive nesting?
- **Performance**: Only flag if obviously problematic (O(n²) on unbounded data, N+1 queries, blocking I/O on hot paths)

Rules:
- Be certain before flagging — investigate first
- Don't invent hypothetical problems
- Only review the changes, not pre-existing code
- Include file paths and line numbers
- Matter-of-fact tone, no flattery

Review these changes: <paste diff here>"
)
```

Launch all three in ONE message with the same prompt. Each will independently analyze the code.

## Step 3: Correlate Findings

After all three reviewers return:
1. Merge findings, noting which issues were found by multiple reviewers (higher confidence)
2. Deduplicate
3. Rank by severity: critical bugs > security > logic errors > structure > style
4. Produce a unified summary

## Step 4: Oracle Deep Review (MANDATORY — NEVER SKIP)

Launch the @oracle agent to perform a deep review on the correlated findings. Focus the oracle on accuracy and correctness by evaluating the surrounding code, system, subsystems, abstractions, and overall architecture of each item. Apply any recommendations from the oracle to the final summary.

## Step 5: Final Output

Present the final review with findings ranked by severity, incorporating oracle's analysis.

## Pull Request Reviews

If the user provides a pull request URL or identifier, fetch it and review.

### Bitbucket

The `bitbucket` CLI is provided by [bitbucket-mcp](https://github.com/MatanYemini/bitbucket-mcp) wrapped with [mcporter](https://github.com/steipete/mcporter/) to produce a standalone CLI binary.

Parse the URL format `https://bitbucket.org/{workspace}/{repo-slug}/pull-requests/{id}` to extract workspace, repo-slug, and pull-request-id. Then run:
```
bitbucket getPullRequest --workspace <workspace> --repo-slug <repo-slug> --pull-request-id <id>
bitbucket getPullRequestDiff --workspace <workspace> --repo-slug <repo-slug> --pull-request-id <id>
```
Use the PR description from `getPullRequest` for context and the diff from `getPullRequestDiff` for the actual review.

### GitHub

If the user provides a GitHub PR link or number, use `gh` CLI to fetch it.
