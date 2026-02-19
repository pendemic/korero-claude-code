# Korero for Claude Code

[![CI](https://github.com/pendemic/korero-claude-code/actions/workflows/test.yml/badge.svg)](https://github.com/pendemic/korero-claude-code/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-0.12.0-blue)
![Tests](https://img.shields.io/badge/tests-503%20passing-green)
[![GitHub Issues](https://img.shields.io/github/issues/pendemic/korero-claude-code)](https://github.com/pendemic/korero-claude-code/issues)

> **Multi-agent ideation and development system for Claude Code**

Korero is a multi-agent ideation and development system for Claude Code with two modes: a **Continuous Coding Loop** (domain experts propose ideas, mandatory agents debate them, winning idea gets implemented and committed) and a **Continuous Idea Loop** (same debate process, but only the best idea is saved to disk). Built-in safeguards prevent infinite loops and API overuse.

**Install once, use everywhere** - Korero becomes a global command available in any directory.

## Project Status

**Version**: v0.12.0 - Active Development
**Core Features**: Working and tested
**Test Coverage**: 503 tests, 100% pass rate

### What's Working Now
- **Multi-agent ideation system** with domain expert agents and structured debate protocol
- **Two loop modes**: Continuous Coding Loop (ideation + implementation) and Continuous Idea Loop (ideation only)
- **Auto-generated domain agents** via Claude Code CLI based on project subject
- **3 mandatory evaluation agents**: Devil's Advocate, Technical Feasibility Analyst, Idea Orchestrator
- **Configurable agent count** (1-10 domain agents) and loop limits
- **Idea accumulation** in `.korero/ideas/IDEAS.md`
- Autonomous development loops with intelligent exit detection
- **Dual-condition exit gate**: Requires BOTH completion indicators AND explicit EXIT_SIGNAL
- Rate limiting with hourly reset (100 calls/hour, configurable)
- Circuit breaker with advanced error detection (prevents runaway loops)
- Response analyzer with semantic understanding and two-stage error filtering
- **JSON output format support with automatic fallback to text parsing**
- **Session continuity with `--resume` flag for context preservation**
- **Interactive project enablement with `korero-enable` 7-phase wizard**
- **`.korerorc` configuration file for project settings**
- **Live streaming output with `--live` flag for real-time Claude Code visibility**
- tmux integration for live monitoring
- PRD import functionality
- **CI/CD pipeline with GitHub Actions**

### Recent Improvements

**v0.12.0 - Fork to Korero + Multi-Agent Ideation** (latest)
- Forked from Ralph to Korero - renamed entire codebase
- Multi-agent ideation system with domain expert agents and structured debate protocol
- Two loop modes: Continuous Coding Loop (ideation + implementation) and Continuous Idea Loop (ideation only)
- Auto-generate domain agents via Claude Code CLI or enter manually
- Configurable agent count (1-10) and loop limits (10, 20, 50, continuous)
- 7-phase interactive wizard in `korero-enable`
- Idea accumulation in `.korero/ideas/IDEAS.md`
- 38 new tests for ideation mode

**v0.11.4 - Bug Fixes & Compatibility**
- Fixed progress detection: Git commits within a loop now count as progress (#141)
- Fixed checkbox regex: Date entries `[2026-01-29]` no longer counted as checkboxes (#144)
- Fixed session hijacking: Use `--resume <session_id>` instead of `--continue` (#151)
- Fixed EXIT_SIGNAL override: `STATUS: COMPLETE` with `EXIT_SIGNAL: false` now continues working (#146)
- Fixed korero-import hanging indefinitely (added `--print` flag for non-interactive mode)
- Fixed korero-import absolute path handling
- Fixed cross-platform date commands for macOS with Homebrew coreutils
- Added configurable circuit breaker thresholds via environment variables (#99)
- Added tmux support for non-zero `base-index` configurations
- Added 13 new regression tests for progress detection and checkbox regex

**v0.11.3 - Live Streaming & Beads Fix**
- Added live streaming output mode with `--live` flag for real-time Claude Code visibility (#125)
- Fixed beads task import using correct `bd list` arguments (#150)
- Applied CodeRabbit review fixes: camelCase variables, status-respecting fallback, jq guards
- Added 12 new tests for live streaming and beads import improvements

**v0.11.2 - Setup Permissions Fix**
- Fixed issue #136: `korero-setup` now creates `.korerorc` with consistent tool permissions
- Updated default `ALLOWED_TOOLS` to include `Edit`, `Bash(npm *)`, and `Bash(pytest)`
- Both `korero-setup` and `korero-enable` now create identical `.korerorc` configurations
- Monitor now forwards all CLI parameters to inner korero loop (#126)
- Added 16 new tests for permissions and parameter forwarding

**v0.11.1 - Completion Indicators Fix**
- Fixed premature exit after exactly 5 loops in JSON output mode
- `completion_indicators` now only accumulates when `EXIT_SIGNAL: true`
- Aligns with documented dual-condition exit gate behavior

**v0.11.0 - Korero Enable Wizard + Multi-Agent Ideation**
- Added `korero-enable` interactive wizard (7-phase) with mode selection, agent generation, and loop limits
- **Multi-agent ideation system**: Domain experts propose ideas, 3 mandatory agents debate them
- **Two modes**: Continuous Coding Loop (implement + commit) and Continuous Idea Loop (save ideas only)
- Auto-generate domain agents via Claude Code CLI or enter manually
- Configurable agent count (1-10) and loop limits (10, 20, 50, continuous)
- Idea accumulation in `.korero/ideas/IDEAS.md`
- Auto-detects project type (TypeScript, Python, Rust, Go) and framework
- Imports tasks from beads, GitHub Issues, or PRD documents
- Added `korero-enable-ci` with `--mode`, `--subject`, `--agents`, `--loops` flags
- New library components: `enable_core.sh`, `wizard_utils.sh`, `task_sources.sh`

**v0.10.1 - Bug Fixes & Monitor Path Corrections**
- Fixed `korero_monitor.sh` hardcoded paths for v0.10.0 compatibility
- Fixed EXIT_SIGNAL parsing in JSON format
- Added safety circuit breaker (force exit after 5 consecutive completion indicators)
- Fixed checkbox parsing for indented markdown

**v0.10.0 - .korero/ Subfolder Structure (BREAKING CHANGE)**
- **Breaking**: Moved all Korero-specific files to `.korero/` subfolder
- Project root stays clean: only `src/`, `README.md`, and user files remain
- Added `korero-migrate` command for upgrading existing projects

<details>
<summary>Earlier versions (v0.9.x)</summary>

**v0.9.9 - EXIT_SIGNAL Gate & Uninstall Script**
- Fixed premature exit bug: completion indicators now require Claude's explicit `EXIT_SIGNAL: true`
- Added dedicated `uninstall.sh` script for clean Korero removal

**v0.9.8 - Modern CLI for PRD Import**
- Modernized `korero_import.sh` to use Claude Code CLI JSON output format
- Enhanced error handling with structured JSON error messages

**v0.9.7 - Session Lifecycle Management**
- Complete session lifecycle management with automatic reset triggers
- Added `--reset-session` CLI flag for manual session reset

**v0.9.6 - JSON Output & Session Management**
- Extended `parse_json_response()` to support Claude Code CLI JSON format
- Added session management functions

**v0.9.5 - v0.9.0** - PRD import tests, project setup tests, installation tests, prompt file fix, modern CLI commands, circuit breaker enhancements

</details>

### In Progress
- Expanding test coverage
- Log rotation functionality
- Dry-run mode
- Metrics and analytics tracking
- Desktop notifications
- Git backup and rollback system
- [Automated badge updates](#138)

**Timeline to v1.0**: ~4 weeks | [Full roadmap](IMPLEMENTATION_PLAN.md) | **Contributions welcome!**

## Features

- **Multi-Agent Ideation** - Domain expert agents propose improvements, mandatory agents debate them in structured rounds
- **Two Loop Modes** - Continuous Coding Loop (ideation + implementation) or Continuous Idea Loop (ideation only)
- **Auto-Generated Agents** - Domain experts generated via Claude Code CLI based on project subject
- **Structured Debate Protocol** - 3-round evaluation: Evaluation → Rebuttal → Final Selection
- **Idea Accumulation** - Winning ideas saved per-loop and indexed in `.korero/ideas/IDEAS.md`
- **Autonomous Development Loop** - Continuously executes Claude Code with your project requirements
- **Intelligent Exit Detection** - Dual-condition check requiring BOTH completion indicators AND explicit EXIT_SIGNAL
- **Session Continuity** - Preserves context across loop iterations with automatic session management
- **Rate Limiting** - Built-in API call management with hourly limits and countdown timers
- **Live Monitoring** - Real-time dashboard showing loop status, progress, and logs
- **Task Management** - Structured approach with prioritized task lists and progress tracking
- **Interactive Project Setup** - `korero-enable` 7-phase wizard with mode selection and agent generation
- **Configuration Files** - `.korerorc` for project-specific settings, mode, agents, and loop limits
- **Response Analyzer** - AI-powered analysis of Claude Code responses with semantic understanding
- **Circuit Breaker** - Advanced error detection with two-stage filtering and automatic recovery
- **CI/CD Integration** - GitHub Actions workflow with automated testing
- **Live Streaming Output** - Real-time visibility into Claude Code execution with `--live` flag

## Quick Start

Korero has two phases: **one-time installation** and **per-project setup**.

```
INSTALL ONCE              USE MANY TIMES
+-----------------+          +----------------------+
| ./install.sh    |    ->    | korero-setup project1 |
|                 |          | korero-enable         |
| Adds global     |          | korero-import prd.md  |
| commands        |          | ...                  |
+-----------------+          +----------------------+
```

### Phase 1: Install Korero (One Time Only)

Install Korero globally on your system:

```bash
git clone https://github.com/pendemic/korero-claude-code.git
cd korero-claude-code
./install.sh
```

This adds `korero`, `korero-monitor`, `korero-setup`, `korero-import`, `korero-migrate`, `korero-enable`, and `korero-enable-ci` commands to your PATH.

> **Note**: You only need to do this once per system. After installation, you can delete the cloned repository if desired.

### Phase 2: Initialize Projects (Per Project)

#### Option A: Enable Korero in Existing Project (Recommended)
```bash
cd my-existing-project

# Interactive wizard - selects mode, generates agents, imports tasks
korero-enable

# Idea loop for brainstorming domain improvements
korero-enable --mode idea --subject "data analysis tool" --agents 4

# Coding loop with auto-generated agents and limited iterations
korero-enable --mode coding --subject "web app" --loops 20

# Or with specific task source (coding mode)
korero-enable --from beads
korero-enable --from github --label "sprint-1"

# Start autonomous development
korero --monitor
```

#### Option B: Import Existing PRD/Specifications
```bash
# Convert existing PRD/specs to Korero format
korero-import my-requirements.md my-project
cd my-project

# Review and adjust the generated files:
# - .korero/PROMPT.md (Korero instructions)
# - .korero/fix_plan.md (task priorities)
# - .korero/specs/requirements.md (technical specs)

# Start autonomous development
korero --monitor
```

#### Option C: Create New Project from Scratch
```bash
# Create blank Korero project
korero-setup my-awesome-project
cd my-awesome-project

# Configure your project requirements manually
# Edit .korero/PROMPT.md with your project goals
# Edit .korero/specs/ with detailed specifications
# Edit .korero/fix_plan.md with initial priorities

# Start autonomous development
korero --monitor
```

### Ongoing Usage (After Setup)

Once Korero is installed and your project is initialized:

```bash
# Navigate to any Korero project and run:
korero --monitor              # Integrated tmux monitoring (recommended)

# Or use separate terminals:
korero                        # Terminal 1: Korero loop
korero-monitor               # Terminal 2: Live monitor dashboard
```

### Uninstalling Korero

To completely remove Korero from your system:

```bash
# Run the uninstall script
./uninstall.sh

# Or if you deleted the repo, download and run:
curl -sL https://raw.githubusercontent.com/pendemic/korero-claude-code/main/uninstall.sh | bash
```

## Understanding Korero Files

After running `korero-enable` or `korero-import`, you'll have a `.korero/` directory with several files. Here's what each file does and whether you need to edit it:

| File | Auto-Generated? | You Should... |
|------|-----------------|---------------|
| `.korero/PROMPT.md` | Yes (includes debate protocol) | **Review & customize** project goals and principles |
| `.korero/fix_plan.md` | Yes (can import tasks) | **Add/modify** specific implementation tasks |
| `.korero/AGENT.md` | Yes (domain + evaluation agents) | **Edit to customize** agent personas and expertise |
| `.korero/ideas/` | Created in idea/coding modes | Read accumulated ideas from each loop iteration |
| `.korero/specs/` | Empty directory | Add files when PROMPT.md isn't detailed enough |
| `.korerorc` | Yes (project-aware) | Edit to change mode, agent count, or loop limits |

### Key File Relationships

```
PROMPT.md (debate protocol + project goals)
    ↓
AGENT.md (domain experts + evaluation agents)
    ↓
fix_plan.md (specific tasks Korero executes)
    ↓
ideas/ (accumulated winning ideas from each loop)
```

### When to Use specs/

- **Simple projects**: PROMPT.md + fix_plan.md is usually enough
- **Complex features**: Add specs/feature-name.md for detailed requirements
- **Team conventions**: Add specs/stdlib/convention-name.md for reusable patterns

See the [User Guide](docs/user-guide/) for detailed explanations and the [examples/](examples/) directory for realistic project configurations.

## How It Works

Korero operates on a multi-agent ideation cycle:

1. **Read Instructions** - Loads `PROMPT.md` (debate protocol) and `AGENT.md` (agent personas)
2. **Phase 1: Idea Generation** - Each domain agent proposes ONE improvement
3. **Phase 2: Structured Debate** - Devil's Advocate, Technical Feasibility Analyst, and Idea Orchestrator evaluate proposals in 3 rounds (Evaluation → Rebuttal → Final Selection)
4. **Phase 3: Implementation** (coding mode only) - Winning idea gets implemented and committed
5. **Save & Repeat** - Winning idea saved to `.korero/ideas/`, loop continues until complete or limit reached

### Intelligent Exit Detection

Korero uses a **dual-condition check** to prevent premature exits during productive iterations:

**Exit requires BOTH conditions:**
1. `completion_indicators >= 2` (heuristic detection from natural language patterns)
2. Claude's explicit `EXIT_SIGNAL: true` in the KORERO_STATUS block

**Example behavior:**
```
Loop 5: Claude outputs "Phase complete, moving to next feature"
        → completion_indicators: 3 (high confidence from patterns)
        → EXIT_SIGNAL: false (Claude says more work needed)
        → Result: CONTINUE (respects Claude's explicit intent)

Loop 8: Claude outputs "All tasks complete, project ready"
        → completion_indicators: 4
        → EXIT_SIGNAL: true (Claude confirms done)
        → Result: EXIT with "project_complete"
```

**Other exit conditions:**
- All tasks in `.korero/fix_plan.md` marked complete
- Multiple consecutive "done" signals from Claude Code
- Too many test-focused loops (indicating feature completeness)
- Claude API 5-hour usage limit reached (with user prompt to wait or exit)

## Enabling Korero in Existing Projects

The `korero-enable` command provides an interactive 7-phase wizard for adding Korero to existing projects:

```bash
cd my-existing-project
korero-enable
```

**The wizard:**
1. **Detects Environment** - Identifies project type (TypeScript, Python, etc.) and framework
2. **Selects Mode** - Continuous Coding Loop (ideation + implementation) or Continuous Idea Loop (ideation only)
3. **Configures Subject & Agents** - Enter project subject, choose agent count (1-10), select auto-generate or manual entry
4. **Selects Task Sources** - Choose from beads, GitHub Issues, or PRD documents (coding mode only)
5. **Configures Settings** - Set tool permissions, loop limits (10, 20, 50, or continuous)
6. **Generates Files** - Creates `.korero/` directory, AGENT.md with domain + evaluation agents, `.korerorc`
7. **Verifies Setup** - Confirms all files are created correctly

**Non-interactive mode for CI/automation:**
```bash
korero-enable-ci                                                    # Sensible defaults
korero-enable-ci --mode idea --subject "ML pipeline" --agents 5     # Idea loop
korero-enable-ci --mode coding --subject "web app" --loops 20       # Coding loop
korero-enable-ci --from github --json                               # Import + JSON output
```

## Importing Existing Requirements

Korero can convert existing PRDs, specifications, or requirement documents into the proper Korero format using Claude Code.

### Supported Formats
- **Markdown** (.md) - Product requirements, technical specs
- **Text files** (.txt) - Plain text requirements
- **JSON** (.json) - Structured requirement data
- **Word documents** (.docx) - Business requirements
- **PDFs** (.pdf) - Design documents, specifications
- **Any text-based format** - Korero will intelligently parse the content

### Usage Examples

```bash
# Convert a markdown PRD
korero-import product-requirements.md my-app

# Convert a text specification
korero-import requirements.txt webapp

# Convert a JSON API spec
korero-import api-spec.json backend-service

# Let Korero auto-name the project from filename
korero-import design-doc.pdf
```

### What Gets Generated

Korero-import creates a complete project with:

- **.korero/PROMPT.md** - Converted into Korero development instructions
- **.korero/fix_plan.md** - Requirements broken down into prioritized tasks
- **.korero/specs/requirements.md** - Technical specifications extracted from your document
- **.korerorc** - Project configuration file with tool permissions
- **Standard Korero structure** - All necessary directories and template files in `.korero/`

The conversion is intelligent and preserves your original requirements while making them actionable for autonomous development.

## Configuration

### Project Configuration (.korerorc)

Each Korero project can have a `.korerorc` configuration file:

```bash
# .korerorc - Korero project configuration
PROJECT_NAME="my-project"
PROJECT_TYPE="typescript"

# Korero mode: idea (ideation only) or coding (ideation + implementation)
KORERO_MODE="coding"

# Project subject (used for agent generation)
PROJECT_SUBJECT="web application"

# Number of domain expert agents (not including 3 mandatory evaluation agents)
DOMAIN_AGENT_COUNT=3

# Maximum loops to run (number or "continuous" for unlimited)
MAX_LOOPS="continuous"

# Loop settings
MAX_CALLS_PER_HOUR=100
CLAUDE_TIMEOUT_MINUTES=15
CLAUDE_OUTPUT_FORMAT="json"

# Tool permissions
ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)"

# Session management
SESSION_CONTINUITY=true
SESSION_EXPIRY_HOURS=24

# Circuit breaker thresholds
CB_NO_PROGRESS_THRESHOLD=3
CB_SAME_ERROR_THRESHOLD=5
```

### Rate Limiting & Circuit Breaker

Korero includes intelligent rate limiting and circuit breaker functionality:

```bash
# Default: 100 calls per hour
korero --calls 50

# With integrated monitoring
korero --monitor --calls 50

# Check current usage
korero --status
```

The circuit breaker automatically:
- Detects API errors and rate limit issues with advanced two-stage filtering
- Opens circuit after 3 loops with no progress or 5 loops with same errors
- Eliminates false positives from JSON fields containing "error"
- Accurately detects stuck loops with multi-line error matching
- Gradually recovers with half-open monitoring state
- Provides detailed error tracking and logging with state history

### Claude API 5-Hour Limit

When Claude's 5-hour usage limit is reached, Korero:
1. Detects the limit error automatically
2. Prompts you to choose:
   - **Option 1**: Wait 60 minutes for the limit to reset (with countdown timer)
   - **Option 2**: Exit gracefully (or auto-exits after 30-second timeout)
3. Prevents endless retry loops that waste time

### Custom Prompts

```bash
# Use custom prompt file
korero --prompt my_custom_instructions.md

# With integrated monitoring
korero --monitor --prompt my_custom_instructions.md
```

### Execution Timeouts

```bash
# Set Claude Code execution timeout (default: 15 minutes)
korero --timeout 30  # 30-minute timeout for complex tasks

# With monitoring and custom timeout
korero --monitor --timeout 60  # 60-minute timeout

# Short timeout for quick iterations
korero --verbose --timeout 5  # 5-minute timeout with progress
```

### Verbose Mode

```bash
# Enable detailed progress updates during execution
korero --verbose

# Combine with other options
korero --monitor --verbose --timeout 30
```

### Live Streaming Output

```bash
# Enable real-time visibility into Claude Code execution
korero --live

# Combine with monitoring for best experience
korero --monitor --live

# Live output is written to .korero/live.log
tail -f .korero/live.log  # Watch in another terminal
```

Live streaming mode shows Claude Code's output in real-time as it works, providing visibility into what's happening during each loop iteration.

### Session Continuity

Korero maintains session context across loop iterations for improved coherence:

```bash
# Sessions are enabled by default with --resume flag
korero --monitor                 # Uses session continuity

# Start fresh without session context
korero --no-continue             # Isolated iterations

# Reset session manually (clears context)
korero --reset-session           # Clears current session

# Check session status
cat .korero/.claude_session_id          # View current Claude session ID
cat .korero/.korero_session_history     # View session transition history
```

**Note:** Korero uses `--resume <session_id>` (not `--continue`) to avoid session hijacking (Issue #151). The session ID is stored in `.korero/.claude_session_id`.

**Session Auto-Reset Triggers:**
- Circuit breaker opens (stagnation detected)
- Manual interrupt (Ctrl+C / SIGINT)
- Project completion (graceful exit)
- Manual circuit breaker reset (`--reset-circuit`)
- Session expiration (default: 24 hours)

Sessions are persisted to `.korero/.korero_session` with a configurable expiration (default: 24 hours). The last 50 session transitions are logged to `.korero/.korero_session_history` for debugging.

### Exit Thresholds

Modify these variables in `~/.korero/korero_loop.sh`:

**Exit Detection Thresholds:**
```bash
MAX_CONSECUTIVE_TEST_LOOPS=3     # Exit after 3 test-only loops
MAX_CONSECUTIVE_DONE_SIGNALS=2   # Exit after 2 "done" signals
TEST_PERCENTAGE_THRESHOLD=30     # Flag if 30%+ loops are test-only
```

**Circuit Breaker Thresholds:**
```bash
CB_NO_PROGRESS_THRESHOLD=3       # Open circuit after 3 loops with no file changes
CB_SAME_ERROR_THRESHOLD=5        # Open circuit after 5 loops with repeated errors
CB_OUTPUT_DECLINE_THRESHOLD=70   # Open circuit if output declines by >70%
```

**Completion Indicators with EXIT_SIGNAL Gate:**

| completion_indicators | EXIT_SIGNAL | Result |
|-----------------------|-------------|--------|
| >= 2 | `true` | **Exit** ("project_complete") |
| >= 2 | `false` | **Continue** (Claude still working) |
| >= 2 | missing | **Continue** (defaults to false) |
| < 2 | `true` | **Continue** (threshold not met) |

## Project Structure

Korero creates a standardized structure for each project with a `.korero/` subfolder for configuration:

```
my-project/
├── .korero/                 # Korero configuration and state (hidden folder)
│   ├── PROMPT.md           # Main development instructions (includes debate protocol)
│   ├── fix_plan.md        # Prioritized task list
│   ├── AGENT.md           # Domain agents + evaluation agents (editable)
│   ├── ideas/              # Ideation mode output
│   │   ├── IDEAS.md       # Cumulative idea index with timestamps
│   │   └── loop_N_idea.md # Individual loop ideas
│   ├── specs/              # Project specifications and requirements
│   │   └── stdlib/         # Standard library specifications
│   ├── examples/           # Usage examples and test cases
│   ├── logs/               # Korero execution logs
│   └── docs/generated/     # Auto-generated documentation
├── .korerorc                # Korero configuration file (mode, agents, loop limits)
└── src/                    # Source code implementation (at project root)
```

> **Migration**: If you have existing Korero projects using the old flat structure, run `korero-migrate` to automatically move files to the `.korero/` subfolder.

## Best Practices

### Writing Effective Prompts

1. **Be Specific** - Clear requirements lead to better results
2. **Prioritize** - Use `.korero/fix_plan.md` to guide Korero's focus
3. **Set Boundaries** - Define what's in/out of scope
4. **Include Examples** - Show expected inputs/outputs

### Project Specifications

- Place detailed requirements in `.korero/specs/`
- Use `.korero/fix_plan.md` for prioritized task tracking
- Keep `.korero/AGENT.md` updated with build instructions
- Document key decisions and architecture

### Monitoring Progress

- Use `korero-monitor` for live status updates
- Check logs in `.korero/logs/` for detailed execution history
- Monitor `.korero/status.json` for programmatic access
- Watch for exit condition signals

## System Requirements

- **Bash 4.0+** - For script execution
- **Claude Code CLI** - `npm install -g @anthropic-ai/claude-code`
- **tmux** - Terminal multiplexer for integrated monitoring (recommended)
- **jq** - JSON processing for status tracking
- **Git** - Version control (projects are initialized as git repos)
- **GNU coreutils** - For the `timeout` command (execution timeouts)
  - Linux: Pre-installed on most distributions
  - macOS: Install via `brew install coreutils` (provides `gtimeout`)
- **Standard Unix tools** - grep, date, etc.

### Testing Requirements (Development)

See [TESTING.md](TESTING.md) for the comprehensive testing guide.

If you want to run the test suite:

```bash
# Install BATS testing framework
npm install -g bats bats-support bats-assert

# Run all tests (503 tests)
npm test

# Run specific test suites
bats tests/unit/test_rate_limiting.bats
bats tests/unit/test_exit_detection.bats
bats tests/unit/test_json_parsing.bats
bats tests/unit/test_cli_modern.bats
bats tests/unit/test_cli_parsing.bats
bats tests/unit/test_session_continuity.bats
bats tests/unit/test_enable_core.bats
bats tests/unit/test_task_sources.bats
bats tests/unit/test_korero_enable.bats
bats tests/unit/test_wizard_utils.bats
bats tests/unit/test_ideation_mode.bats
bats tests/integration/test_loop_execution.bats
bats tests/integration/test_edge_cases.bats
bats tests/integration/test_prd_import.bats
bats tests/integration/test_project_setup.bats
bats tests/integration/test_installation.bats

# Run error detection and circuit breaker tests
./tests/test_error_detection.sh
./tests/test_stuck_loop_detection.sh
```

Current test status:
- **503 tests** across 16 test files
- **100% pass rate**
- Comprehensive unit and integration tests
- Specialized tests for JSON parsing, CLI flags, circuit breaker, EXIT_SIGNAL behavior, enable wizard, ideation mode, and installation workflows

> **Note on Coverage**: Bash code coverage measurement with kcov has fundamental limitations when tracing subprocess executions. Test pass rate (100%) is the quality gate. See [bats-core#15](https://github.com/bats-core/bats-core/issues/15) for details.

### Installing tmux

```bash
# Ubuntu/Debian
sudo apt-get install tmux

# macOS
brew install tmux

# CentOS/RHEL
sudo yum install tmux
```

### Installing GNU coreutils (macOS)

Korero uses the `timeout` command for execution timeouts. On macOS, you need to install GNU coreutils:

```bash
# Install coreutils (provides gtimeout)
brew install coreutils

# Verify installation
gtimeout --version
```

Korero automatically detects and uses `gtimeout` on macOS. No additional configuration is required after installation.

## Monitoring and Debugging

### Live Dashboard

```bash
# Integrated tmux monitoring (recommended)
korero --monitor

# Manual monitoring in separate terminal
korero-monitor
```

Shows real-time:
- Current loop count and status
- API calls used vs. limit
- Recent log entries
- Rate limit countdown

**tmux Controls:**
- `Ctrl+B` then `D` - Detach from session (keeps Korero running)
- `Ctrl+B` then `←/→` - Switch between panes
- `tmux list-sessions` - View active sessions
- `tmux attach -t <session-name>` - Reattach to session

### Status Checking

```bash
# JSON status output
korero --status

# Manual log inspection
tail -f .korero/logs/korero.log
```

### Common Issues

- **Rate Limits** - Korero automatically waits and displays countdown
- **5-Hour API Limit** - Korero detects and prompts for user action (wait or exit)
- **Stuck Loops** - Check `fix_plan.md` for unclear or conflicting tasks
- **Early Exit** - Review exit thresholds if Korero stops too soon
- **Premature Exit** - Check if Claude is setting `EXIT_SIGNAL: false` (Korero now respects this)
- **Execution Timeouts** - Increase `--timeout` value for complex operations
- **Missing Dependencies** - Ensure Claude Code CLI and tmux are installed
- **tmux Session Lost** - Use `tmux list-sessions` and `tmux attach` to reconnect
- **Session Expired** - Sessions expire after 24 hours by default; use `--reset-session` to start fresh
- **timeout: command not found (macOS)** - Install GNU coreutils: `brew install coreutils`
- **Permission Denied** - Korero halts when Claude Code is denied permission for commands:
  1. Edit `.korerorc` and update `ALLOWED_TOOLS` to include required tools
  2. Common patterns: `Bash(npm *)`, `Bash(git *)`, `Bash(pytest)`
  3. Run `korero --reset-session` after updating `.korerorc`
  4. Restart with `korero --monitor`

## Contributing

Korero is actively seeking contributors! We're working toward v1.0.0 with clear priorities and a detailed roadmap.

**See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete contributor guide** including:
- Getting started and setup instructions
- Development workflow and commit conventions
- Code style guidelines
- Testing requirements (100% pass rate mandatory)
- Pull request process and code review guidelines
- Quality standards and checklists

### Quick Start

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/korero-claude-code.git
cd korero-claude-code

# Install dependencies and run tests
npm install
npm test  # All 503 tests must pass
```

### Priority Contribution Areas

1. **Test Implementation** - Help expand test coverage
2. **Feature Development** - Log rotation, dry-run mode, metrics
3. **Documentation** - Tutorials, troubleshooting guides, examples
4. **Real-World Testing** - Use Korero, report bugs, share feedback

**Every contribution matters** - from fixing typos to implementing major features!

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by the [Ralph technique](https://ghuntley.com/ralph/) created by Geoffrey Huntley
- Built for [Claude Code](https://claude.ai/code) by Anthropic
- Community feedback and contributions

## Related Projects

- [Claude Code](https://claude.ai/code) - The AI coding assistant that powers Korero
- [Aider](https://github.com/paul-gauthier/aider) - AI pair programming tool

---

## Command Reference

### Installation Commands (Run Once)
```bash
./install.sh              # Install Korero globally
./uninstall.sh            # Remove Korero from system (dedicated script)
./install.sh uninstall    # Alternative: Remove Korero from system
./install.sh --help       # Show installation help
korero-migrate             # Migrate existing project to .korero/ structure
```

### Korero Loop Options
```bash
korero [OPTIONS]
  -h, --help              Show help message
  -c, --calls NUM         Set max calls per hour (default: 100)
  -p, --prompt FILE       Set prompt file (default: PROMPT.md)
  -s, --status            Show current status and exit
  -m, --monitor           Start with tmux session and live monitor
  -v, --verbose           Show detailed progress updates during execution
  -l, --live              Enable live streaming output (real-time Claude Code visibility)
  -t, --timeout MIN       Set Claude Code execution timeout in minutes (1-120, default: 15)
  --output-format FORMAT  Set output format: json (default) or text
  --allowed-tools TOOLS   Set allowed Claude tools (default: Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest))
  --no-continue           Disable session continuity (start fresh each loop)
  --reset-circuit         Reset the circuit breaker
  --circuit-status        Show circuit breaker status
  --reset-session         Reset session state manually
```

### Project Commands (Per Project)
```bash
korero-setup project-name     # Create new Korero project
korero-enable                 # Enable Korero in existing project (interactive)
korero-enable-ci              # Enable Korero in existing project (non-interactive)
korero-import prd.md project  # Convert PRD/specs to Korero project
korero --monitor              # Start with integrated monitoring
korero --status               # Check current loop status
korero --verbose              # Enable detailed progress updates
korero --timeout 30           # Set 30-minute execution timeout
korero --calls 50             # Limit to 50 API calls per hour
korero --reset-session        # Reset session state manually
korero --live                 # Enable live streaming output
korero-monitor                # Manual monitoring dashboard
```

### tmux Session Management
```bash
tmux list-sessions        # View active Korero sessions
tmux attach -t <name>     # Reattach to detached session
# Ctrl+B then D           # Detach from session (keeps running)
```

---

## Development Roadmap

Korero is under active development with a clear path to v1.0.0. See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the complete roadmap.

### Current Status: v0.12.0

**What's Delivered:**
- **Multi-agent ideation system** with domain experts and structured debate protocol
- **Two loop modes**: Continuous Coding Loop and Continuous Idea Loop
- **Auto-generated domain agents** via Claude Code CLI
- Core loop functionality with intelligent exit detection
- **Dual-condition exit gate** (completion indicators + EXIT_SIGNAL)
- Rate limiting (100 calls/hour) and circuit breaker pattern
- Response analyzer with semantic understanding
- **Live streaming output mode** for real-time Claude Code visibility
- tmux integration and live monitoring
- PRD import functionality with modern CLI JSON parsing
- Installation system and project templates
- CI/CD pipeline with GitHub Actions
- **Interactive `korero-enable` 7-phase wizard** with mode selection and agent generation
- **`.korerorc` configuration file** with mode, agents, and loop limit settings
- Session lifecycle management with auto-reset triggers

**Test Coverage Breakdown:**
- Unit Tests: 367 across 11 files (CLI parsing, JSON, exit detection, rate limiting, session continuity, enable wizard, ideation mode)
- Integration Tests: 136 across 5 files (loop execution, edge cases, PRD import, project setup, installation)
- Total: 503 tests across 16 files

### Path to v1.0.0 (~4 weeks)

**Enhanced Testing**
- Installation and setup workflow tests
- tmux integration tests
- Monitor dashboard tests

**Core Features**
- Log rotation functionality
- Dry-run mode

**Advanced Features & Polish**
- Metrics and analytics tracking
- Desktop notifications
- Git backup and rollback system
- End-to-end tests
- Final documentation and release prep

See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for detailed progress tracking.

### How to Contribute
Korero is seeking contributors! See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete guide. Priority areas:
1. **Test Implementation** - Help expand test coverage ([see plan](IMPLEMENTATION_PLAN.md))
2. **Feature Development** - Log rotation, dry-run mode, metrics
3. **Documentation** - Usage examples, tutorials, troubleshooting guides
4. **Bug Reports** - Real-world usage feedback and edge cases

---

**Ready to let AI build your project?** Start with `./install.sh` and let Korero take it from there!

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=pendemic/korero-claude-code&type=date&legend=top-left)](https://www.star-history.com/#pendemic/korero-claude-code&type=date&legend=top-left)
