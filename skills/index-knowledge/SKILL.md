---
name: index-knowledge
description: Generate hierarchical CLAUDE.md knowledge base for a codebase. Creates root + complexity-scored subdirectory documentation.
---

# index-knowledge

Generate hierarchical CLAUDE.md files. Root + complexity-scored subdirectories.

## Usage

```
--create-new   # Read existing → remove all → regenerate from scratch
--max-depth=2  # Limit directory depth (default: 5)
```

Default: Update mode (modify existing + create new where warranted)

---

## Workflow (High-Level)

1. **Discovery + Analysis** (concurrent)
   - Launch parallel Explore agents (multiple Task calls in one message)
   - Main session: bash structure + read existing CLAUDE.md
2. **Score & Decide** - Determine CLAUDE.md locations from merged findings
3. **Generate** - Root first, then subdirs in parallel
4. **Review** - Deduplicate, trim, validate

**TaskCreate ALL phases. Mark in_progress → completed in real-time.**

```
TaskCreate({ subject: "Discovery: fire explore agents + bash structure + read existing", description: "...", activeForm: "Running discovery" })
TaskCreate({ subject: "Scoring: score directories, determine locations", description: "...", activeForm: "Scoring directories" })
TaskCreate({ subject: "Generate: create CLAUDE.md files (root + subdirs)", description: "...", activeForm: "Generating CLAUDE.md files" })
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

Example spawning (all in ONE message for parallel execution):
```
// 500 files, 50k lines, depth 6, 15 large files → spawn additional agents
Task(
  description="large files",
  subagent_type="Explore",
  prompt="Large file analysis: FIND files >500 lines, REPORT complexity hotspots"
)

Task(
  description="deep modules",
  subagent_type="Explore",
  prompt="Deep modules at depth 4+: FIND hidden patterns, internal conventions"
)

Task(
  description="cross-cutting",
  subagent_type="Explore",
  prompt="Cross-cutting concerns: FIND shared utilities across directories"
)
// ... more based on calculation
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

# Existing CLAUDE.md
find . -type f -name "CLAUDE.md" -not -path '*/node_modules/*' 2>/dev/null
```

#### 2. Read Existing CLAUDE.md
```
For each existing file found:
  Read(filePath=file)
  Extract: key insights, conventions, anti-patterns
  Store in EXISTING map
```

If `--create-new`: Read all existing first (preserve context) → then delete all → regenerate.

#### 3. Code Structure Analysis (optional)

If `ast-grep` is available, use it for structural analysis as a supplement:
```bash
# Find exported symbols
ast-grep run --pattern 'export function $NAME($$$PARAMS) { $$$BODY }' .
ast-grep run --pattern 'func $NAME($$$PARAMS) $RET { $$$BODY }' .
```

**Note:** LSP-based analysis (symbol density, reference centrality) is not available. Rely on explore agents + ast-grep + bash analysis instead.

**Merge: bash + existing + Task agent results. Mark discovery task as completed.**

---

## Phase 2: Scoring & Location Decision

**Mark scoring task as in_progress.**

### Scoring Matrix

| Factor | Weight | High Threshold | Source |
|--------|--------|----------------|--------|
| File count | 3x | >20 | bash |
| Subdir count | 2x | >5 | bash |
| Code ratio | 2x | >70% | bash |
| Unique patterns | 1x | Has own config | explore |
| Module boundary | 2x | Has index.ts/__init__.py | bash |

### Decision Rules

| Score | Action |
|-------|--------|
| **Root (.)** | ALWAYS create |
| **>15** | Create CLAUDE.md |
| **8-15** | Create if distinct domain |
| **<8** | Skip (parent covers) |

### Output
```
CLAUDE_MD_LOCATIONS = [
  { path: ".", type: "root" },
  { path: "src/hooks", score: 18, reason: "high complexity" },
  { path: "src/api", score: 12, reason: "distinct domain" }
]
```

**Mark scoring task as completed.**

---

## Phase 3: Generate CLAUDE.md

**Mark generate task as in_progress.**

### Root CLAUDE.md (Full Treatment)

```markdown
# PROJECT KNOWLEDGE BASE

**Generated:** {TIMESTAMP}
**Commit:** {SHORT_SHA}
**Branch:** {BRANCH}

## OVERVIEW
{1-2 sentences: what + core stack}

## STRUCTURE
\`\`\`
{root}/
├── {dir}/    # {non-obvious purpose only}
└── {entry}
\`\`\`

## WHERE TO LOOK
| Task | Location | Notes |
|------|----------|-------|

## CODE MAP
{From ast-grep structural analysis - skip if unavailable or project <10 files}

| Symbol | Type | Location | Role |

## CONVENTIONS
{ONLY deviations from standard}

## ANTI-PATTERNS (THIS PROJECT)
{Explicitly forbidden here}

## UNIQUE STYLES
{Project-specific}

## COMMANDS
\`\`\`bash
{dev/test/build}
\`\`\`

## NOTES
{Gotchas}
```

**Quality gates**: 50-150 lines, no generic advice, no obvious info.

### Subdirectory CLAUDE.md (Parallel)

Launch general-purpose agents for each location in ONE message (parallel execution):

```
// All in single message = parallel
Task(
  description="CLAUDE.md for src/hooks",
  subagent_type="general-purpose",
  prompt="Generate CLAUDE.md for: src/hooks
    - Reason: high complexity
    - 30-80 lines max
    - NEVER repeat parent content
    - Sections: OVERVIEW (1 line), STRUCTURE (if >5 subdirs), WHERE TO LOOK, CONVENTIONS (if different), ANTI-PATTERNS
    - Write directly to src/hooks/CLAUDE.md"
)

Task(
  description="CLAUDE.md for src/api",
  subagent_type="general-purpose",
  prompt="Generate CLAUDE.md for: src/api
    - Reason: distinct domain
    - 30-80 lines max
    - NEVER repeat parent content
    - Sections: OVERVIEW (1 line), STRUCTURE (if >5 subdirs), WHERE TO LOOK, CONVENTIONS (if different), ANTI-PATTERNS
    - Write directly to src/api/CLAUDE.md"
)
// ... one Task per CLAUDE_MD_LOCATIONS entry
```

**Results return directly. Mark generate task as completed.**

---

## Phase 4: Review & Deduplicate

**Mark review task as in_progress.**

For each generated file:
- Remove generic advice
- Remove parent duplicates
- Trim to size limits
- Verify telegraphic style

**Mark review task as completed.**

---

## Final Report

```
=== index-knowledge Complete ===

Mode: {update | create-new}

Files:
  ✓ ./CLAUDE.md (root, {N} lines)
  ✓ ./src/hooks/CLAUDE.md ({N} lines)

Dirs Analyzed: {N}
CLAUDE.md Created: {N}
CLAUDE.md Updated: {N}

Hierarchy:
  ./CLAUDE.md
  └── src/hooks/CLAUDE.md
```

---

## Anti-Patterns

- **Static agent count**: MUST vary agents based on project size/depth
- **Sequential execution**: MUST parallel (multiple Task calls in one message)
- **Ignoring existing**: ALWAYS read existing first, even with --create-new
- **Over-documenting**: Not every dir needs CLAUDE.md
- **Redundancy**: Child never repeats parent
- **Generic content**: Remove anything that applies to ALL projects
- **Verbose style**: Telegraphic or die
