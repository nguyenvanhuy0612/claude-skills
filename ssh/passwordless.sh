#!/usr/bin/env bash
# Set up passwordless SSH from this Mac/Linux machine to a remote host.
#
# Just run it — you'll be prompted for host, user, password, and target OS:
#     ./passwordless.sh
#
# Or pass any of them up front to skip the matching prompt:
#     ./passwordless.sh 10.0.0.5 root 22 linux
#
# Usage: ./passwordless.sh [host] [user] [port] [windows|mac|linux] [password]
set -euo pipefail

TARGET_HOST="${1:-}"
TARGET_USER="${2:-}"
PORT="${3:-22}"
TARGET_OS="${4:-}"
TARGET_PASS="${5:-}"
KEY_FILE="$HOME/.ssh/id_ed25519"

# --- Prompt for anything not supplied on the command line ---
if [ -z "$TARGET_HOST" ]; then
    read -r -p "Remote host (IP or name): " TARGET_HOST
    [ -z "$TARGET_HOST" ] && { echo "ERROR: remote host is required." >&2; exit 1; }
fi
if [ -z "$TARGET_USER" ]; then
    read -r -p "Remote username [admin]: " TARGET_USER
    [ -z "$TARGET_USER" ] && TARGET_USER="admin"
fi
if [ -z "$TARGET_OS" ]; then
    read -r -p "Target OS - windows / mac / linux [linux]: " TARGET_OS
    [ -z "$TARGET_OS" ] && TARGET_OS="linux"
fi
TARGET_OS=$(printf '%s' "$TARGET_OS" | tr '[:upper:]' '[:lower:]')
case "$TARGET_OS" in
    windows|mac|linux) ;;
    *) printf 'ERROR: invalid target OS "%s" (use windows|mac|linux)\n' "$TARGET_OS" >&2; exit 1 ;;
esac
if [ -z "$TARGET_PASS" ]; then
    read -r -s -p "Remote password (leave blank to type it at the SSH prompt): " TARGET_PASS
    printf '\n'
fi

# A password means non-interactive auth, which needs sshpass.
if [ -n "$TARGET_PASS" ] && ! command -v sshpass >/dev/null 2>&1; then
    echo "ERROR: a password was given but 'sshpass' is not installed." >&2
    echo "  Install it (macOS: brew install sshpass | Debian/Ubuntu: apt install sshpass)" >&2
    echo "  or re-run and leave the password blank to type it at the SSH prompt." >&2
    exit 1
fi

# run_ssh / run_copy_id: use sshpass when a password is supplied, else plain (interactive).
run_ssh() {
    if [ -n "$TARGET_PASS" ]; then sshpass -p "$TARGET_PASS" ssh "$@"; else ssh "$@"; fi
}
run_copy_id() {
    if [ -n "$TARGET_PASS" ]; then sshpass -p "$TARGET_PASS" ssh-copy-id "$@"; else ssh-copy-id "$@"; fi
}

# --- Generate key if missing ---
if [ ! -f "$KEY_FILE" ]; then
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "$TARGET_USER@$TARGET_HOST"
fi
PUB_KEY=$(cat "$KEY_FILE.pub")

# --- Clear stale host keys ---
ssh-keygen -R "$TARGET_HOST" 2>/dev/null || true
ssh-keygen -R "[$TARGET_HOST]:$PORT" 2>/dev/null || true

SSH_OPTS="-o StrictHostKeyChecking=no -o PasswordAuthentication=yes -o PubkeyAuthentication=no -p $PORT"

if [ "$TARGET_OS" = "mac" ] || [ "$TARGET_OS" = "linux" ]; then
    # Unix target (mac/linux): append the key to ~/.ssh/authorized_keys
    echo "[INFO] Deploying key to $TARGET_OS target..."
    if command -v ssh-copy-id >/dev/null 2>&1; then
        run_copy_id -i "$KEY_FILE.pub" -p "$PORT" "$TARGET_USER@$TARGET_HOST"
    else
        CMD="mkdir -p ~/.ssh && chmod 700 ~/.ssh && grep -qF '$PUB_KEY' ~/.ssh/authorized_keys 2>/dev/null || echo '$PUB_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo done"
        # shellcheck disable=SC2086
        run_ssh $SSH_OPTS "$TARGET_USER@$TARGET_HOST" "$CMD"
    fi
else
    # Windows target: deploy via Base64-encoded PowerShell
    echo "[INFO] Deploying key to windows target..."
    REMOTE_SCRIPT=$(cat <<PSEOF
\$key  = '$PUB_KEY'
\$f    = 'C:\ProgramData\ssh\administrators_authorized_keys'
New-Item -ItemType Directory -Force -Path (Split-Path \$f) | Out-Null
if (-not (Test-Path \$f)) { New-Item \$f -ItemType File -Force | Out-Null }
\$lines = Get-Content \$f -ErrorAction SilentlyContinue
if (\$lines -notcontains \$key) { Add-Content \$f \$key; Write-Host 'Key added.' } else { Write-Host 'Key exists.' }
icacls \$f /inheritance:r /grant 'SYSTEM:(F)' /grant 'Administrators:(F)' | Out-Null
\$uf = "\$env:USERPROFILE\.ssh\authorized_keys"
New-Item -ItemType Directory -Force -Path (Split-Path \$uf) | Out-Null
if (-not (Test-Path \$uf)) { New-Item \$uf -ItemType File -Force | Out-Null }
\$ul = Get-Content \$uf -ErrorAction SilentlyContinue
if (\$ul -notcontains \$key) { Add-Content \$uf \$key }
Write-Host 'done'
PSEOF
)
    ENCODED=$(printf '%s' "$REMOTE_SCRIPT" | iconv -t UTF-16LE | base64 | tr -d '\n')
    # shellcheck disable=SC2086
    run_ssh $SSH_OPTS "$TARGET_USER@$TARGET_HOST" "powershell -EncodedCommand $ENCODED"
fi

echo "[OK] Key deployed."

# --- Test passwordless login ---
# Drop stderr (login banners / TMOUT warnings) and match 'ok' loosely,
# since servers may prepend banner text to stdout.
echo "[INFO] Testing passwordless login..."
result=$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
    -i "$KEY_FILE" -p "$PORT" "$TARGET_USER@$TARGET_HOST" "echo ok" 2>/dev/null)

case "$result" in
    *ok*)
        echo "[OK] Passwordless works: ssh -i $KEY_FILE -p $PORT $TARGET_USER@$TARGET_HOST"
        ;;
    *)
        echo "[WARN] Test returned: $result"
        echo "  Try: ssh -i $KEY_FILE -p $PORT $TARGET_USER@$TARGET_HOST"
        ;;
esac
