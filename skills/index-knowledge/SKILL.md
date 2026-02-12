---
name: index-knowledge
description: Generate project instructions using CLAUDE.md + .claude/rules/. Creates actionable, scoped instructions from codebase analysis.
---

# index-knowledge

Generate actionable project instructions. Root CLAUDE.md + scoped `.claude/rules/*.md` files.

## Usage

```
--create-new   # Read existing → remove all → regenerate from scratch
--max-depth=2  # Limit directory depth for analysis (default: 5)
```

Default: Update mode (modify existing + create new where warranted)

---

## Output Structure

Files follow Claude Code's memory hierarchy:

```
project/
├── CLAUDE.md                    # Project-wide instructions (always created)
└── .claude/
    └── rules/
        ├── api.md               # paths: ["src/api/**/*"]
        ├── hooks.md             # paths: ["src/hooks/**/*"]
        ├── testing.md           # paths: ["**/*.test.*", "**/*.spec.*"]
        └── frontend/
            ├── components.md    # paths: ["src/components/**/*"]
            └── styles.md        # paths: ["src/styles/**/*"]
```

**When to use which:**

| Mechanism | Use for |
|-----------|---------|
| `CLAUDE.md` (root) | Project-wide commands, conventions, structure, anti-patterns |
| `.claude/rules/*.md` with `paths` | Directory/file-scoped conventions that differ from root |
| Subdirectory `CLAUDE.md` | ONLY monorepo packages or truly independent modules |
| `@import` in root | Reference README, package.json, or other existing docs |

---

## Context Loading Model

Understanding what loads when is critical — especially for large monorepos. Every line loaded unconditionally eats context in every session, whether relevant or not.

| File | Loads when | Context cost |
|------|-----------|--------------|
| Root `CLAUDE.md` | **Always** at session start | Every session, every task |
| `.claude/rules/*.md` **without** `paths` | **Always** at session start | Every session, every task |
| `.claude/rules/*.md` **with** `paths` | **Only** when Claude works with matching files | Only relevant sessions |
| Subdirectory `CLAUDE.md` | **Only** when Claude reads files in that directory | Only relevant sessions |
| `@import` targets | When the importing file loads | Follows parent's loading rule |

**Implications for generation:**

- **Root CLAUDE.md must be minimal.** It loads in every session. For a monorepo with 20 packages, root should contain only what's truly universal — not per-package details.
- **`paths` frontmatter is not optional.** A rules file without `paths` is functionally identical to putting that content in root CLAUDE.md — it always loads. Every rules file MUST have `paths` unless the content genuinely applies to all files in the project.
- **Prefer narrow `paths` globs.** `src/api/**/*` is better than `src/**/*`. Overly broad globs defeat the purpose of conditional loading.
- **Monorepo packages get subdirectory CLAUDE.md** because it only loads when Claude enters that package — matching the natural workflow of working in one package at a time.
- **`@import` inherits the parent's loading behavior.** An `@import` in root CLAUDE.md loads unconditionally. An `@import` in a `paths`-gated rules file loads conditionally. Place imports accordingly.

---

## Workflow (High-Level)

1. **Discovery + Analysis** (concurrent)
   - Launch parallel Explore agents (multiple Task calls in one message)
   - Main session: bash structure + read existing memory files
2. **Score & Decide** - Determine rules file locations from merged findings
3. **Generate** - Root CLAUDE.md first, then rules files in parallel
4. **Review** - Deduplicate, trim, validate

**TaskCreate ALL phases. Mark in_progress → completed in real-time.**

```
TaskCreate({ subject: "Discovery: explore agents + bash structure + read existing", description: "...", activeForm: "Running discovery" })
TaskCreate({ subject: "Scoring: score directories, determine rules files", description: "...", activeForm: "Scoring directories" })
TaskCreate({ subject: "Generate: create CLAUDE.md + rules files", description: "...", activeForm: "Generating instruction files" })
TaskCreate({ subject: "Review: deduplicate, validate, trim", description: "...", activeForm: "Reviewing generated files" })
```

---

## Phase 1: Discovery + Analysis (Concurrent)

**Mark discovery task as in_progress.**

### Launch Parallel Explore Agents

Multiple Task calls in a single message execute in parallel. Results return directly.

