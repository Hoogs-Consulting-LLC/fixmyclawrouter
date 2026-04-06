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

# Read state
if ! command -v jq &>/dev/null; then
  echo "  ❌ jq is required for uninstall. Install it: apt install jq / brew install jq"
  exit 1
fi

CONFIG=$(jq -r '.config_path' "$STATE")
BACKUP=$(jq -r '.backup_path' "$STATE")
PRE_HASH=$(jq -r '.pre_install_hash' "$STATE")
POST_HASH=$(jq -r '.post_install_hash // "unknown"' "$STATE")
API_KEY=$(jq -r '.api_key' "$STATE")
INSTALLED_AT=$(jq -r '.installed_at' "$STATE")

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

# Check if config has been modified since we installed
CURRENT_HASH=$(sha256sum "$CONFIG" 2>/dev/null || shasum -a 256 "$CONFIG" 2>/dev/null || echo "unknown")
CURRENT_HASH=$(echo "$CURRENT_HASH" | awk '{print $1}')

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
      TMPFILE=$(mktemp)
      jq 'del(.models.providers["smart-proxy"])' "$CONFIG" > "$TMPFILE"

      # Check what the old default model was
      OLD_DEFAULT=$(jq -r '.agents.defaults.model.primary // empty' "$BACKUP" 2>/dev/null || echo "")
      if [ -n "$OLD_DEFAULT" ]; then
        jq --arg m "$OLD_DEFAULT" '.agents.defaults.model.primary = $m' "$TMPFILE" > "${TMPFILE}.2" && mv "${TMPFILE}.2" "$TMPFILE"
        echo "  Restored default model: $OLD_DEFAULT"
      fi

      mv "$TMPFILE" "$CONFIG"
      echo "  ✅ Removed smart-proxy, kept everything else."
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

# Restore agent models.json files from backups
OPENCLAW_DIR="$(dirname "$CONFIG")"
find "$OPENCLAW_DIR" -name "*.fixmyclawrouter-state" -type f 2>/dev/null | while read -r MSTATE_FILE; do
  MFILE=$(jq -r '.file' "$MSTATE_FILE" 2>/dev/null)
  MBACKUP=$(jq -r '.backup' "$MSTATE_FILE" 2>/dev/null)
  MPRE_HASH=$(jq -r '.pre_hash' "$MSTATE_FILE" 2>/dev/null)
  MPOST_HASH=$(jq -r '.post_hash' "$MSTATE_FILE" 2>/dev/null)

  if [ -z "$MFILE" ] || [ ! -f "$MFILE" ]; then
    continue
  fi

  if [ -n "$MBACKUP" ] && [ -f "$MBACKUP" ]; then
    # Check if the file has been modified since we touched it
    MCURRENT_HASH=$(sha256sum "$MFILE" 2>/dev/null || shasum -a 256 "$MFILE" 2>/dev/null || echo "unknown")
    MCURRENT_HASH=$(echo "$MCURRENT_HASH" | awk '{print $1}')

    if [ "$MCURRENT_HASH" = "$MPOST_HASH" ] || [ "$MPOST_HASH" = "unknown" ]; then
      # Unchanged since install — safe to restore backup
      cp "$MBACKUP" "$MFILE"
      echo "  ✅ Restored: $MFILE"
    else
      echo "  ⚠️  $MFILE was modified since install — skipping (manual cleanup needed)"
    fi
    rm -f "$MBACKUP"
  fi
  rm -f "$MSTATE_FILE"
done

# Clean up state
rm -rf "$(dirname "$STATE")"
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
