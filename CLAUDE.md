# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the Korero for Claude Code repository - a multi-agent ideation and development system that enables continuous development cycles with intelligent exit detection and rate limiting. Korero supports four modes: a **Continuous Coding Loop** (ideation + implementation + git commits), a **Continuous Idea Loop** (ideation + debate only, saves best idea to disk), a **Heavy Coding Loop** (Claude + Codex parallel execution + cross-AI debate + implementation), and a **Heavy Idea Loop** (Claude + Codex parallel execution + cross-AI debate, saves best idea).

See [README.md](README.md) for version info, changelog, and user documentation.

## Core Architecture

The system consists of four main bash scripts and a modular library system:

### Main Scripts

1. **korero_loop.sh** - The main autonomous loop that executes Claude Code repeatedly
2. **korero_monitor.sh** - Live monitoring dashboard for tracking loop status
3. **setup.sh** - Project initialization script for new Korero projects
4. **create_files.sh** - Bootstrap script that creates the entire Korero system
5. **korero_import.sh** - PRD/specification import tool that converts documents to Korero format
   - Uses modern Claude Code CLI with `--output-format json` for structured responses
   - Implements `detect_response_format()` and `parse_conversion_response()` for JSON parsing
   - Backward compatible with older CLI versions (automatic text fallback)
6. **korero_enable.sh** - Interactive wizard for enabling Korero in existing projects
   - 7-phase wizard: Environment Detection → Mode Selection → Subject & Agents → Task Source → Configuration → File Generation → Verification
   - **Mode selection**: Continuous Coding Loop or Continuous Idea Loop
   - **Agent generation**: Auto-generate domain experts via Claude Code CLI, enter roles manually, or use generic agents
   - **Configurable agent count** (1-10 domain agents) plus 3 mandatory evaluation agents
   - **Loop limit configuration**: 10, 20, 50, or continuous
   - Imports tasks from beads, GitHub Issues, or PRD documents (coding mode only)
   - Generates `.korerorc` project configuration file
7. **korero_enable_ci.sh** - Non-interactive version for CI/automation
   - Same functionality as interactive version with CLI flags
   - New flags: `--mode`, `--subject`, `--agents`, `--loops`
   - JSON output mode for machine parsing
   - Exit codes: 0 (success), 1 (error), 2 (already enabled)

### Library Components (lib/)

The system uses a modular architecture with reusable components in the `lib/` directory:

1. **lib/circuit_breaker.sh** - Circuit breaker pattern implementation
   - Prevents runaway loops by detecting stagnation
   - Three states: CLOSED (normal), HALF_OPEN (monitoring), OPEN (halted)
   - Configurable thresholds for no-progress and error detection
   - Automatic state transitions and recovery

2. **lib/response_analyzer.sh** - Intelligent response analysis
   - Analyzes Claude Code output for completion signals
   - **JSON output format detection and parsing** (with text fallback)
   - Supports both flat JSON format and Claude CLI format (`result`, `sessionId`, `metadata`)
   - Extracts structured fields: status, exit_signal, work_type, files_modified
   - **Session management**: `store_session_id()`, `get_last_session_id()`, `should_resume_session()`
   - Automatic session persistence to `.korero/.claude_session_id` file with 24-hour expiration
   - Session lifecycle: `get_session_id()`, `reset_session()`, `log_session_transition()`, `init_session_tracking()`
   - Session history tracked in `.korero/.korero_session_history` (last 50 transitions)
   - Session auto-reset on: circuit breaker open, manual interrupt, project completion
   - Detects test-only loops and stuck error patterns
   - Two-stage error filtering to eliminate false positives
   - Multi-line error matching for accurate stuck loop detection
   - Confidence scoring for exit decisions
   - **Permission denial handling**: Interactive recovery with auto-apply capability
   - `prompt_permission_fix()` - Interactive prompt for permission recovery (auto-updates .korerorc)
   - `apply_permission_fix()` - Updates ALLOWED_TOOLS in .korerorc (creates backup)
   - `merge_tool_permissions()` - Merges tool permissions avoiding duplicates
   - `suggest_permission_fix()` - Maps commands to ALLOWED_TOOLS patterns (e.g., `npm install` → `Bash(npm *)`)
   - `format_permission_denial_message()` - Formats actionable fix messages with preset alternatives
   - **Visual configuration diff**: Colorized before/after display for `.korerorc` changes
   - `show_config_diff()` - Pure display: RED for removed, GREEN for added, YELLOW for no-change; shows preset expansion
   - `confirm_config_change()` - Wraps `show_config_diff()` with y/N confirmation prompt (for contexts without prior menu)

3. **lib/date_utils.sh** - Cross-platform date utilities
   - ISO timestamp generation for logging
   - Epoch time calculations for rate limiting

4. **lib/timeout_utils.sh** - Cross-platform timeout command utilities
   - Detects and uses appropriate timeout command for the platform
   - Linux: Uses standard `timeout` from GNU coreutils
   - macOS: Uses `gtimeout` from Homebrew coreutils
   - `portable_timeout()` function for seamless cross-platform execution
   - Automatic detection with caching for performance

