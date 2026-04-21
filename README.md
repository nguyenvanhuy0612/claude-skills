# claude-skills

A collection of reusable skill references for Claude Code, organized by topic.

## Skills

| Folder | Description |
|---|---|
| [ssh/](ssh/SKILL.md) | Install OpenSSH, passwordless key setup, and remote command execution (Mac + Windows) |
| [claude-cli/](claude-cli/SKILL.md) | Claude Code CLI — installation, session management, slash commands, and keyboard shortcuts |

## Structure

Each skill lives in its own folder:

```
<skill-name>/
├── SKILL.md          # documentation, patterns, and critical rules
└── *.sh / *.ps1      # helper scripts (if any)
```

## Adding a new skill

1. Create a folder: `mkdir <skill-name>`
2. Add `<skill-name>/SKILL.md` with documentation
3. Add any helper scripts alongside it
4. Add a row to the table above
