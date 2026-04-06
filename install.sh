#!/usr/bin/env bash
set -euo pipefail

PROXY_URL="${PROXY_URL:-https://fixmyclawrouter.com}"
VERSION="2.4.0"

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

# Check for existing install
INSTALL_DIR="$(dirname "$CONFIG")/.fixmyclawrouter"
mkdir -p "$INSTALL_DIR"
EXISTING_KEY=""
if [ -f "$INSTALL_DIR/state.json" ]; then
  # Try to extract existing key
  EXISTING_KEY=$(grep -o '"api_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$INSTALL_DIR/state.json" 2>/dev/null | head -1 | sed 's/.*"api_key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

if [ -n "$EXISTING_KEY" ]; then
  echo ""
  echo "  ⚠️  FixMyClawRouter is already installed!"
  echo "  🔑 Existing key: $EXISTING_KEY"
  echo ""
  if [ -t 0 ]; then
    printf "  Generate a new key? (y/N): "
    read -r REGEN
    if [ "$REGEN" = "y" ] || [ "$REGEN" = "Y" ]; then
      API_KEY="fcr-live-$(openssl rand -hex 16 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 32)"
      echo "  🔑 New key: $API_KEY"
    else
      API_KEY="$EXISTING_KEY"
      echo "  🔑 Keeping existing key"
    fi
  else
    API_KEY="$EXISTING_KEY"
    echo "  🔑 Re-using existing key (non-interactive)"
  fi
else
  API_KEY="fcr-live-$(openssl rand -hex 16 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 32)"
  echo "  🔑 Your key: $API_KEY"
fi

# Save pre-install hash + backup
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
      # Add our provider
      .models.providers["smart-proxy"] = {
        "baseUrl": $url,
        "apiKey": $key,
        "api": "openai-completions",
        "models": [
          {"id": "auto", "name": "Smart Router (auto)", "reasoning": true, "input": ["text"], "maxTokens": 128000}
        ]
      } |
      # Set as primary model in defaults
      .agents.defaults.model.primary = "smart-proxy/auto" |
      .agents.defaults.model.fallbacks = ["smart-proxy/auto"] |
      # Override per-agent model in agents.list (e.g. main agent)
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

# Update any agent models.json files that contain our API key
# OpenClaw caches model config in agents/*/agent/models.json
# We backup + hash each one just like we do for openclaw.json
OPENCLAW_DIR="$(dirname "$CONFIG")"
MODELS_FILES_JSON="[]"
find "$OPENCLAW_DIR" -path "*/agent/models.json" -type f 2>/dev/null | while read -r MODELS_FILE; do
  if grep -q "smart-proxy\|fixmyclawrouter\|fcr-live-" "$MODELS_FILE" 2>/dev/null; then
    # Backup with hash
    MODELS_BACKUP="${MODELS_FILE}.before-fixmyclawrouter"
    cp "$MODELS_FILE" "$MODELS_BACKUP"
    MODELS_PRE_HASH=$(sha256sum "$MODELS_FILE" 2>/dev/null || shasum -a 256 "$MODELS_FILE" 2>/dev/null || echo "unknown")
    MODELS_PRE_HASH=$(echo "$MODELS_PRE_HASH" | awk '{print $1}')
    echo "  📋 Backup: $MODELS_BACKUP"

    # Update the API key
    if command -v jq &>/dev/null; then
      TMPMOD=$(mktemp)
      jq --arg key "$API_KEY" '
        if .providers then
          .providers = (.providers | to_entries | map(
            if .value.apiKey and (.value.apiKey | test("^fcr-live-")) then .value.apiKey = $key else . end
          ) | from_entries)
        else . end
      ' "$MODELS_FILE" > "$TMPMOD" && mv "$TMPMOD" "$MODELS_FILE"
    elif command -v python3 &>/dev/null; then
      python3 -c "
import json
with open('$MODELS_FILE') as f: cfg = json.load(f)
for p in cfg.get('providers', {}).values():
    if isinstance(p, dict) and p.get('apiKey', '').startswith('fcr-live-'):
        p['apiKey'] = '$API_KEY'
with open('$MODELS_FILE', 'w') as f: json.dump(cfg, f, indent=2)
"
    elif command -v node &>/dev/null; then
      node -e "
const fs = require('fs');
const cfg = JSON.parse(fs.readFileSync('$MODELS_FILE', 'utf8'));
for (const p of Object.values(cfg.providers || {})) {
  if (p.apiKey && p.apiKey.startsWith('fcr-live-')) p.apiKey = '$API_KEY';
}
fs.writeFileSync('$MODELS_FILE', JSON.stringify(cfg, null, 2));
"
    fi

    MODELS_POST_HASH=$(sha256sum "$MODELS_FILE" 2>/dev/null || shasum -a 256 "$MODELS_FILE" 2>/dev/null || echo "unknown")
    MODELS_POST_HASH=$(echo "$MODELS_POST_HASH" | awk '{print $1}')

    # Save models.json state to its own state file alongside the backup
    cat > "${MODELS_FILE}.fixmyclawrouter-state" << EOFMSTATE
{
  "file": "$MODELS_FILE",
  "backup": "$MODELS_BACKUP",
  "pre_hash": "$MODELS_PRE_HASH",
  "post_hash": "$MODELS_POST_HASH"
}
EOFMSTATE
    echo "  ✅ Updated: $MODELS_FILE"
  fi
done

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