```
// All Task calls in ONE message = parallel execution

Task(
  description="project structure",
  subagent_type="Explore",
  prompt="Project structure: PREDICT standard patterns for detected language → REPORT deviations only"
)

Task(
  description="entry points",
  subagent_type="Explore",
  prompt="Entry points: FIND main files → REPORT non-standard organization"
)

Task(
  description="conventions",
  subagent_type="Explore",
  prompt="Conventions: FIND config files (.eslintrc, pyproject.toml, .editorconfig) → REPORT project-specific rules"
)

Task(
  description="anti-patterns",
  subagent_type="Explore",
  prompt="Anti-patterns: FIND 'DO NOT', 'NEVER', 'ALWAYS', 'DEPRECATED' comments → LIST forbidden patterns"
)

Task(
  description="build/ci",
  subagent_type="Explore",
  prompt="Build/CI: FIND .github/workflows, Makefile → REPORT non-standard patterns"
)

Task(
  description="test patterns",
  subagent_type="Explore",
  prompt="Test patterns: FIND test configs, test structure → REPORT unique conventions"
)
```

**DYNAMIC AGENT SPAWNING**: After bash analysis, spawn ADDITIONAL Explore agents based on project scale:

| Factor | Threshold | Additional Agents |
|--------|-----------|-------------------|
| **Total files** | >100 | +1 per 100 files |
| **Total lines** | >10k | +1 per 10k lines |
| **Directory depth** | ≥4 | +2 for deep exploration |
| **Large files (>500 lines)** | >10 files | +1 for complexity hotspots |
| **Monorepo** | detected | +1 per package/workspace |
| **Multiple languages** | >1 | +1 per language |

```bash
# Measure project scale first
total_files=$(find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' | wc -l)
total_lines=$(find . -type f \( -name "*.ts" -o -name "*.py" -o -name "*.go" \) -not -path '*/node_modules/*' -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')
large_files=$(find . -type f \( -name "*.ts" -o -name "*.py" \) -not -path '*/node_modules/*' -exec wc -l {} + 2>/dev/null | awk '$1 > 500 {count++} END {print count+0}')
max_depth=$(find . -type d -not -path '*/node_modules/*' -not -path '*/.git/*' | awk -F/ '{print NF}' | sort -rn | head -1)
```

Example additional spawning (all in ONE message):
```
Task(
  description="large files",
  subagent_type="Explore",
  prompt="Large file analysis: FIND files >500 lines, REPORT complexity hotspots and local conventions"
)

Task(
  description="deep modules",
  subagent_type="Explore",
  prompt="Deep modules at depth 4+: FIND hidden patterns, internal conventions"
)

Task(
  description="cross-cutting",
  subagent_type="Explore",
  prompt="Cross-cutting concerns: FIND shared utilities, common patterns across directories"
)
```

### Main Session: Concurrent Analysis

**While Task agents execute**, main session does:

#### 1. Bash Structural Analysis
```bash
# Directory depth + file counts
find . -type d -not -path '*/\.*' -not -path '*/node_modules/*' -not -path '*/venv/*' -not -path '*/dist/*' -not -path '*/build/*' | awk -F/ '{print NF-1}' | sort -n | uniq -c

# Files per directory (top 30)
find . -type f -not -path '*/\.*' -not -path '*/node_modules/*' | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -30

# Code concentration by extension
find . -type f \( -name "*.py" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.go" -o -name "*.rs" \) -not -path '*/node_modules/*' | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -20

# Existing memory files
find . -type f \( -name "CLAUDE.md" -o -name "CLAUDE.local.md" \) -not -path '*/node_modules/*' 2>/dev/null
find .claude/rules -name "*.md" 2>/dev/null

# Detect monorepo
find . -maxdepth 2 -name "package.json" -not -path '*/node_modules/*' 2>/dev/null | head -20
```

#### 2. Read Existing Memory Files
```
For each existing file found (CLAUDE.md, .claude/rules/*.md):
  Read(filePath=file)
  Extract: key insights, conventions, anti-patterns
  Store in EXISTING map
```

If `--create-new`: Read all existing first (preserve context) → then delete all → regenerate.

#### 3. Code Structure Analysis (optional)

If `ast-grep` is available, use it as a supplement:
```bash
ast-grep run --pattern 'export function $NAME($$$PARAMS) { $$$BODY }' .
ast-grep run --pattern 'func $NAME($$$PARAMS) $RET { $$$BODY }' .
```

**Merge: bash + existing + Task agent results. Mark discovery task as completed.**

---

## Phase 2: Scoring & Location Decision

**Mark scoring task as in_progress.**

### Scoring Matrix

