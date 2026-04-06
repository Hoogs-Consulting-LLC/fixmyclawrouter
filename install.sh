#!/usr/bin/env bash
set -euo pipefail

PROXY_URL="${PROXY_URL:-https://fixmyclawrouter.com}"
VERSION="2.5.0"

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

# Check for existing install
INSTALL_DIR="$(dirname "$CONFIG")/.fixmyclawrouter"
mkdir -p "$INSTALL_DIR"
EXISTING_KEY=""
if [ -f "$INSTALL_DIR/state.json" ]; then
  EXISTING_KEY=$(grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$INSTALL_DIR/state.json" 2>/dev/null | head -1 | sed 's/.*"api_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

# Register key from server (or re-use existing)
INSTALLER_TOKEN="__INSTALLER_TOKEN__"
HOSTNAME_HASH=$(hostname 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1 || true)
[ -z "$HOSTNAME_HASH" ] && HOSTNAME_HASH=$(hostname 2>/dev/null | shasum -a 256 2>/dev/null | cut -d' ' -f1 || true)
[ -z "$HOSTNAME_HASH" ] && HOSTNAME_HASH="unknown"
OS_TYPE=$(uname -s 2>/dev/null || echo "unknown")
ARCH_TYPE=$(uname -m 2>/dev/null || echo "unknown")

request_key() {
  local RESP
  RESP=$(curl -s -w "\n%{http_code}" -X POST "$PROXY_URL/api/gimme-a-key" \
    -H "Content-Type: application/json" \
    -H "User-Agent: fixmyclawrouter-installer/$VERSION" \
    -H "X-Installer-Token: $INSTALLER_TOKEN" \
    -d "{\"hostname_hash\":\"$HOSTNAME_HASH\",\"os\":\"$OS_TYPE\",\"arch\":\"$ARCH_TYPE\",\"installer_version\":\"$VERSION\"}" \
    2>/dev/null)
  local HTTP_CODE=$(echo "$RESP" | tail -1)
  local BODY=$(echo "$RESP" | sed '$d')

  if [ "$HTTP_CODE" = "201" ]; then
    # Extract api_key from JSON response
    local KEY=""
    if command -v jq &>/dev/null; then
      KEY=$(echo "$BODY" | jq -r '.api_key' 2>/dev/null)
    elif command -v python3 &>/dev/null; then
      KEY=$(echo "$BODY" | python3 -c "import sys,json;print(json.load(sys.stdin).get('api_key',''))" 2>/dev/null)
    else
      KEY=$(echo "$BODY" | grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"api_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if [ -n "$KEY" ] && [ "$KEY" != "null" ]; then
      echo "$KEY"
      return 0
    fi
  fi
  return 1
}

if [ -n "$EXISTING_KEY" ]; then
  echo ""
  echo "  ⚠️  FixMyClawRouter is already installed!"
  echo "  🔑 Existing key: $EXISTING_KEY"
  echo ""
  if [ -t 0 ]; then
    printf "  Generate a new key? (y/N): "
    read -r REGEN
    if [ "$REGEN" = "y" ] || [ "$REGEN" = "Y" ]; then
      API_KEY=$(request_key) || true
      if [ -n "$API_KEY" ]; then
        echo "  🔑 New key: $API_KEY"
      else
        echo "  ❌ Could not register a new key. Keeping existing."
        API_KEY="$EXISTING_KEY"
      fi
    else
      API_KEY="$EXISTING_KEY"
      echo "  🔑 Keeping existing key"
    fi
  else
    API_KEY="$EXISTING_KEY"
    echo "  🔑 Re-using existing key (non-interactive)"
  fi
else
  echo "  🔑 Registering API key..."
  API_KEY=$(request_key) || true
  if [ -n "$API_KEY" ]; then
    echo "  🔑 Your key: $API_KEY"
  else
    echo ""
    echo "  ❌ Could not reach $PROXY_URL to register a key."
    echo "  Visit https://fixmyclawrouter.com to register manually."
    exit 1
  fi
fi

# Backup openclaw.json with timestamp (before touching anything)
BACKUP_TS=$(date -u +%Y%m%d_%H%M%S)
BACKUP="${CONFIG}.before-fixmyclawrouter.${BACKUP_TS}"
cp "$CONFIG" "$BACKUP"

PRE_HASH=$(sha256sum "$CONFIG" 2>/dev/null || shasum -a 256 "$CONFIG" 2>/dev/null || echo "unknown")
PRE_HASH=$(echo "$PRE_HASH" | awk '{print $1}')

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
      .models.mode = "replace" |
      .models.providers["smart-proxy"] = {
        "baseUrl": $url,
        "apiKey": $key,
        "api": "openai-completions",
        "models": [
          {"id": "auto", "name": "Smart Router (auto)", "reasoning": true, "input": ["text"], "maxTokens": 128000}
        ]
      } |
      .agents.defaults.model.primary = "smart-proxy/auto" |
      .agents.defaults.model.fallbacks = ["smart-proxy/auto"] |
      if .agents.list then
        .agents.list = [.agents.list[] |
          if .id == "main" then .model = "smart-proxy/auto" else . end
        ]
      else . end
    ' "$CONFIG" > "$TMPFILE" && mv "$TMPFILE" "$CONFIG"
    return 0
  fi

  if command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$CONFIG') as f: cfg = json.load(f)
cfg.setdefault('models', {})['mode'] = 'replace'
cfg['models'].setdefault('providers', {})['smart-proxy'] = {
  'baseUrl': '$url', 'apiKey': '$key', 'api': 'openai-completions',
  'models': [{'id': 'auto', 'name': 'Smart Router (auto)', 'reasoning': True, 'input': ['text'], 'maxTokens': 128000}]
}
cfg.setdefault('agents', {}).setdefault('defaults', {}).setdefault('model', {})['primary'] = 'smart-proxy/auto'
cfg['agents']['defaults']['model']['fallbacks'] = ['smart-proxy/auto']
for agent in cfg.get('agents', {}).get('list', []):
    if agent.get('id') == 'main':
        agent['model'] = 'smart-proxy/auto'
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
if (cfg.agents.list) {
  for (const agent of cfg.agents.list) {
    if (agent.id === 'main') agent.model = 'smart-proxy/auto';
  }
}
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

# Print summary BEFORE bouncing the gateway (the bounce may kill our shell session)
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║  ✅ FixMyClawRouter installed! You're good to go.  ║"
echo "  ║                                                    ║"
echo "  ║  Your OpenClaw now routes through our smart        ║"
echo "  ║  proxy. Simple stuff → free models. Complex        ║"
echo "  ║  stuff → best available.                           ║"
echo "  ║                                                    ║"
echo "  ║  🔑 Your key: $API_KEY"
echo "  ║                                                    ║"
echo "  ║  ⚡ Claim your key for better performance:         ║"
echo "  ║  $PROXY_URL/claim?key=$API_KEY"
echo "  ║                                                    ║"
echo "  ║  Claiming verifies your email and upgrades you     ║"
echo "  ║  from anonymous to free tier — faster responses,   ║"
echo "  ║  higher limits, and a dashboard to manage it all.  ║"
echo "  ║                                                    ║"
echo "  ║  Don't like it? No hard feelings:                  ║"
echo "  ║  curl -fsSL $PROXY_URL/nah-i-didnt-like-it.sh | bash"
echo "  ║                                                    ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
echo "  🔄 Bouncing OpenClaw gateway to load new config..."
echo "     (your shell session may disconnect — that's normal)"
echo ""

# Bounce gateway: stop saves state, SIGHUP tells the process to reload.
# Works on Docker (process manager restarts it) and Mac Mini (process reloads).
# Background subshell so script exits cleanly even if it disrupts the session.
(openclaw gateway stop 2>/dev/null || true; sleep 1; PIDS=$(pgrep -f "node.*gateway" 2>/dev/null || echo ""); [ -n "$PIDS" ] && kill -HUP $PIDS 2>/dev/null; true) &
