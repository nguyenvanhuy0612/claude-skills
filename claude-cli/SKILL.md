# Claude Code CLI — Personal Guide

## Table of Contents

- [Installation & Auth](#installation--auth)
- [Starting Claude](#starting-claude)
- [Session Management](#session-management)
- [Slash Commands (Inside Session)](#slash-commands-inside-session)
- [Common CLI Flags](#common-cli-flags)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Quick Prefixes](#quick-prefixes)
- [Configuration Files](#configuration-files)
- [Permissions](#permissions)
- [Creating Custom Skills](#creating-custom-skills)
- [CLAUDE.md — Project Instructions](#claudemd--project-instructions)
- [Hooks](#hooks)
- [MCP Servers](#mcp-servers)

---

## Installation & Auth

```bash
# Install
npm install -g @anthropic-ai/claude-code

# Login
claude auth login                  # Interactive login
claude auth login --email me@x.com # Pre-fill email
claude auth login --sso            # SSO login
claude auth login --console        # Anthropic Console billing

# Check auth
claude auth status                 # JSON output
claude auth status --text          # Human-readable

# Logout
claude auth logout

# Update
claude update

# Version
claude -v
```

---

## Starting Claude

```bash
# Interactive mode
claude                             # New session
claude "explain this project"      # New session with initial prompt
claude -n "my-session"             # New named session
claude --init                      # Run init hooks, then start

# One-shot / print mode (non-interactive)
claude -p "what does this do"
claude -p "summarize" --output-format json
cat file.txt | claude -p "explain this"

# Bare mode (skip auto-discovery, faster startup)
claude --bare -p "quick question"
```

---

## Session Management

### Create

| Command | Description |
|---------|-------------|
| `claude` | New interactive session |
| `claude "prompt"` | New session with initial prompt |
| `claude -n "name"` | New **named** session |
| `claude -n "name" "prompt"` | Named session with prompt |
| `claude --session-id "UUID"` | Use a specific session ID |

### List / Browse

| Command | Description |
|---------|-------------|
| `claude --resume` or `claude -r` | Interactive session picker (lists all sessions) |
| `/resume` (inside session) | Interactive session picker |

> Sessions stored at: `~/.claude/sessions/`

### Resume / Continue

| Command | Description |
|---------|-------------|
| `claude -c` | Continue **most recent** conversation |
| `claude -c "prompt"` | Continue most recent + send prompt |
| `claude -r "name-or-id"` | Resume specific session by name or ID |
| `claude -r "name" "prompt"` | Resume + send prompt |
| `claude --from-pr <PR>` | Resume session linked to a GitHub PR |
| `/resume [session]` (inside) | Resume by name/ID or open picker |

### Rename

| Command | Description |
|---------|-------------|
| `/rename new-name` (inside) | Rename current session |
| `/rename` (inside) | Auto-generate name from conversation |

### Fork / Branch

| Command | Description |
|---------|-------------|
| `claude -r "session" --fork-session` | Resume as a new forked copy |
| `/branch [name]` or `/fork` (inside) | Branch at current point |

### Clear / Reset

| Command | Description |
|---------|-------------|
| `/clear` (inside) | Clear conversation history |
| `/reset` or `/new` (inside) | Aliases for `/clear` |

### Rewind

| Command | Description |
|---------|-------------|
| `/rewind` or `/checkpoint` (inside) | Rewind to a previous point |
| `Esc + Esc` | Shortcut for rewind |

### Export

| Command | Description |
|---------|-------------|
| `/export [filename]` (inside) | Export conversation as plain text |
| `/copy [N]` (inside) | Copy last response to clipboard |

### Delete (Manual)

Session data is stored in two locations:

```bash
# Per-project session data (conversation history)
# Path: ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
# <encoded-cwd> = working directory with non-alphanumeric chars replaced by "-"
# e.g. /Users/admin/my-project → -Users-admin-my-project

ls ~/.claude/projects/                          # List all project folders
ls ~/.claude/projects/-Users-admin-my-project/  # List sessions for a project
rm ~/.claude/projects/-Users-admin-my-project/<session-id>.jsonl  # Delete one session

# Global session index
ls ~/.claude/sessions/              # List session index files
rm ~/.claude/sessions/<id>.json     # Delete a session index entry
```

> **Tip:** Use `claude --resume` first to identify the session ID you want to delete.

### Disable Persistence

```bash
claude -p --no-session-persistence "query"   # Session not saved to disk (print mode only)
```

---

## Slash Commands (Inside Session)

| Command | Description |
|---------|-------------|
| `/help` | Show help |
| `/status` | Version, model, account info |
| `/model [model]` | View or change model |
| `/effort [level]` | Set effort (low/medium/high/max) |
| `/cost` | Token usage stats |
| `/context` | Visualize context window usage |
| `/diff` | Interactive diff viewer |
| `/compact [instructions]` | Compact conversation to free context |
| `/config` or `/settings` | Open settings |
| `/permissions` or `/allowed-tools` | Manage tool permissions |
| `/memory` | Edit CLAUDE.md memory files |
| `/mcp` | Manage MCP server connections |
| `/resume [session]` | Resume a conversation |
| `/rename [name]` | Rename current session |
| `/clear` / `/reset` / `/new` | Clear conversation |
| `/branch [name]` / `/fork` | Branch conversation |
| `/rewind` / `/checkpoint` | Rewind to previous point |
| `/export [file]` | Export as text |
| `/copy [N]` | Copy response to clipboard |
| `/fast` | Toggle fast mode (same model, faster output) |

---

## Common CLI Flags

### Model & Behavior

| Flag | Description |
|------|-------------|
| `--model <model>` | Set model (`sonnet`, `opus`, or full ID like `claude-sonnet-4-6`) |
| `--effort [low\|medium\|high\|max\|auto]` | Effort level (`max` requires Opus) |
| `--verbose` | Verbose logging |
| `--debug [categories]` | Debug mode (e.g. `--debug "api,mcp"`) |
| `--debug-file <path>` | Write debug logs to file |

### Output (Print Mode)

| Flag | Description |
|------|-------------|
| `--output-format [text\|json\|stream-json]` | Output format |
| `--input-format [text\|stream-json]` | Input format |
| `--max-turns <N>` | Limit agentic turns |
| `--max-budget-usd <amount>` | Spending cap |

### Permissions

| Flag | Description |
|------|-------------|
| `--permission-mode <mode>` | `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions` |
| `--dangerously-skip-permissions` | Skip all permission prompts |
| `--allowedTools "Tool1" "Tool2"` | Auto-allow specific tools |
| `--disallowedTools "Tool1"` | Block specific tools |

### System Prompt

| Flag | Description |
|------|-------------|
| `--system-prompt "text"` | Replace entire system prompt |
| `--system-prompt-file <path>` | Load system prompt from file |
| `--append-system-prompt "text"` | Append to default prompt |
| `--append-system-prompt-file <path>` | Append from file |

### Git Worktrees

| Flag | Description |
|------|-------------|
| `-w <name>` or `--worktree <name>` | Start in isolated git worktree |
| `--tmux` | Create tmux session for worktree |

### Other

| Flag | Description |
|------|-------------|
| `--add-dir <path>` | Add extra working directories |
| `--tools "Bash,Edit,Read"` | Restrict available tools |
| `--chrome` / `--no-chrome` | Enable/disable Chrome integration |
| `--settings <path-or-json>` | Load additional settings |
| `--ide` | Auto-connect to IDE |

---

## Keyboard Shortcuts

### General

| Shortcut | Action |
|----------|--------|
| `Ctrl+C` | Cancel current generation |
| `Ctrl+D` | Exit Claude Code |
| `Ctrl+L` | Clear prompt input |
| `Ctrl+R` | Reverse search history |
| `Up/Down` | Navigate command history |

### Mode & Model

| Shortcut | Action |
|----------|--------|
| `Shift+Tab` / `Alt+M` | Cycle permission modes |
| `Alt+P` | Switch model |
| `Alt+T` | Toggle extended thinking |
| `Alt+O` | Toggle fast mode |

### Session

| Shortcut | Action |
|----------|--------|
| `Ctrl+O` | Toggle transcript viewer |
| `Ctrl+B` | Background running tasks |
| `Ctrl+T` | Toggle task list |
| `Esc + Esc` | Rewind / summarize |

### Editing

| Shortcut | Action |
|----------|--------|
| `Ctrl+K` | Delete to end of line |
| `Ctrl+U` | Delete to start of line |
| `Ctrl+Y` | Paste deleted text |
| `\` + `Enter` | New line (multiline input) |

---

## Quick Prefixes

| Prefix | Action |
|--------|--------|
| `/` | Slash commands |
| `!` | Run bash command directly (e.g. `! ls -la`) |
| `@` | File path autocomplete |

---

## Configuration Files

### Directory Structure

```
~/.claude/
  settings.json          # Global user settings
  settings.local.json    # Local overrides (gitignored)
  commands/              # Global slash commands (available everywhere)
    my-command.md
  skills/                # Global auto-triggered skills
    my-skill/
      SKILL.md
  keybindings.json       # Custom keyboard shortcuts
  sessions/              # Session data
  projects/              # Project-specific data

<project>/.claude/
  settings.json          # Project settings (committed to git)
  settings.local.json    # Local project overrides (gitignored)
  commands/              # Project slash commands
    deploy.md
  skills/                # Project auto-triggered skills
    lint/
      SKILL.md
  CLAUDE.md              # Project instructions
```

### settings.json Example

```json
{
  "model": "opus[1m]",
  "effortLevel": "medium",
  "permissions": {
    "allow": ["Bash(git:*)", "Read", "Glob", "Grep"],
    "deny": ["Bash(rm:*)"]
  },
  "env": {
    "MY_VAR": "value"
  }
}
```

---

## Permissions

Claude Code asks for approval before running tools by default. You can loosen or tighten this via CLI flags, in-session commands, or settings files.

### Permission Modes

Cycle modes mid-session with `Shift+Tab`, or set via `--permission-mode <mode>`:

| Mode | Behavior |
|------|----------|
| `default` | Prompt for each tool that isn't pre-allowed |
| `acceptEdits` | Auto-accept file edits, still prompt for Bash/other |
| `plan` | Plan-only — no edits, no commands, just read & propose |
| `auto` | Auto-approve tools matched by allow rules |
| `dontAsk` | Never prompt (approvals fail closed if not allowed) |
| `bypassPermissions` | **Skip all permission checks** (same as `--dangerously-skip-permissions`) |

### `--dangerously-skip-permissions` (YOLO mode)

Bypasses every permission prompt. Equivalent to `--permission-mode bypassPermissions`.

```bash
# One-off: skip all prompts for this session
claude --dangerously-skip-permissions

# Print mode — run fully unattended
claude -p "refactor auth module" --dangerously-skip-permissions

# Combined with other flags
claude --dangerously-skip-permissions --model opus -c
```

**Warning:** Claude can run any command, edit any file, and make network calls without asking. Use only when:
- Running in a sandbox, container, or throwaway VM
- Running on a branch you can easily revert
- The task is low-risk and fully trusted

Never use with `sudo`, on production servers, or in directories you can't afford to lose.

### Managing Permissions Inside a Session

```
/permissions              # Open the permission manager UI
/allowed-tools            # Alias for /permissions
```

From `/permissions` you can add allow/deny/ask rules that get saved to `settings.local.json`.

### Permission Rules — settings.json

Rules use the pattern `Tool(argument-pattern)`. Most specific rule wins; `deny` overrides `allow`.

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Edit",
      "Bash(git:*)",
      "Bash(npm:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "WebFetch(domain:docs.anthropic.com)"
    ],
    "deny": [
      "Bash(rm:*)",
      "Bash(sudo:*)",
      "Bash(curl:*)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(gh:*)"
    ]
  }
}
```

### Allow-All Configurations

**Allow everything (equivalent to YOLO mode, persistent):**

`~/.claude/settings.local.json`:
```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```

**Allow everything except dangerous commands (recommended):**
```json
{
  "permissions": {
    "defaultMode": "acceptEdits",
    "allow": [
      "Read", "Write", "Edit", "Glob", "Grep",
      "Bash(git:*)", "Bash(npm:*)", "Bash(node:*)",
      "Bash(python:*)", "Bash(pytest:*)",
      "Bash(ls:*)", "Bash(cat:*)", "Bash(pwd)",
      "Bash(mkdir:*)", "Bash(mv:*)", "Bash(cp:*)"
    ],
    "deny": [
      "Bash(rm -rf:*)", "Bash(sudo:*)",
      "Bash(curl:* | sh)", "Bash(wget:* | sh)",
      "Read(./.env)", "Read(./.env.*)",
      "Read(**/id_rsa)", "Read(**/.ssh/**)"
    ]
  }
}
```

### settings.json vs settings.local.json

| File | Scope | Git-tracked? | Use for |
|------|-------|-------------|---------|
| `~/.claude/settings.json` | Global user | No (home dir) | Your personal defaults across all projects |
| `~/.claude/settings.local.json` | Global user, local | No | Machine-specific overrides (e.g. this laptop only) |
| `<project>/.claude/settings.json` | Project | **Yes — commit** | Team-shared project rules |
| `<project>/.claude/settings.local.json` | Project, local | **No — gitignored** | Your personal allow-list for this project |

> Claude Code auto-adds `.claude/settings.local.json` to your project's `.gitignore`.

**Typical pattern:** Commit a conservative `settings.json` for the team, keep a permissive `settings.local.json` for yourself.

### CLI Flags — Per-Run Overrides

```bash
# Pre-allow specific tools for this run only
claude --allowedTools "Read" "Glob" "Grep" "Bash(git:*)"

# Block specific tools
claude --disallowedTools "Bash(rm:*)"

# Combine with permission mode
claude --permission-mode acceptEdits --allowedTools "Bash(npm:*)"

# Load an ad-hoc settings file
claude --settings ./my-perms.json

# Inline JSON settings
claude --settings '{"permissions":{"defaultMode":"acceptEdits"}}'
```

### Tool Pattern Reference

| Pattern | Matches |
|---------|---------|
| `Read` | Any Read tool use |
| `Bash(git:*)` | Any bash command starting with `git ` |
| `Bash(git status)` | Exactly `git status` |
| `Bash(npm run test:*)` | `npm run test`, `npm run test:unit`, etc. |
| `Read(./src/**)` | Read any file under `./src/` |
| `Read(./.env)` | Read specifically `./.env` |
| `WebFetch(domain:github.com)` | WebFetch calls to github.com |
| `mcp__server__tool` | A specific MCP tool |

---

## Creating Custom Skills

There are two types of custom skills:

### 1. Slash Commands (`commands/`)

User-invoked via `/command-name`. Placed as `.md` files in `commands/` directory.

**Locations:**

| Scope | Path | Availability |
|-------|------|-------------|
| Global | `~/.claude/commands/my-cmd.md` | All projects |
| Project | `<project>/.claude/commands/my-cmd.md` | This project only |

**Format:**

```markdown
---
description: Short description shown in command list
allowed-tools: "Bash(git:*) Read Edit"
---

Instructions for Claude when this command is invoked.

Use $ARGUMENTS to access anything the user types after the command.
For example: `/my-cmd hello world` sets $ARGUMENTS to "hello world".
```

**Example — `/deploy` command:**

Create `<project>/.claude/commands/deploy.md`:

```markdown
---
description: Build and deploy the application
allowed-tools: "Bash(npm:*) Bash(docker:*) Bash(git:*)"
---

Deploy the application. Parse $ARGUMENTS for target environment.

Steps:
1. Run tests: `npm test`
2. Build: `npm run build`
3. Deploy to the specified environment (default: staging)

If $ARGUMENTS contains "prod" or "production", confirm with the user first.
```

Usage: `/deploy staging` or `/deploy prod`

**Example — `/review` command:**

Create `~/.claude/commands/review.md`:

```markdown
---
description: Review current git changes
allowed-tools: "Bash(git:*) Read"
---

Review the current uncommitted changes:
1. Run `git diff` to see changes
2. Analyze code quality, potential bugs, and style
3. Provide a summary with actionable feedback
```

Usage: `/review`

### 2. Auto-Triggered Skills (`skills/`)

Automatically activated when Claude detects a matching context. Placed in a folder with a `SKILL.md` file.

**Locations:**

| Scope | Path | Availability |
|-------|------|-------------|
| Global | `~/.claude/skills/my-skill/SKILL.md` | All projects |
| Project | `<project>/.claude/skills/my-skill/SKILL.md` | This project only |

**Format:**

```markdown
---
description: When and what this skill does (Claude uses this to decide activation)
allowed-tools: "Bash(specific:*) Edit Read"
---

Instructions for Claude when this skill is activated.

This content guides Claude's behavior automatically —
no slash command needed.
```

**Example — auto lint skill:**

Create `<project>/.claude/skills/lint/SKILL.md`:

```markdown
---
description: Automatically run linter after editing TypeScript files
allowed-tools: "Bash(npx:*)"
---

After editing any .ts or .tsx file, run:
```
npx eslint --fix <changed-file>
```

Report any remaining errors to the user.
```

**Example — global coding standards skill:**

Create `~/.claude/skills/standards/SKILL.md`:

```markdown
---
description: Enforce personal coding standards when writing code
allowed-tools: "Edit Read"
---

When writing or editing code, always:
- Use 2-space indentation
- Add error handling for async operations
- Use descriptive variable names
- Prefer const over let
```

### Slash Commands vs Skills — When to Use Which

| | Slash Commands (`commands/`) | Skills (`skills/`) |
|---|---|---|
| **Triggered by** | User types `/command` | Claude auto-detects context |
| **Use for** | On-demand actions, workflows | Always-on rules, standards |
| **Accepts args** | Yes, via `$ARGUMENTS` | No |
| **Examples** | `/deploy`, `/review`, `/test` | Lint after edit, coding style |

### Frontmatter Options

| Field | Description |
|-------|-------------|
| `description` | What the skill/command does (shown in lists, used for auto-trigger matching) |
| `allowed-tools` | Space-separated tools auto-permitted when active |

**Tool permission patterns for `allowed-tools`:**

```
Read                         # Allow Read tool
Edit                         # Allow Edit tool
Bash(git:*)                  # Allow any bash command starting with "git"
Bash(npm:*)                  # Allow any bash command starting with "npm"
Bash(docker:*)               # Allow docker commands
Bash(ssh:*)                  # Allow ssh commands
Bash(curl:*)                 # Allow curl commands
```

---

## CLAUDE.md — Project Instructions

`CLAUDE.md` files give Claude persistent context about your project. Claude reads these automatically.

### Locations (loaded in order)

| File | Scope |
|------|-------|
| `~/.claude/CLAUDE.md` | Global — all projects |
| `<project>/CLAUDE.md` | Project root |
| `<project>/.claude/CLAUDE.md` | Project (alternative location) |
| `<subdir>/CLAUDE.md` | Subdirectory-specific |

### What to Put in CLAUDE.md

```markdown
# Project Name

## Build & Test
- Build: `npm run build`
- Test: `npm test`
- Single test: `npm test -- --grep "test name"`
- Lint: `npm run lint`

## Architecture
- Frontend: React + TypeScript in `src/`
- API: Express in `api/`
- Database: PostgreSQL with Prisma ORM

## Conventions
- Use kebab-case for file names
- Use PascalCase for React components
- All API responses follow `{ data, error }` shape

## Important Notes
- Never modify migration files directly
- Environment secrets are in 1Password, not .env
```

Edit with: `/memory` inside a session.

---

## Hooks

Hooks run shell commands automatically before/after Claude's tool calls.

### Configure in settings.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'About to edit a file'"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Bash command completed'"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "afplay /System/Library/Sounds/Glass.aiff"
          }
        ]
      }
    ]
  }
}
```

### Hook Events

| Event | When |
|-------|------|
| `PreToolUse` | Before a tool runs |
| `PostToolUse` | After a tool runs |
| `Notification` | When Claude sends a notification |
| `Stop` | When Claude finishes a turn |

### Matcher Patterns

- `""` — match all tools
- `"Edit"` — match specific tool
- `"Bash"` — match Bash tool
- `"mcp:server-name:tool"` — match MCP tool

---

## MCP Servers

Connect external tools via Model Context Protocol.

### Configure in settings.json

```json
{
  "mcpServers": {
    "my-server": {
      "command": "npx",
      "args": ["-y", "my-mcp-server"],
      "env": {
        "API_KEY": "xxx"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
    }
  }
}
```

### Manage inside session

```
/mcp                           # View MCP server status
```