Score each directory to determine if it needs its own rules file:

| Factor | Weight | High Threshold | Source |
|--------|--------|----------------|--------|
| File count | 3x | >20 | bash |
| Subdir count | 2x | >5 | bash |
| Code ratio | 2x | >70% | bash |
| Unique conventions | 2x | Differs from root | explore |
| Module boundary | 2x | Has index.ts/__init__.py | bash |
| Own config files | 1x | Has .eslintrc, tsconfig, etc. | explore |

### Decision Rules

| Score | Action |
|-------|--------|
| **Root (.)** | ALWAYS create CLAUDE.md |
| **>15** | Create `.claude/rules/{name}.md` with `paths` frontmatter |
| **8-15** | Create rules file if conventions differ from root |
| **<8** | Skip (root covers it) |
| **Monorepo package** | Create subdirectory CLAUDE.md (not a rules file) |

### Rules File vs Subdirectory CLAUDE.md

- **`.claude/rules/`**: Default choice. Centrally organized, supports glob patterns, auto-loaded when Claude works with matching files.
- **Subdirectory CLAUDE.md**: Only for monorepo packages or modules with their own build/test/deploy lifecycle. These are truly independent sub-projects.

### Context Budget (Monorepo)

For monorepos, track the unconditionally-loaded set — everything that loads in every session regardless of what the user is working on:

```
ALWAYS_LOADED = root CLAUDE.md + any rules file WITHOUT paths
TARGET: always-loaded set ≤ 80 lines total

CONDITIONALLY_LOADED = rules files WITH paths + subdirectory CLAUDE.md
No hard limit, but each file should still be 15-50 lines.
```

If the always-loaded set exceeds 80 lines, move content into `paths`-gated rules files. Ask: "Does a developer working on package X need to see this?" If no, it doesn't belong in root.

### Output
```
INSTRUCTION_FILES = [
  { path: "CLAUDE.md", type: "root" },
  { path: ".claude/rules/api.md", paths: ["src/api/**/*"], reason: "distinct REST conventions" },
  { path: ".claude/rules/hooks.md", paths: ["src/hooks/**/*"], reason: "complex state patterns" },
  { path: ".claude/rules/testing.md", paths: ["**/*.test.*", "**/*.spec.*"], reason: "unique test conventions" },
  { path: "packages/worker/CLAUDE.md", type: "monorepo-package", reason: "independent deploy target" }
]
```

**Mark scoring task as completed.**

---

## Phase 3: Generate Files

**Mark generate task as in_progress.**

### Root CLAUDE.md

Every line is an actionable instruction or essential context. Not documentation.

```markdown
# {Project Name}

{1-2 sentences: what this project is + core stack}

See @README.md for full project context.

## Commands
\`\`\`bash
{dev command}
{test command}
{build command}
{lint command}
\`\`\`

## Structure
\`\`\`
{root}/
├── {dir}/    # {non-obvious purpose only}
└── {entry}
\`\`\`

## Where to Look
| Task | Location |
|------|----------|
| {common task} | {path} |

## Conventions
- {Only deviations from language/framework defaults}
- {Project-specific naming, patterns, idioms}

## Do Not
- {Explicitly forbidden patterns in this project}
- {Common mistakes specific to this codebase}

## Gotchas
- {Non-obvious behaviors, tricky setup steps, known sharp edges}
```

**Quality gates:**
- 40-120 lines (monorepo: aim for 40-80 — this loads in EVERY session)
- Every line is an actionable instruction or essential context
- No generic advice ("write clean code", "use meaningful names")
- No information Claude discovers by reading source (no symbol tables, no API inventories)
- Use `@import` to reference existing docs rather than duplicating content
- Omit any section that would be empty
- **Monorepo**: Aggressively push package-specific content into `paths`-gated rules files or subdirectory CLAUDE.md. Root should only contain cross-package universals (repo-wide commands, shared conventions, monorepo tooling).

### Rules Files (Parallel)

Launch general-purpose agents for each rules file in ONE message:

