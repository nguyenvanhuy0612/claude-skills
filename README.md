# claude-skills

A collection of reusable Claude Code skills by [@nguyenvanhuy0612](https://github.com/nguyenvanhuy0612).

## Skills

| Name | Description |
|---|---|
| [ssh](ssh/SKILL.md) | Install OpenSSH, passwordless key setup (SSH_ASKPASS), and remote command execution — Mac + Windows |
| [claude-cli](claude-cli/SKILL.md) | Claude Code CLI — installation, session management, slash commands, keyboard shortcuts |

## Install

### Windows (PowerShell)

Install one skill:
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/nguyenvanhuy0612/claude-skills/main/install.ps1))) ssh
```

Install all skills:
```powershell
irm https://raw.githubusercontent.com/nguyenvanhuy0612/claude-skills/main/install.ps1 | iex
```

### Mac / Linux

Install one skill:
```bash
curl -fsSL https://raw.githubusercontent.com/nguyenvanhuy0612/claude-skills/main/install.sh | bash -s ssh
```

Install all skills:
```bash
curl -fsSL https://raw.githubusercontent.com/nguyenvanhuy0612/claude-skills/main/install.sh | bash
```

Skills are installed to `~/.claude/skills/<name>/` and available immediately in the current Claude Code session.

## Structure

Each skill lives in its own folder:

```
<skill-name>/
├── SKILL.md          # documentation, patterns, and critical rules
└── *.sh / *.ps1      # helper scripts (if any)
```

## Adding a new skill

1. Create a folder: `mkdir <skill-name>`
2. Add `<skill-name>/SKILL.md` with frontmatter `name:` and `description:`
3. Add any helper scripts alongside it
4. Add a row to the Skills table above