5. **lib/enable_core.sh** - Shared logic for korero enable commands
   - Configuration validation: `validate_korerorc()` - line-by-line validation, `validate_korerorc_verbose()` - rich per-field checkmark output
   - Quick Start: `run_quickstart_wizard()` - streamlined 3-question setup for new users
   - Idempotency checks: `check_existing_korero()`, `is_korero_enabled()`
   - Safe file operations: `safe_create_file()`, `safe_create_dir()`
   - Project detection: `detect_project_context()`, `detect_git_info()`, `detect_task_sources()`
   - Standard template generation: `generate_prompt_md()`, `generate_agent_md()`, `generate_fix_plan_md()`, `generate_korerorc()`
   - **Context-aware project analysis**:
     - `gather_project_context()` - Collects directory tree, README, package manifest, source file inventory
     - `generate_context_aware_config()` - Sends project context to Claude CLI, returns structured config (agents, categories, scoring, key files, project summary, focus constraint, notes)
   - **Ideation template generation** (MMMlight quality — uses CONFIG_* globals from context-aware config):
     - `generate_domain_agents()` - Auto-generates domain expert agents via Claude Code CLI
     - `_generate_generic_agents()` - Returns generic agents from predefined pool
     - `_generate_agents_from_roles()` - Creates agents from comma-separated role names
     - `generate_ideation_prompt_md()` - Full 4-phase workflow with scoring criteria, categories, anti-repetition rules, key files reference, winning idea output format with ═══ separators
     - `generate_ideation_agent_md()` - Agent table, debate rules, scoring criteria, output location instructions
     - `generate_ideation_fix_plan_md()` - Pre-built tracker tables, category coverage, type balance, per-loop checklists with checkpoints
     - `generate_ideation_ideas_md()` - Project-specific IDEAS.md header
   - **Configuration preview**: `preview_korerorc_changes(new_content, interactive)` - Field-by-field diff when overwriting existing `.korerorc`; prompts for confirmation in interactive mode
   - **Diversity tracking**: `generate_diversity_stats(ideas_dir)` - Scans idea files for `**Category:**` fields, produces compact text summary with per-category counts, overrepresentation warnings, and diversity alerts
   - **Config fix commands**: `get_config_fix(field, korerorc)` - Returns copy-paste shell command to fix a missing/invalid field
   - **Config validation with fixes**: `validate_korerorc_with_fixes(korerorc)` - Validates config and outputs actionable fix commands for each error

6. **lib/wizard_utils.sh** - Interactive prompt utilities for enable wizard
   - User prompts: `confirm()`, `prompt_text()`, `prompt_number()`
   - Selection utilities: `select_option()`, `select_multiple()`, `select_with_default()`
   - Output formatting: `print_header()`, `print_bullet()`, `print_success/warning/error/info()`

7. **lib/task_sources.sh** - Task import from external sources
   - Beads integration: `check_beads_available()`, `fetch_beads_tasks()`, `get_beads_count()`
   - GitHub integration: `check_github_available()`, `fetch_github_tasks()`, `get_github_issue_count()`
   - PRD extraction: `extract_prd_tasks()`, supports checkbox and numbered list formats
   - Task normalization: `normalize_tasks()`, `prioritize_tasks()`, `import_tasks_from_sources()`

8. **lib/permission_presets.sh** - Named permission template presets
   - Three presets: `@conservative` (Read/Write/Edit), `@standard` (+ git, npm, pytest), `@permissive` (all Bash)
   - `expand_tool_preset()` - Expands single `@name` to tool list
   - `expand_allowed_tools()` - Splits by comma, expands `@`-prefixed items, passes through others
   - `list_presets()` - Displays available presets with usage examples
   - Mixed presets + custom tools: `@standard,Bash(docker *)`

9. **lib/debate_transcript.sh** - Debate transcript generation for ideation loops
   - `init_debate_transcript(loop_num)` - Creates timestamped transcript file in `.korero/debates/`
   - `append_transcript_section(loop_num, section_name, content)` - Appends a named section (auto-creates if missing)
   - `finalize_debate_transcript(loop_num, winner)` - Marks transcript complete and records winning idea
   - `get_latest_debate_loop()` - Returns highest loop number from debates directory
   - `show_debate_transcript(loop_num|"latest")` - Displays transcript content; resolves "latest" automatically
   - `list_debate_transcripts()` - Lists all available transcripts with status indicators

10. **lib/health_check.sh** - Environment prerequisite validation
    - `check_bash_version()` - Validates Bash 4.0+ requirement; shows platform-specific upgrade instructions; returns 3 on failure
    - `run_health_check()` - Runs all checks (including bash version) and prints formatted report; exits 0 (all pass) or N (issues found)
    - `check_tool(cmd, name, hint)` - Checks if a CLI tool is installed; shows version or install hint
    - `check_timeout_tool()` - Checks for `timeout` or `gtimeout` (cross-platform)
    - `check_git_config()` - Validates `git config user.name` and `user.email` are set
    - `check_permissions()` - Checks `.korero/` directory write access
    - `check_network()` - Tests connectivity to `api.anthropic.com` via curl (5s timeout)
    - `check_config()` - Validates `.korerorc` bash syntax via `bash -n`
    - `check_codex_tool()` - Checks if Codex CLI is installed; shows version (heavy modes only)
    - `check_codex_auth_health()` - Verifies `~/.codex/auth.json` or `codex login status` (heavy modes only)
    - `check_codex_network()` - Tests connectivity to `api.openai.com` via curl (heavy modes only)

11. **lib/codex_adapter.sh** - Codex CLI integration for heavy modes
    - `check_codex_ready()` - Returns 0 (ready), 1 (not installed), 2 (not authenticated)
    - `check_codex_auth()` - Checks `~/.codex/auth.json` exists or `codex login status` passes
    - `run_codex_login(method)` - Runs OAuth login via `device` (device-auth), `browser`, or `api-key` method
    - `build_codex_command(prompt, mode, output_path)` - Populates `CODEX_CMD_ARGS` array with `codex exec --json --sandbox read-only`
    - `parse_codex_response(ndjson_file, last_message_file, result_file)` - Creates normalized JSON at `.korero/.codex_parse_result`
    - `extract_codex_proposal(last_message_file)` - Returns final proposal text on stdout
    - `should_fallback_to_claude()` - Checks `CODEX_FALLBACK` env and Codex readiness; returns 0 (should fallback) with reason on stdout, 1 (Codex ready)
    - `display_fallback_warning(reason, fallback_mode)` - Shows fallback warning to stderr; suppressed in "silent" mode