```
Task(
  description="rules for src/api",
  subagent_type="general-purpose",
  prompt="Generate .claude/rules/api.md for this project.

    MUST include paths frontmatter:
    ---
    paths:
      - \"src/api/**/*\"
    ---

    Content requirements:
    - 15-50 lines max
    - NEVER repeat what's in root CLAUDE.md
    - Only conventions/anti-patterns SPECIFIC to these files
    - Every line is an actionable instruction
    - Sections: brief purpose (1 line), conventions, anti-patterns, gotchas
    - Omit empty sections
    - Write directly to .claude/rules/api.md"
)

Task(
  description="rules for testing",
  subagent_type="general-purpose",
  prompt="Generate .claude/rules/testing.md for this project.

    MUST include paths frontmatter:
    ---
    paths:
      - \"**/*.test.*\"
      - \"**/*.spec.*\"
      - \"tests/**/*\"
    ---

    Content requirements:
    - 15-50 lines max
    - NEVER repeat root CLAUDE.md content
    - Test-specific conventions, fixtures, patterns, common mistakes
    - Omit empty sections
    - Write directly to .claude/rules/testing.md"
)
```

### Monorepo Package CLAUDE.md (if applicable)

For true monorepo packages only — independent sub-projects with own lifecycle:

```
Task(
  description="CLAUDE.md for packages/worker",
  subagent_type="general-purpose",
  prompt="Generate CLAUDE.md for packages/worker (monorepo package).
    - Independent sub-project with own build/test lifecycle
    - 30-80 lines max
    - Include: commands, conventions, anti-patterns, gotchas
    - NEVER repeat root CLAUDE.md content
    - Use @import for package-local docs if they exist
    - Write directly to packages/worker/CLAUDE.md"
)
```

**Mark generate task as completed.**

---

## Phase 4: Review & Deduplicate

**Mark review task as in_progress.**

For each generated file:
- Remove generic advice (anything true of ALL projects of this type)
- Remove root duplicates from rules files
- Verify `paths` frontmatter on every rules file is correct and specific
- Verify `paths` globs are narrow (prefer `src/api/**/*` over `src/**/*`)
- Trim to size limits (root: 40-120, rules: 15-50, monorepo CLAUDE.md: 30-80)
- Verify every line is actionable (instruction or essential context, not documentation)
- Ensure `.claude/rules/` directory exists before writing rules files
- Confirm `@import` targets exist
- Omit sections that ended up empty after dedup

**Context budget check (especially monorepos):**
- Sum lines of root CLAUDE.md + any rules files without `paths` = always-loaded set
- If always-loaded set > 80 lines: move package/domain-specific content into `paths`-gated files
- For each line in root, ask: "Is this relevant to ALL packages?" If no → move to a rules file with `paths`

**Mark review task as completed.**

---

## Final Report

```
=== index-knowledge Complete ===

Mode: {update | create-new}

Files:
  ✓ ./CLAUDE.md (root, {N} lines)
  ✓ ./.claude/rules/api.md ({N} lines, paths: src/api/**/*)
  ✓ ./.claude/rules/testing.md ({N} lines, paths: **/*.test.*)

Dirs Analyzed: {N}
Files Created: {N}
Files Updated: {N}

Context Budget:
  Always loaded: {N} lines (root + ungated rules)
  Conditionally loaded: {N} lines across {N} files

Structure:
  ./CLAUDE.md
  ./.claude/rules/
  ├── api.md          → src/api/**/*
  ├── testing.md      → **/*.test.*
  └── hooks.md        → src/hooks/**/*
```

---

## Anti-Patterns

- **Static agent count**: MUST vary agents based on project size/depth
- **Sequential execution**: MUST parallel (multiple Task calls in one message)
- **Ignoring existing**: ALWAYS read existing first, even with --create-new
- **Over-documenting**: Most dirs don't need their own rules file
- **Redundancy**: Rules files never repeat root content
- **Generic content**: Remove anything that applies to ALL projects of this type
- **Verbose style**: Telegraphic — every line earns its place
- **Documentation over instructions**: CLAUDE.md tells Claude what to DO, not what things ARE
- **Symbol tables / code maps**: Claude discovers these by reading source — don't cache stale data
- **Subdirectory CLAUDE.md for everything**: Use `.claude/rules/` with `paths`; reserve subdirectory CLAUDE.md for monorepo packages only
- **Missing paths frontmatter**: Every `.claude/rules/` file MUST have `paths` (unless it truly applies globally)
- **Stale metadata**: No timestamps, commit SHAs, or branch names — these waste context and go stale immediately
- **Context bloat in monorepos**: Root CLAUDE.md loads in EVERY session. Package-specific content in root wastes context for developers working on unrelated packages. Always-loaded set should be ≤ 80 lines.
- **Broad path globs**: `src/**/*` matches too much — use `src/api/**/*` or narrower. Overly broad globs defeat conditional loading.
