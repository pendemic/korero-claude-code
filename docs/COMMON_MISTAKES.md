# Common Mistakes Guide

Quick reference for frequent Korero onboarding issues and their solutions.

## Quick Reference Table

| Symptom | Likely Cause | Solution |
|---------|-------------|----------|
| `bash: version 4+ required` | Old Bash version | Install Bash 4+ (macOS: `brew install bash`) |
| `jq: command not found` | Missing jq | Install jq (`brew install jq` / `apt install jq`) |
| `Permission denied: npm install` | ALLOWED_TOOLS too restrictive | Add `Bash(npm *)` to ALLOWED_TOOLS in `.korerorc` |
| Circuit breaker OPEN | Loop stagnation detected | Run `korero --reset-circuit` and check logs |
| Session expired, starting fresh | 24h session limit reached | Normal behavior; use `korero --reset-session` to force |
| Rate limit hit suddenly | No approach warning | Increase `--calls` or monitor usage |
| Backslash path errors on Windows | Windows path separators | Use Git Bash; paths auto-normalized in v0.12+ |
| `npx: command not found` | Node.js not installed | Install Node.js 18+ |
| Loop exits immediately | Completion indicators triggered | Check EXIT_SIGNAL in KORERO_STATUS; set to `false` |
| `No .korero directory` | Project not initialized | Run `korero-enable` in project root |

## Detailed Solutions

### 1. Bash Version Errors

**Symptom:** Error about Bash version requirement or associative array syntax errors.

**Cause:** macOS ships with Bash 3.2 (2007). Korero requires Bash 4+.

**Fix:**
```bash
# macOS
brew install bash
# Add to /etc/shells and set as default
echo /opt/homebrew/bin/bash | sudo tee -a /etc/shells
chsh -s /opt/homebrew/bin/bash

# Verify
bash --version
```

### 2. Missing jq

**Symptom:** JSON parsing errors or `jq: command not found`.

**Cause:** jq is not installed.

**Fix:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Windows (via chocolatey)
choco install jq
```

### 3. Permission Denied for Commands

**Symptom:** Loop exits with "permission_denied" reason.

**Cause:** ALLOWED_TOOLS in `.korerorc` doesn't include the tools Claude needs.

**Fix:** Update `.korerorc`:
```bash
# Use a preset (recommended)
ALLOWED_TOOLS="@standard"

# Or specify explicitly
ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)"
```

Run `korero --reset-circuit` if the circuit breaker tripped.

### 4. Circuit Breaker Tripped

**Symptom:** Loop halts with "Circuit breaker OPEN" message.

**Cause:** Detected stagnation (no file changes for 3 loops, repeated errors, or permission denials).

**Fix:**
```bash
# Check circuit breaker state
korero --circuit-status

# Reset and restart
korero --reset-circuit
korero
```

**Prevention:** Check logs in `.korero/logs/` to identify the root cause before restarting.

### 5. Session Expiration

**Symptom:** "Session expired" message, Claude starts without context.

**Cause:** Sessions expire after 24 hours by default.

**Fix:** This is normal behavior. To force a fresh session:
```bash
korero --reset-session
```

Use `--no-continue` flag to always start fresh sessions.

### 6. Rate Limit Hit

**Symptom:** Loop pauses with rate limit countdown.

**Cause:** Exceeded the hourly API call budget.

**Fix:**
```bash
# Increase call limit
korero --calls 200

# Check current status
korero --status
```

### 7. Windows Path Issues

**Symptom:** File not found errors with backslash paths.

**Cause:** Windows uses `\` but Bash expects `/`.

**Fix:** Always use Git Bash on Windows. Korero normalizes paths automatically (v0.12+). If issues persist, check that `lib/path_utils.sh` is sourced.

### 8. Loop Exits Too Early

**Symptom:** Loop exits after a few iterations even though work remains.

**Cause:** Completion indicators triggered AND EXIT_SIGNAL was `true`.

**Fix:** Ensure your PROMPT.md instructs Claude to set `EXIT_SIGNAL: false` while work remains. Check `.korero/.response_analysis` for the last exit signal value.

### 9. Agent Generation Fails

**Symptom:** `korero-enable` fails during agent generation.

**Cause:** Claude CLI not available or API quota exceeded.

**Fix:** Use manual agent specification:
```bash
korero-enable --agents "Backend Expert,Frontend Expert,DevOps Engineer"
```

Or use generic agents (no API call needed).

### 10. tmux Not Available

**Symptom:** `korero --monitor` fails.

**Cause:** tmux not installed.

**Fix:**
```bash
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt install tmux
```

Use `korero` without `--monitor` as fallback.