12. **lib/cross_ai_debate.sh** - Cross-AI debate orchestrator for heavy modes
    - `run_cross_ai_debate(claude_file, codex_file, loop_num, mode, project, rounds)` - Orchestrates 3-round debate, writes `.korero/.debate_result`
    - `build_critique_prompt(own, other, ai_name, other_name, project)` - Generates critique prompt from template
    - `build_defense_prompt(own, critique, ai_name, other_name, project)` - Generates defense prompt from template
    - `build_judge_prompt(6 artifacts, mode, project)` - Generates judgment prompt with scoring criteria (truncates artifacts to 2000 chars)
    - `parse_debate_verdict(judge_output, result_file)` - Extracts winner from `---DEBATE_VERDICT---` block, defaults to claude on failure
    - `get_debate_winner()` - Returns winner from `.korero/.debate_result`
    - `get_phase_icon(phase)` - Returns ASCII icon for debate phase (proposal, critique, defense, judgment, complete, error)
    - `show_debate_progress(phase, status, detail, elapsed)` - Streams colorized progress indicator to stderr with phase name, status, timing
    - `show_debate_summary(winner, title, confidence, total_time)` - Displays formatted debate completion box with winner info

13. **lib/cost_estimator.sh** - API cost estimation from loop logs
    - `estimate_tokens_from_file(file_path)` - Estimates token count from file size (4 chars/token)
    - `calculate_cost(tokens, rate)` - Calculates USD cost for given tokens at per-1M rate
    - `estimate_api_costs(log_dir)` - Scans log directory and returns JSON cost breakdown (input/output tokens, costs, files analyzed)
    - `display_cost_report(log_dir)` - Displays formatted cost dashboard with token usage, cost breakdown, and pricing info

## Key Commands

### Installation
```bash
# Install Korero globally (run once)
./install.sh

# Uninstall Korero
./install.sh uninstall
```

### Setting Up a New Project
```bash
# Create a new Korero-managed project (run from anywhere)
korero-setup my-project-name
cd my-project-name
```

### Migrating Existing Projects
```bash
# Migrate from flat structure to .korero/ subfolder (v0.10.0+)
cd existing-project
korero-migrate
```

### Enabling Korero in Existing Projects
```bash
# Interactive wizard (recommended for humans)
cd existing-project
korero-enable

# Idea loop for a specific domain
korero-enable --mode idea --subject "data analysis tool" --agents 4

# Coding loop with limited iterations
korero-enable --mode coding --subject "web app" --loops 20

# With specific task source
korero-enable --from beads
korero-enable --from github --label "sprint-1"
korero-enable --from prd ./docs/requirements.md

# Heavy mode with dual-AI parallel execution
korero-enable --mode heavy-coding --subject "web app"
korero-enable --mode heavy-idea --subject "ML pipeline" --agents 5

# Force overwrite existing .korero/
korero-enable --force

# Non-interactive for CI/scripts
korero-enable-ci                              # Sensible defaults
korero-enable-ci --mode idea --subject "ML pipeline" --agents 5 --loops 10
korero-enable-ci --mode heavy-coding          # Heavy mode (requires Codex auth)
korero-enable-ci --from github               # With task source
korero-enable-ci --project-type typescript   # Override detection
korero-enable-ci --json                      # Machine-readable output
```

### Running the Korero Loop
```bash
# Start with integrated tmux monitoring (recommended)
korero --monitor

# Start without monitoring
korero

# With custom parameters and monitoring
korero --monitor --calls 50 --prompt my_custom_prompt.md

# Check current status
korero --status

# Dry run - show what would happen without executing
korero --dry-run

# Configuration validation
korero --validate

# Inline help topics
korero --help presets         # Permission preset details
korero --help circuit-breaker # Circuit breaker states and thresholds
korero --help config          # .korerorc configuration reference

# Quick start for new users (3-question setup)
korero --quickstart

# Start coding from an ideation idea
korero --start-idea 5         # Create branch from loop 5's winning idea

# Verbose config validation with per-field checkmarks
korero --validate-config

# Auto-fix missing/invalid config fields
korero --fix-config

# Example workflow gallery (interactive menu)
korero --examples

# View debate transcripts from ideation loops
korero --show-debate          # Show latest debate transcript
korero --show-debate 5        # Show transcript from loop 5

# Environment health check
korero --health-check            # Validate all prerequisites
korero --health-check || exit 1  # Use in CI to fail fast

# API cost estimation
korero --cost-estimate           # Show estimated API costs from logs

# Troubleshooting
korero --troubleshoot            # Quick reference for common issues and fixes

# Circuit breaker management
korero --reset-circuit
korero --circuit-status

# Session management
korero --reset-session    # Reset session state manually
```

### Monitoring
```bash
# Integrated tmux monitoring (recommended)
korero --monitor

# Manual monitoring in separate terminal
korero-monitor

# tmux session management
tmux list-sessions
tmux attach -t <session-name>
```

Each loop iteration displays a visual progress indicator:
```
[████████░░] 80% | Loop 8 | Phase: Executing (8/10)
```
When `MAX_LOOPS` is set to a number, the bar shows completion percentage. In continuous mode, it shows 0% with the current loop number.

### Running Tests
```bash
# Run all tests (sequential, works everywhere)
npm test

# Parallel execution (requires flock — CI uses this automatically)
npm run test:parallel

# Sequential fallback for debugging
npm run test:sequential

# Run specific test suites
npm run test:unit
npm run test:integration

# Run individual test files
bats tests/unit/test_cli_parsing.bats
bats tests/unit/test_json_parsing.bats
bats tests/unit/test_cli_modern.bats
bats tests/unit/test_enable_core.bats
bats tests/unit/test_task_sources.bats
bats tests/unit/test_korero_enable.bats
```

