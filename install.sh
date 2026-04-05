#!/usr/bin/env bash
set -euo pipefail

PROXY_URL="${PROXY_URL:-https://fixmyclawrouter.com}"
VERSION="1.0.0"

echo ""
echo "  🔧 FixMyClawRouter — Smart LLM Router for OpenClaw"
echo "  ────────────────────────────────────────────────────"
echo "  Version: $VERSION"
echo ""

# Terms acceptance
echo "  📋 By installing FixMyClawRouter, you agree to our:"
echo ""
echo "     Terms of Service:  https://fixmyclawrouter.com/terms"
echo "     Privacy Policy:    https://fixmyclawrouter.com/privacy"
echo ""
echo "  Summary: We route your requests to LLM providers. Aggregated,"
echo "  anonymized usage data may be used to improve our services"
echo "  and for research purposes. No PII or raw prompts are ever shared."
echo ""

if [ -t 0 ]; then
  # Interactive terminal — ask for consent
  printf "  Type 'I agree' to continue: "
  read -r CONSENT
  if [ "$CONSENT" != "I agree" ] && [ "$CONSENT" != "i agree" ] && [ "$CONSENT" != "I AGREE" ]; then
    echo ""
    echo "  ❌ Installation cancelled. You must agree to the terms to continue."
    echo ""
    exit 1
  fi
  echo ""
else
  # Non-interactive (piped) — show terms and continue with notice
  echo "  ⚠️  Running non-interactively. By continuing, you accept the terms above."
  echo "  To review first: curl -fsSL https://fixmyclawrouter.com/install.sh > install.sh && bash install.sh"
  echo ""
  sleep 2
fi

# Find openclaw config
CONFIG=""
for path in "$HOME/.openclaw/openclaw.json" "/home/node/.openclaw/openclaw.json" "${OPENCLAW_HOME:-/dev/null}/openclaw.json"; do
  if [ -f "$path" ]; then
    CONFIG="$path"
    break
  fi
done

if [ -z "$CONFIG" ]; then
  echo "  ❌ Could not find openclaw.json"
  echo "  Checked: ~/.openclaw/openclaw.json"
  echo ""
  echo "  Set OPENCLAW_HOME or run this from your OpenClaw directory."
  exit 1
fi

echo "  ✅ Found OpenClaw config: $CONFIG"

# Generate unique key
API_KEY="fcr-live-$(openssl rand -hex 16 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 32)"
echo "  🔑 Your key: $API_KEY"

# Save pre-install hash + backup
INSTALL_DIR="$(dirname "$CONFIG")/.fixmyclawrouter"
mkdir -p "$INSTALL_DIR"
PRE_HASH=$(sha256sum "$CONFIG" 2>/dev/null || shasum -a 256 "$CONFIG" 2>/dev/null || echo "unknown")
PRE_HASH=$(echo "$PRE_HASH" | awk '{print $1}')

# Backup
BACKUP="${CONFIG}.before-fixmyclawrouter"
cp "$CONFIG" "$BACKUP"

# Save install state
cat > "$INSTALL_DIR/state.json" << EOFSTATE
{
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "$VERSION",
  "api_key": "$API_KEY",
  "config_path": "$CONFIG",
  "backup_path": "$BACKUP",
  "pre_install_hash": "$PRE_HASH",
  "proxy_url": "$PROXY_URL"
}
EOFSTATE

echo "  📋 Backup saved: $BACKUP"
echo ""

