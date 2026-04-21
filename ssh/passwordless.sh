#!/usr/bin/env bash
# Usage: ./ssh_passwordless.sh <target-ip> <username> [port] [mac|windows]
set -euo pipefail

TARGET_IP="${1:?Usage: $0 <ip> <user> [port] [mac|windows]}"
TARGET_USER="${2:?Usage: $0 <ip> <user> [port] [mac|windows]}"
PORT="${3:-22}"
TARGET_OS="${4:-windows}"
KEY_FILE="$HOME/.ssh/id_ed25519"

# Generate key if missing
if [ ! -f "$KEY_FILE" ]; then
    ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "$TARGET_USER@$TARGET_IP"
fi

PUB_KEY=$(cat "$KEY_FILE.pub")

# Clear stale host keys
ssh-keygen -R "$TARGET_IP" 2>/dev/null || true
ssh-keygen -R "[$TARGET_IP]:$PORT" 2>/dev/null || true

if [ "$TARGET_OS" = "mac" ]; then
    ssh-copy-id -i "$KEY_FILE.pub" -p "$PORT" "$TARGET_USER@$TARGET_IP"
else
    # Windows target: embed key into script then Base64-encode the whole thing
    SCRIPT=$(cat <<PSEOF
\$key = '$PUB_KEY'
\$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
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
PSEOF
)
    ENCODED=$(printf '%s' "$SCRIPT" | iconv -t UTF-16LE | base64 | tr -d '\n')
    ssh -o StrictHostKeyChecking=no -p "$PORT" "$TARGET_USER@$TARGET_IP" \
        "powershell -EncodedCommand $ENCODED"
fi

# Test passwordless login
echo "Testing passwordless login..."
result=$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
    -i "$KEY_FILE" -p "$PORT" "$TARGET_USER@$TARGET_IP" "echo ok" 2>&1)

if [ "$result" = "ok" ]; then
    echo "Success: ssh -i $KEY_FILE -p $PORT $TARGET_USER@$TARGET_IP"
else
    echo "WARNING: test returned: $result"
    echo "Try: ssh -p $PORT $TARGET_USER@$TARGET_IP"
fi