> **CI Note:** GitHub Actions runs tests in parallel via `bats --jobs $(nproc)` for ~50% faster feedback. Locally, `npm test` runs sequentially for compatibility.

## Korero Loop Configuration

The loop is controlled by several key files and environment variables within the `.korero/` subfolder:

- **.korero/PROMPT.md** - Main prompt file that drives each loop iteration
- **.korero/fix_plan.md** - Prioritized task list that Korero follows
- **.korero/AGENT.md** - Build and run instructions maintained by Korero
- **.korero/status.json** - Real-time status tracking (JSON format)
- **.korero/logs/** - Execution logs for each loop iteration

### Rate Limiting
- Default: 100 API calls per hour (configurable via `--calls` flag)
- Automatic hourly reset with countdown display
- Call tracking persists across script restarts

### Modern CLI Configuration (Phase 1.1)

Korero uses modern Claude Code CLI flags for structured communication:

**Configuration Variables:**
```bash
CLAUDE_OUTPUT_FORMAT="json"           # Output format: json (default) or text
CLAUDE_ALLOWED_TOOLS="@standard"      # Preset or explicit tool permissions
CLAUDE_USE_CONTINUE=true              # Enable session continuity
CLAUDE_MIN_VERSION="2.0.76"           # Minimum Claude CLI version
```

**Permission Presets:**
| Preset | Expands To |
|--------|-----------|
| `@conservative` | `Write,Read,Edit` |
| `@standard` | `Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)` |
| `@permissive` | `Write,Read,Edit,Bash(*)` |

Presets can be mixed with custom tools: `@standard,Bash(docker *)`

**CLI Options:**
- `--output-format json|text` - Set Claude output format (default: json)
- `--allowed-tools "Write,Read,Bash(git *)"` - Restrict allowed tools
- `--no-continue` - Disable session continuity, start fresh each loop
- `--help <topic>` - Show detailed help on a specific topic (presets, circuit-breaker, session, tools, modes, exit-detection, rate-limiting, config)
- `--start-idea N` - Create a feature branch from winning idea N and start coding loop
- `--quickstart` - Quick 3-question setup wizard for new users (mode, project description, permissions)
- `--validate-config` - Verbose configuration validation with per-field success/error checkmarks
- `--fix-config` - Apply default fixes for missing/invalid `.korerorc` fields (adds ALLOWED_TOOLS, KORERO_MODE, MAX_LOOPS with sensible defaults)
- `--examples` - Interactive example workflow gallery with 7 project-type templates
- `--show-debate [N]` - Display debate transcript from loop N (or latest if N omitted)
- `--health-check` - Validate all prerequisites (Claude CLI, jq, git, permissions, network, config)
- `--cost-estimate` - Estimate API costs from loop log files and display formatted report
- `--troubleshoot` / `--troubleshooting` - Show categorized troubleshooting quick reference with common issues and fix commands
- `--codex-timeout NUM` - Set Codex execution timeout in minutes (1-120, heavy modes only)
- `--debate-rounds NUM` - Set number of cross-AI debate rounds (1-3, heavy modes only)

**Loop Context:**
Each loop iteration injects context via `build_loop_context()`:
- Current loop number
- Remaining tasks from fix_plan.md
- Category diversity stats (per-category counts, overrepresentation warnings)
- Idea context (when started via `--start-idea`)
- Circuit breaker state (if not CLOSED)
- Previous loop work summary
- Previous debate winner info (heavy modes only)

**Session Continuity:**
- Sessions are preserved in `.korero/.claude_session_id`
- Use `--continue` flag to maintain context across loops
- Disable with `--no-continue` for isolated iterations

### Multi-Agent Ideation System

Korero supports four loop modes configured via `korero-enable` or `.korerorc`:

**Modes:**
- **`coding`** - Ideation → Debate → Implementation → Git Commit (default)
- **`idea`** - Ideation → Debate → Save Best Idea (no code changes)
- **`heavy-coding`** - Claude + Codex parallel execution → Cross-AI debate → Claude implements winner + git commit
- **`heavy-idea`** - Claude + Codex parallel execution → Cross-AI debate → Save winning idea (no code changes)

**Agent Architecture:**
- **Domain Agents** (1-10, user-configurable): Auto-generated experts based on project subject, or manually specified roles
- **3 Mandatory Evaluation Agents** (always present): Devil's Advocate, Technical Feasibility Analyst, Idea Orchestrator

**Debate Protocol (PROMPT.md):**
1. **Phase 1: Idea Generation** - Each domain agent proposes ONE improvement
2. **Phase 2: Structured Debate** - 3 rounds: Evaluation → Rebuttal → Final Selection
3. **Phase 3: Implementation** (coding mode only) - Implement winning idea + git commit

**Idea Storage:**
- Each loop's winning idea is extracted from the `KORERO_IDEA` output block
- Individual ideas saved to `.korero/ideas/loop_N_idea.md`
- Cumulative index maintained in `.korero/ideas/IDEAS.md`

**Loop Limits:**
- Configured via `MAX_LOOPS` in `.korerorc` (number or "continuous")
- Loop exits gracefully when limit is reached

**`.korerorc` Ideation Fields:**
```bash
KORERO_MODE="idea"               # Loop mode: coding, idea, heavy-coding, or heavy-idea
PROJECT_SUBJECT="data analysis"  # Subject for agent generation
DOMAIN_AGENT_COUNT=3             # Number of domain agents
MAX_LOOPS="continuous"           # Loop limit: number or continuous
```

**`.korerorc` Heavy Mode Fields** (only used for `heavy-coding` / `heavy-idea`):
```bash
CODEX_TIMEOUT=15                 # Codex execution timeout in minutes (1-120)
CODEX_APPROVAL="never"          # Codex approval mode: never | on-request
DEBATE_ROUNDS=2                  # Cross-AI debate rounds (1-3)
CODEX_FALLBACK="claude-only"    # Fallback when Codex unavailable: fail | claude-only | silent
```

### Heavy Mode Architecture

Heavy modes run Claude Code and OpenAI Codex CLI in parallel each loop, then orchestrate a cross-AI debate:

**Debate Flow (3 rounds, 5 extra API calls per loop):**
1. **Round 1: Mutual Critique** (parallel) — Each AI critiques the other's proposal
2. **Round 2: Defense** (parallel) — Each AI defends its proposal against the critique
3. **Round 3: Judgment** (Claude only) — Claude evaluates all 6 artifacts and selects a winner

**Scoring Rubric:** User Impact (30%), Technical Feasibility (25%), Debate Performance (20%), Implementation Clarity (15%), Risk Management (10%)

**Fallback Behavior:**
- If one AI fails, the surviving AI's proposal is used directly (debate skipped)
- If both AIs fail, the loop exits with an error
- Codex always runs in `--sandbox read-only`; only Claude implements the winner
- **CODEX_FALLBACK modes**: `fail` (default, halt on Codex error), `claude-only` (auto-fallback with warning), `silent` (auto-fallback without output)
- Fallback is checked at the start of `run_cross_ai_debate()` via `should_fallback_to_claude()` before any API calls
- Fallback result includes `"fallback": true` and `"fallback_reason"` in `.korero/.debate_result`

**Streaming Progress Indicators:**
Each debate phase outputs real-time progress to stderr with colorized status, phase icons, and elapsed time:
```
[*] Critique [IN PROGRESS] — Claude + Codex critiquing in parallel
[+] Critique [DONE] (42s) — Both critiques received
[#] Defense [IN PROGRESS] — Claude + Codex defending in parallel
[+] Defense [DONE] (38s) — Both defenses received
[=] Judgment [IN PROGRESS] — Claude evaluating all artifacts
[+] Judgment [DONE] (15s) — Verdict received
╔══════════════════════════════════════════════════╗
║  DEBATE COMPLETE                                 ║
╠══════════════════════════════════════════════════╣
║  Winner:     Claude
║  Idea:       Add streaming support
║  Confidence: 85%
║  Duration:   95s
╚══════════════════════════════════════════════════╝
```

**Key Files:**
- `.korero/.debate_result` — JSON with winner, title, confidence, rationale
- `.korero/debates/loop_N.md` — Full debate transcript per loop
- `templates/heavy_debate_prompts/` — Critique, defense, and judge prompt templates

### Intelligent Exit Detection
The loop uses a dual-condition check to prevent premature exits during productive iterations:

**Exit requires BOTH conditions:**
1. `recent_completion_indicators >= 2` (heuristic-based detection from natural language patterns)
2. Claude's explicit `EXIT_SIGNAL: true` in the KORERO_STATUS block

The `EXIT_SIGNAL` value is read from `.korero/.response_analysis` (at `.analysis.exit_signal`) which is populated by `response_analyzer.sh` from Claude's KORERO_STATUS output block.

**Other exit conditions (checked before completion indicators):**
- Multiple consecutive "done" signals from Claude Code (`done_signals >= 2`)
- Too many test-only loops indicating feature completeness (`test_loops >= 3`)
- All items in .korero/fix_plan.md marked as completed

**Example behavior when EXIT_SIGNAL is false:**
```
Loop 5: Claude outputs "Phase complete, moving to next feature"
        → completion_indicators: 3 (high confidence from patterns)
        → EXIT_SIGNAL: false (Claude explicitly says more work needed)
        → Result: CONTINUE (respects Claude's explicit intent)

Loop 8: Claude outputs "All tasks complete, project ready"
        → completion_indicators: 4
        → EXIT_SIGNAL: true (Claude confirms project is done)
        → Result: EXIT with "project_complete"
```

**Rationale:** Natural language patterns like "done" or "complete" can trigger false positives during productive work (e.g., "feature done, moving to tests"). By requiring Claude's explicit EXIT_SIGNAL confirmation, Korero avoids exiting mid-iteration when Claude is still working.

## CI/CD Pipeline

Korero uses GitHub Actions for continuous integration:

### Workflows (`.github/workflows/`)

1. **test.yml** - Main test suite
   - Runs on push to `main`/`develop` and PRs to `main`
   - Executes unit, integration, and E2E tests
   - Coverage reporting with kcov (informational only)
   - Uploads coverage artifacts

2. **claude.yml** - Claude Code GitHub Actions integration
   - Automated code review capabilities

3. **claude-code-review.yml** - PR code review workflow
   - Automated review on pull requests

### Coverage Note
Bash code coverage measurement with kcov has fundamental limitations when tracing subprocess executions. The `COVERAGE_THRESHOLD` is set to 0 (disabled) because kcov cannot instrument subprocesses spawned by bats. **Test pass rate (100%) is the quality gate.** See [bats-core#15](https://github.com/bats-core/bats-core/issues/15) for details.

## Project Structure for Korero-Managed Projects

Each project created with `./setup.sh` follows this structure with a `.korero/` subfolder:
```
project-name/
├── .korero/                # Korero configuration and state (hidden folder)
│   ├── PROMPT.md          # Main development instructions (includes debate protocol)
│   ├── fix_plan.md       # Prioritized TODO list
│   ├── AGENT.md          # Domain agents + evaluation agents (editable)
│   ├── ideas/             # Ideation mode output (idea/coding modes)
│   │   ├── IDEAS.md       # Cumulative idea index with timestamps
│   │   └── loop_N_idea.md # Individual loop ideas
│   ├── specs/             # Project specifications
│   ├── examples/          # Usage examples
│   ├── logs/              # Loop execution logs
│   └── docs/generated/    # Auto-generated documentation
├── .korerorc              # Project configuration (mode, agents, loops)
└── src/                   # Source code (at project root)
```

> **Migration**: Existing projects can be migrated with `korero-migrate`.

## Template System

Templates in `templates/` provide starting points for new projects:
- **PROMPT.md** - Instructions for Korero's autonomous behavior
- **fix_plan.md** - Initial task structure
- **AGENT.md** - Build system template

## File Naming Conventions

- Korero control files (`fix_plan.md`, `AGENT.md`, `PROMPT.md`) reside in the `.korero/` directory
- Hidden files within `.korero/` (e.g., `.korero/.call_count`, `.korero/.exit_signals`) track loop state
- `.korero/logs/` contains timestamped execution logs
- `.korero/docs/generated/` for Korero-created documentation
- `docs/code-review/` for code review reports (at project root)

## Global Installation

Korero installs to:
- **Commands**: `~/.local/bin/` (korero, korero-monitor, korero-setup, korero-import, korero-migrate, korero-enable, korero-enable-ci)
- **Templates**: `~/.korero/templates/`
- **Scripts**: `~/.korero/` (korero_loop.sh, korero_monitor.sh, setup.sh, korero_import.sh, migrate_to_korero_folder.sh, korero_enable.sh, korero_enable_ci.sh)
- **Libraries**: `~/.korero/lib/` (circuit_breaker.sh, response_analyzer.sh, date_utils.sh, timeout_utils.sh, enable_core.sh, wizard_utils.sh, task_sources.sh, permission_presets.sh, codex_adapter.sh, cross_ai_debate.sh, debate_transcript.sh, cost_estimator.sh)

After installation, the following global commands are available:
- `korero` - Start the autonomous development loop
- `korero-monitor` - Launch the monitoring dashboard
- `korero-setup` - Create a new Korero-managed project
- `korero-import` - Import PRD/specification documents to Korero format
- `korero-migrate` - Migrate existing projects from flat structure to `.korero/` subfolder
- `korero-enable` - Interactive wizard to enable Korero in existing projects
- `korero-enable-ci` - Non-interactive version for CI/automation

## Integration Points

Korero integrates with:
- **Claude Code CLI**: Uses `npx @anthropic/claude-code` as the execution engine
- **OpenAI Codex CLI**: Used as second AI in heavy modes (`codex exec --json --sandbox read-only`)
- **tmux**: Terminal multiplexer for integrated monitoring sessions
- **Git**: Expects projects to be git repositories
- **jq**: For JSON processing of status and exit signals
- **GitHub Actions**: CI/CD pipeline for automated testing
- **Standard Unix tools**: bash, grep, date, etc.

## Exit Conditions and Thresholds

Korero uses multiple mechanisms to detect when to exit:

### Exit Detection Thresholds
- `MAX_CONSECUTIVE_TEST_LOOPS=3` - Exit if too many test-only iterations
- `MAX_CONSECUTIVE_DONE_SIGNALS=2` - Exit on repeated completion signals
- `TEST_PERCENTAGE_THRESHOLD=30%` - Flag if testing dominates recent loops
- Completion detection via .korero/fix_plan.md checklist items

### Completion Indicators with EXIT_SIGNAL Gate

The `completion_indicators` exit condition requires dual verification:

| completion_indicators | EXIT_SIGNAL | .response_analysis | Result |
|-----------------------|-------------|-------------------|--------|
| >= 2 | `true` | exists | **Exit** ("project_complete") |
| >= 2 | `false` | exists | **Continue** (Claude still working) |
| >= 2 | N/A | missing | **Continue** (defaults to false) |
| >= 2 | N/A | malformed | **Continue** (defaults to false) |
| < 2 | `true` | exists | **Continue** (threshold not met) |

**Implementation** (`korero_loop.sh:312-327`):
```bash
local claude_exit_signal="false"
if [[ -f "$KORERO_DIR/.response_analysis" ]]; then
    claude_exit_signal=$(jq -r '.analysis.exit_signal // false' "$KORERO_DIR/.response_analysis" 2>/dev/null || echo "false")
fi

if [[ $recent_completion_indicators -ge 2 ]] && [[ "$claude_exit_signal" == "true" ]]; then
    echo "project_complete"
    return 0
fi
```

**Conflict Resolution:** When `STATUS: COMPLETE` but `EXIT_SIGNAL: false` in KORERO_STATUS, the explicit EXIT_SIGNAL takes precedence. This allows Claude to mark a phase complete while indicating more phases remain.

### Circuit Breaker Thresholds
- `CB_NO_PROGRESS_THRESHOLD=3` - Open circuit after 3 loops with no file changes
- `CB_SAME_ERROR_THRESHOLD=5` - Open circuit after 5 loops with repeated errors
- `CB_OUTPUT_DECLINE_THRESHOLD=70%` - Open circuit if output declines by >70%
- `CB_PERMISSION_DENIAL_THRESHOLD=2` - Open circuit after 2 loops with permission denials (Issue #101)
- `CB_CODEX_FAILURE_THRESHOLD=3` - Open circuit after 3 consecutive Codex failures (heavy modes only)

### Permission Denial Detection (Issue #101)

When Claude Code is denied permission to execute commands (e.g., `npm install`), Korero detects this from the `permission_denials` array in the JSON output and offers interactive recovery:

1. **Detection**: The `parse_json_response()` function extracts `permission_denials` from Claude Code output
2. **Fields tracked**:
   - `has_permission_denials` (boolean)
   - `permission_denial_count` (integer)
   - `denied_commands` (array of command strings)
3. **Interactive recovery**: When permissions are denied, Korero presents an interactive prompt:
   ```
   ╔════════════════════════════════════════════════════════════╗
   ║  PERMISSION DENIED                                         ║
   ╚════════════════════════════════════════════════════════════╝

   Quick Actions:
     1) Apply quick fix (add only needed tools): Bash(npm *)
     2) Apply @standard preset (recommended for most projects)
     3) Apply @permissive preset (all Bash commands)
     n) Exit and fix manually

   Select option [1/2/3/n]:
   ```
4. **Auto-apply**: Selecting options 1-3 automatically updates `.korerorc` and resumes the loop without restart
5. **Command mapping**: `suggest_permission_fix()` maps common commands to wildcard patterns (e.g., `npm install` → `Bash(npm *)`)
6. **Tool merging**: `merge_tool_permissions()` combines new tools with existing ones, avoiding duplicates

**Visual Configuration Diff:**
Before any `.korerorc` modification, Korero displays a colorized diff showing exactly what will change. Users see the before/after state with RED for removed values and GREEN for added values. When a preset like `@standard` is applied, the expansion is shown. This provides transparency and prevents accidental misconfigurations.

**Key Functions:**
- `prompt_permission_fix()` - Interactive prompt for permission recovery
- `apply_permission_fix()` - Updates `.korerorc` with new tools (creates backup, shows diff before applying)
- `merge_tool_permissions()` - Merges tool permissions avoiding duplicates
- `suggest_permission_fix()` - Maps commands to ALLOWED_TOOLS patterns
- `format_permission_denial_message()` - Formats actionable fix suggestions
- `show_config_diff()` - Colorized before/after diff of config field changes
- `confirm_config_change()` - Show diff + y/N confirmation (for contexts without prior menu)
- `preview_korerorc_changes()` - Field-by-field diff when `korero-enable --force` overwrites existing config

**Example `.korerorc` tool patterns:**
```bash
# Using presets (recommended)
ALLOWED_TOOLS="@standard"                     # Write, Read, Edit, git, npm, pytest
ALLOWED_TOOLS="@standard,Bash(docker *)"      # Preset + custom tool
ALLOWED_TOOLS="@permissive"                   # All Bash commands

# Explicit patterns
ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)"

# Specific patterns (more restrictive)
ALLOWED_TOOLS="Write,Read,Edit,Bash(git commit),Bash(npm install)"
```

### Error Detection

Korero uses advanced error detection with two-stage filtering to eliminate false positives:

**Stage 1: JSON Field Filtering**
- Filters out JSON field patterns like `"is_error": false` that contain the word "error" but aren't actual errors
- Pattern: `grep -v '"[^"]*error[^"]*":'`

**Stage 2: Actual Error Detection**
- Detects real error messages in specific contexts:
  - Error prefixes: `Error:`, `ERROR:`, `error:`
  - Context-specific errors: `]: error`, `Link: error`
  - Error occurrences: `Error occurred`, `failed with error`
  - Exceptions: `Exception`, `Fatal`, `FATAL`
- Pattern: `grep -cE '(^Error:|^ERROR:|^error:|\]: error|Link: error|Error occurred|failed with error|[Ee]xception|Fatal|FATAL)'`

**Multi-line Error Matching**
- Detects stuck loops by verifying ALL error lines appear in ALL recent history files
- Uses literal fixed-string matching (`grep -qF`) to avoid regex edge cases
- Prevents false negatives when multiple distinct errors occur simultaneously

## Test Suite

### Test Files (923 tests across 28 files)

**Unit Tests (787 tests):**

| File | Tests | Description |
|------|-------|-------------|
| `test_cli_parsing.bats` | 70 | CLI argument parsing, progress indicator, dry-run, help topics, start-idea, quickstart, validate-config, examples, show-debate, troubleshoot, fix-config |
| `test_cli_modern.bats` | 33 | Modern CLI commands (Phase 1.1) + build_claude_command fix |
| `test_json_parsing.bats` | 74 | JSON output format parsing + Claude CLI format + session management + permission suggestions + visual config diff |
| `test_session_continuity.bats` | 44 | Session lifecycle management + circuit breaker integration + issue #91 fix |
| `test_exit_detection.bats` | 58 | Exit signal detection + EXIT_SIGNAL-based completion indicators + progress detection |
| `test_rate_limiting.bats` | 25 | Rate limiting behavior |
| `test_enable_core.bats` | 64 | Enable core library (idempotency, project detection, template generation, config validation, quickstart, verbose validation, config preview, diversity stats, config fix commands) |
| `test_task_sources.bats` | 23 | Task sources (beads, GitHub, PRD extraction, normalization) |
| `test_korero_enable.bats` | 22 | Korero enable integration tests (wizard, CI version, JSON output) |
| `test_wizard_utils.bats` | 20 | Wizard utility functions (stdout/stderr separation, prompt functions) |
| `test_ideation_mode.bats` | 66 | Multi-agent ideation: agent generation, context-aware templates, idea storage, integration |
| `test_permission_presets.bats` | 16 | Permission presets: expansion, mixed tools, integration with CLI args |
| `test_korero_ideas.bats` | 31 | Ideas browsing, search, get_idea_title, sanitize_branch_name |
| `test_debate_transcript.bats` | 18 | Debate transcript: init, append, finalize, get_latest, show, list |
| `test_health_check.bats` | 28 | Health check: tool detection, git config, permissions, network, config, CLI flag, bash version guard |
| `test_codex_adapter.bats` | 35 | Codex CLI adapter: command building, auth checks, response parsing, proposal extraction, fallback detection |
| `test_cross_ai_debate.bats` | 48 | Cross-AI debate: prompt building, verdict parsing, transcript recording, fallback handling, progress indicators, codex fallback integration |
| `test_heavy_mode.bats` | 31 | Heavy mode integration: .korerorc validation, CLI flags, health checks, circuit breaker, enable, CODEX_FALLBACK validation |
| `test_agent_protocol.bats` | 21 | Agent protocol tests |
| `test_duration_tracking.bats` | 16 | Loop duration tracking |
| `test_korero_config.bats` | 9 | Configuration management |
| `test_korero_status.bats` | 11 | Status reporting |
| `test_cost_estimator.bats` | 24 | API cost estimation: token estimation, cost calculation, log scanning, report display |

**Integration Tests (136 tests):**

| File | Tests | Description |
|------|-------|-------------|
| `test_project_setup.bats` | 44 | Project setup (setup.sh) validation |
| `test_prd_import.bats` | 33 | PRD import (korero_import.sh) workflows + modern CLI tests |
| `test_edge_cases.bats` | 25 | Edge case handling |
| `test_loop_execution.bats` | 20 | Integration tests |
| `test_installation.bats` | 14 | Global installation/uninstall workflows |

### Running Tests
```bash
# All tests (sequential)
npm test

# Parallel execution (CI — requires flock)
npm run test:parallel

# Unit tests only
npm run test:unit

# Specific test file
bats tests/unit/test_cli_parsing.bats
bats tests/unit/test_ideation_mode.bats
bats tests/unit/test_debate_transcript.bats
bats tests/unit/test_health_check.bats
bats tests/unit/test_codex_adapter.bats
bats tests/unit/test_cross_ai_debate.bats
bats tests/unit/test_heavy_mode.bats
bats tests/unit/test_cost_estimator.bats
```

## Feature Development Quality Standards

**CRITICAL**: All new features MUST meet the following mandatory requirements before being considered complete.

### Testing Requirements

- **Test Pass Rate**: 100% - all tests must pass, no exceptions
- **Test Types Required**:
  - Unit tests for bash script functions (if applicable)
  - Integration tests for Korero loop behavior
  - End-to-end tests for full development cycles
- **Test Quality**: Tests must validate behavior, not just achieve coverage metrics
- **Test Documentation**: Complex test scenarios must include comments explaining the test strategy

> **Note on Coverage**: The 85% coverage threshold is aspirational for bash scripts. Due to kcov subprocess limitations, test pass rate is the enforced quality gate.

### Git Workflow Requirements

Before moving to the next feature, ALL changes must be:

1. **Committed with Clear Messages**:
   ```bash
   git add .
   git commit -m "feat(module): descriptive message following conventional commits"
   ```
   - Use conventional commit format: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, etc.
   - Include scope when applicable: `feat(loop):`, `fix(monitor):`, `test(setup):`
   - Write descriptive messages that explain WHAT changed and WHY

2. **Pushed to Remote Repository**:
   ```bash
   git push origin <branch-name>
   ```
   - Never leave completed features uncommitted
   - Push regularly to maintain backup and enable collaboration
   - Ensure CI/CD pipelines pass before considering feature complete

3. **Branch Hygiene**:
   - Work on feature branches, never directly on `main`
   - Branch naming convention: `feature/<feature-name>`, `fix/<issue-name>`, `docs/<doc-update>`
   - Create pull requests for all significant changes

4. **Korero Integration**:
   - Update .korero/fix_plan.md with new tasks before starting work
   - Mark items complete in .korero/fix_plan.md upon completion
   - Update .korero/PROMPT.md if Korero's behavior needs modification
   - Test Korero loop with new features before completion

### Documentation Requirements

**ALL implementation documentation MUST remain synchronized with the codebase**:

1. **Script Documentation**:
   - Bash: Comments for all functions and complex logic
   - Update inline comments when implementation changes
   - Remove outdated comments immediately

2. **Implementation Documentation**:
   - Update relevant sections in this CLAUDE.md file
   - Keep template files in `templates/` current
   - Update configuration examples when defaults change
   - Document breaking changes prominently

3. **README Updates**:
   - Keep feature lists current
   - Update setup instructions when commands change
   - Maintain accurate command examples
   - Update version compatibility information

4. **Template Maintenance**:
   - Update template files when new patterns are introduced
   - Keep PROMPT.md template current with best practices
   - Update AGENT.md template with new build patterns
   - Document new Korero configuration options

5. **CLAUDE.md Maintenance**:
   - Add new commands to "Key Commands" section
   - Update "Exit Conditions and Thresholds" when logic changes
   - Keep installation instructions accurate and tested
   - Document new Korero loop behaviors or quality gates

### Feature Completion Checklist

Before marking ANY feature as complete, verify:

- [ ] All tests pass (if applicable)
- [ ] Script functionality manually tested
- [ ] All changes committed with conventional commit messages
- [ ] All commits pushed to remote repository
- [ ] CI/CD pipeline passes
- [ ] .korero/fix_plan.md task marked as complete
- [ ] Implementation documentation updated
- [ ] Inline code comments updated or added
- [ ] CLAUDE.md updated (if new patterns introduced)
- [ ] Template files updated (if applicable)
- [ ] Breaking changes documented
- [ ] Korero loop tested with new features
- [ ] Installation process verified (if applicable)

### Rationale

These standards ensure:
- **Quality**: Thorough testing prevents regressions in Korero's autonomous behavior
- **Traceability**: Git commits and fix_plan.md provide clear history of changes
- **Maintainability**: Current documentation reduces onboarding time and prevents knowledge loss
- **Collaboration**: Pushed changes enable team visibility and code review
- **Reliability**: Consistent quality gates maintain Korero loop stability
- **Automation**: Korero integration ensures continuous development practices

**Enforcement**: AI agents should automatically apply these standards to all feature development tasks without requiring explicit instruction for each task.
