#!/usr/bin/env bash
# install.sh — install a skill from this repo into ~/.claude/skills/
# Usage: curl -fsSL https://raw.githubusercontent.com/nguyenvanhuy0612/claude-skills/main/install.sh | bash
#        (installs all skills)
# Or:   curl -fsSL .../install.sh | bash -s ssh
#        (installs one skill by name)
set -euo pipefail

REPO="nguyenvanhuy0612/claude-skills"
DEST="$HOME/.claude/skills"
API="https://api.github.com/repos/$REPO/contents"
RAW="https://raw.githubusercontent.com/$REPO/main"
SKILL="${1:-}"

install_skill() {
    local name="$1"
    echo "  [INFO] Installing skill: $name"
    local dir="$DEST/$name"
    mkdir -p "$dir"
    # fetch file list via GitHub API
    curl -fsSL "$API/$name" | \
        grep -o '"name": "[^"]*"' | \
        sed 's/"name": "//;s/"//' | \
        while read -r fname; do
            curl -fsSL "$RAW/$name/$fname" -o "$dir/$fname"
        done
    echo "  [OK]   Installed '$name' → $dir"
}

# discover available skills (dirs in repo root)
mapfile -t skills < <(curl -fsSL "$API" | grep -o '"name": "[^"]*"' | sed 's/"name": "//;s/"//')

if [ -n "$SKILL" ]; then
    install_skill "$SKILL"
else
    for s in "${skills[@]}"; do
        # skip files/hidden entries — only dirs with SKILL.md
        curl -fsSL "$API/$s/SKILL.md" &>/dev/null && install_skill "$s" || true
    done
fi
