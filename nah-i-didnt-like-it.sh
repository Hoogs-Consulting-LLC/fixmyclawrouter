#!/usr/bin/env bash
set -euo pipefail

echo ""
echo "  😢 FixMyClawRouter — Uninstaller"
echo "  ────────────────────────────────────────────────────"
echo "  No hard feelings. We get it."
echo ""

# Find install state
STATE=""
for path in "$HOME/.openclaw/.fixmyclawrouter/state.json" "/home/node/.openclaw/.fixmyclawrouter/state.json" "${OPENCLAW_HOME:-/dev/null}/.fixmyclawrouter/state.json"; do
  if [ -f "$path" ]; then
    STATE="$path"
    break
  fi
done

if [ -z "$STATE" ]; then
  echo "  🤔 Hmm, can't find the install state."
  echo "  Looks like FixMyClawRouter wasn't installed via our script,"
  echo "  or you already uninstalled it."
  echo ""
  echo "  If you installed manually, just remove the \"smart-proxy\" block"
  echo "  from your openclaw.json and revert agents.defaults.model.primary."
  exit 1
fi

echo "  ✅ Found install state: $STATE"

# Helper: read a JSON string value without jq
json_val() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null | head -1 | sed "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

# Read state — try jq first, fall back to grep/sed
if command -v jq &>/dev/null; then
  CONFIG=$(jq -r '.config_path' "$STATE")
  BACKUP=$(jq -r '.backup_path' "$STATE")
  PRE_HASH=$(jq -r '.pre_install_hash' "$STATE")
  POST_HASH=$(jq -r '.post_install_hash // "unknown"' "$STATE")
  API_KEY=$(jq -r '.api_key' "$STATE")
  INSTALLED_AT=$(jq -r '.installed_at' "$STATE")
else
  CONFIG=$(json_val config_path "$STATE")
  BACKUP=$(json_val backup_path "$STATE")
  PRE_HASH=$(json_val pre_install_hash "$STATE")
  POST_HASH=$(json_val post_install_hash "$STATE")
  API_KEY=$(json_val api_key "$STATE")
  INSTALLED_AT=$(json_val installed_at "$STATE")
  [ -z "$POST_HASH" ] && POST_HASH="unknown"
fi

echo "  📄 Config: $CONFIG"
echo "  📋 Backup: $BACKUP"
echo "  🕐 Installed: $INSTALLED_AT"
echo "  🔑 Key: ${API_KEY:0:20}..."
echo ""

# Check if backup exists
if [ ! -f "$BACKUP" ]; then
  echo "  ❌ Backup file not found: $BACKUP"
  echo "  Can't auto-revert. You'll need to manually remove the smart-proxy"
  echo "  provider from your openclaw.json."
  exit 1
fi

# Stop OpenClaw before editing config
echo "  🛑 Stopping OpenClaw..."
if command -v openclaw &>/dev/null; then
  openclaw gateway stop 2>/dev/null && echo "  ✅ OpenClaw stopped." || echo "  ⚠️  Could not stop OpenClaw (may not be running)."
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q openclaw; then
  docker stop openclaw 2>/dev/null && echo "  ✅ OpenClaw container stopped." || echo "  ⚠️  Could not stop container."
else
  echo "  ℹ️  OpenClaw not detected as running."
fi
echo ""

# Check if config has been modified since we installed
CURRENT_HASH=$(sha256sum "$CONFIG" 2>/dev/null || shasum -a 256 "$CONFIG" 2>/dev/null || echo "unknown")
CURRENT_HASH=$(echo "$CURRENT_HASH" | awk '{print $1}')