# Update openclaw.json — try jq first, then python3, then node
update_config() {
  local url="$PROXY_URL/v1"
  local key="$API_KEY"
  
  if command -v jq &>/dev/null; then
    TMPFILE=$(mktemp)
    jq --arg url "$url" --arg key "$key" '
      # Set mode to replace so only our provider is used
      .models.mode = "replace" |
      # Keep existing providers but add ours
      .models.providers["smart-proxy"] = {
        "baseUrl": $url,
        "apiKey": $key,
        "api": "openai-completions",
        "models": [
          {"id": "auto", "name": "Smart Router (auto)", "reasoning": true, "input": ["text"], "maxTokens": 128000}
        ]
      } |
      # Set as primary model
      .agents.defaults.model.primary = "smart-proxy/auto" |
      # Clear fallbacks so it doesnt revert to old models
      .agents.defaults.model.fallbacks = ["smart-proxy/auto"]
    ' "$CONFIG" > "$TMPFILE" && mv "$TMPFILE" "$CONFIG"
    return 0
  fi

  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open('$CONFIG') as f: cfg = json.load(f)
cfg.setdefault('models', {})['mode'] = 'replace'
cfg['models'].setdefault('providers', {})['smart-proxy'] = {
  'baseUrl': '$url', 'apiKey': '$key', 'api': 'openai-completions',
  'models': [{'id': 'auto', 'name': 'Smart Router (auto)', 'reasoning': True, 'input': ['text'], 'maxTokens': 128000}]
}
cfg.setdefault('agents', {}).setdefault('defaults', {}).setdefault('model', {})['primary'] = 'smart-proxy/auto'
cfg['agents']['defaults']['model']['fallbacks'] = ['smart-proxy/auto']
with open('$CONFIG', 'w') as f: json.dump(cfg, f, indent=2)
" && return 0
  fi

  if command -v node &>/dev/null; then
    node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
if (!cfg.models) cfg.models = {};
cfg.models.mode = 'replace';
if (!cfg.models.providers) cfg.models.providers = {};
cfg.models.providers['smart-proxy'] = {
  baseUrl: '$url', apiKey: '$key', api: 'openai-completions',
  models: [{id: 'auto', name: 'Smart Router (auto)', reasoning: true, input: ['text'], maxTokens: 128000}]
};
if (!cfg.agents) cfg.agents = {};
if (!cfg.agents.defaults) cfg.agents.defaults = {};
if (!cfg.agents.defaults.model) cfg.agents.defaults.model = {};
cfg.agents.defaults.model.primary = 'smart-proxy/auto';
cfg.agents.defaults.model.fallbacks = ['smart-proxy/auto'];
fs.writeFileSync('$CONFIG', JSON.stringify(cfg, null, 2));
" && return 0
  fi

  return 1
}

if update_config; then
  echo "  ✅ OpenClaw config updated!"
else
  echo "  ⚠️  Could not update config (need jq, python3, or node)."
  echo "  Add this manually to your openclaw.json providers:"
  echo ""
  echo '    "smart-proxy": {'
  echo "      \"baseUrl\": \"$PROXY_URL/v1\","
  echo "      \"apiKey\": \"$API_KEY\","
  echo '      "api": "openai-completions",'
  echo '      "models": [{"id": "auto", "name": "Smart Router (auto)"}]'
  echo '    }'
  exit 1
fi

# Post-install hash
POST_HASH=$(sha256sum "$CONFIG" 2>/dev/null || shasum -a 256 "$CONFIG" 2>/dev/null || echo "unknown")
POST_HASH=$(echo "$POST_HASH" | awk '{print $1}')

# Update state with post-install hash
update_state() {
  if command -v jq &>/dev/null; then
    TMPSTATE=$(mktemp)
    jq --arg h "$POST_HASH" '.post_install_hash = $h' "$INSTALL_DIR/state.json" > "$TMPSTATE" && mv "$TMPSTATE" "$INSTALL_DIR/state.json"
  elif command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$INSTALL_DIR/state.json') as f: s = json.load(f)
s['post_install_hash'] = '$POST_HASH'
with open('$INSTALL_DIR/state.json', 'w') as f: json.dump(s, f, indent=2)
"
  elif command -v node &>/dev/null; then
    node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('$INSTALL_DIR/state.json', 'utf8'));
s.post_install_hash = '$POST_HASH';
fs.writeFileSync('$INSTALL_DIR/state.json', JSON.stringify(s, null, 2));
"
  fi
}
update_state

echo ""
# Restart OpenClaw to pick up config changes
echo "  🔄 Restarting OpenClaw..."
if command -v openclaw &>/dev/null; then
  openclaw gateway restart 2>/dev/null && echo "  ✅ OpenClaw restarted!" || echo "  ⚠️  Could not restart OpenClaw. Please restart manually: openclaw gateway restart"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q openclaw; then
  docker restart openclaw 2>/dev/null && echo "  ✅ OpenClaw container restarted!" || echo "  ⚠️  Could not restart container. Please restart manually."
else
  echo "  ⚠️  Please restart OpenClaw to apply changes: openclaw gateway restart"
fi
echo ""

echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  ✅ FixMyClawRouter installed!                   ║"
echo "  ║                                                  ║"
echo "  ║  Your OpenClaw now routes through our smart      ║"
echo "  ║  proxy. Simple stuff → free models. Complex      ║"
echo "  ║  stuff → best available.                         ║"
echo "  ║                                                  ║"
echo "  ║  📊 Claim your dashboard:                        ║"
echo "  ║  $PROXY_URL/claim?key=$API_KEY"
echo "  ║                                                  ║"
echo "  ║  🔑 Your key: $API_KEY"
echo "  ║                                                  ║"
echo "  ║  Don't like it? No hard feelings:                ║"
echo "  ║  curl -fsSL $PROXY_URL/nah-i-didnt-like-it.sh | bash"
echo "  ║                                                  ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo ""