# Helper: surgically remove smart-proxy from config (jq / python3 / node)
surgical_remove() {
  if command -v jq &>/dev/null; then
    TMPFILE=$(mktemp)
    jq 'del(.models.providers["smart-proxy"])' "$CONFIG" > "$TMPFILE"
    # Restore old default model from backup
    OLD_DEFAULT=""
    if command -v jq &>/dev/null; then
      OLD_DEFAULT=$(jq -r '.agents.defaults.model.primary // empty' "$BACKUP" 2>/dev/null || echo "")
    fi
    if [ -n "$OLD_DEFAULT" ]; then
      jq --arg m "$OLD_DEFAULT" '.agents.defaults.model.primary = $m' "$TMPFILE" > "${TMPFILE}.2" && mv "${TMPFILE}.2" "$TMPFILE"
      echo "  Restored default model: $OLD_DEFAULT"
    fi
    mv "$TMPFILE" "$CONFIG"
    return 0
  fi

  if command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$CONFIG') as f: cfg = json.load(f)
cfg.get('models', {}).get('providers', {}).pop('smart-proxy', None)
# Try to restore old default from backup
try:
    with open('$BACKUP') as f: bak = json.load(f)
    old = bak.get('agents', {}).get('defaults', {}).get('model', {}).get('primary', '')
    if old:
        cfg.setdefault('agents', {}).setdefault('defaults', {}).setdefault('model', {})['primary'] = old
        print('  Restored default model: ' + old)
except: pass
with open('$CONFIG', 'w') as f: json.dump(cfg, f, indent=2)
" && return 0
  fi

  if command -v node &>/dev/null; then
    node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
if (cfg.models?.providers) delete cfg.models.providers['smart-proxy'];
try {
  const bak = JSON.parse(fs.readFileSync('$BACKUP', 'utf8'));
  const old = bak?.agents?.defaults?.model?.primary;
  if (old) { cfg.agents.defaults.model.primary = old; console.log('  Restored default model: ' + old); }
} catch {}
fs.writeFileSync('$CONFIG', JSON.stringify(cfg, null, 2));
" && return 0
  fi

  echo "  ❌ Need jq, python3, or node for surgical remove."
  return 1
}

if [ "$CURRENT_HASH" != "$POST_HASH" ] && [ "$POST_HASH" != "unknown" ]; then
  echo "  ⚠️  Your openclaw.json has been modified since installation!"
  echo ""
  echo "  This means you (or OpenClaw) made changes after FixMyClawRouter"
  echo "  was installed. Reverting to the backup will LOSE those changes."
  echo ""
  echo "  Options:"
  echo "    1) Revert anyway (you'll lose post-install changes)"
  echo "    2) Just remove the smart-proxy block (keeps your other changes)"
  echo "    3) Cancel"
  echo ""
  read -p "  Choose [1/2/3]: " CHOICE

  case "$CHOICE" in
    1)
      echo ""
      echo "  Rolling back to pre-install backup..."
      cp "$BACKUP" "$CONFIG"
      echo "  ✅ Reverted to backup."
      ;;
    2)
      echo ""
      echo "  Surgically removing smart-proxy..."
      if surgical_remove; then
        echo "  ✅ Removed smart-proxy, kept everything else."
      else
        echo "  ❌ Surgical remove failed. Please remove smart-proxy from openclaw.json manually."
      fi
      ;;
    3|*)
      echo "  Cancelled. Nothing changed."
      exit 0
      ;;
  esac
else
  # Config unchanged since install — safe to revert
  cp "$BACKUP" "$CONFIG"
  echo "  ✅ Reverted to pre-install backup."
fi

# Clean up state
rm -rf "$(dirname "$STATE")"

# Start OpenClaw with restored config
echo ""
echo "  🔄 Starting OpenClaw..."
if command -v openclaw &>/dev/null; then
  openclaw gateway start 2>/dev/null && echo "  ✅ OpenClaw started!" || echo "  ⚠️  Could not start OpenClaw. Please start manually: openclaw gateway start"
elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q openclaw; then
  docker start openclaw 2>/dev/null && echo "  ✅ OpenClaw container started!" || echo "  ⚠️  Could not start container. Please start manually."
else
  echo "  ⚠️  Please start OpenClaw to apply changes: openclaw gateway start"
fi

echo ""
echo "  ────────────────────────────────────────────────────"
echo ""
echo "  ✅ FixMyClawRouter has been removed."
echo ""
echo "  Your OpenClaw config is back to how it was."
echo ""
echo "  If you change your mind, you know where to find us:"
echo "  curl -fsSL https://fixmyclawrouter.com/install.sh | bash"
echo ""
echo "  No hard feelings. Seriously. 🤝"
echo ""
echo "  ────────────────────────────────────────────────────"
echo ""
