#!/usr/bin/env bash
# cc-profiles - Claude Code multi-model profile manager
# https://github.com/dongdada29/cc-profiles
#
# Run different models in different terminal windows without global config conflicts.
# Each profile sets ANTHROPIC_BASE_URL, ANTHROPIC_API_KEY, ANTHROPIC_MODEL per shell process.

set -euo pipefail

CC_PROFILES_VERSION="0.1.0"
CC_PROFILES_DIR="${CC_PROFILES_DIR:-$HOME/.claude/profiles}"
CC_PROFILES_CONF="$CC_PROFILES_DIR/profiles.json"
CC_PROFS_BIN="${CC_PROFS_BIN:-claude}"

# ─── Colors ───────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_R="\033[0;31m" C_G="\033[0;32m" C_Y="\033[0;33m" C_C="\033[0;36m" C_B="\033[1m" C_X="\033[0m"
else
  C_R="" C_G="" C_Y="" C_C="" C_B="" C_X=""
fi

_info()  { echo -e "${C_G}✔${C_X} $*"; }
_warn()  { echo -e "${C_Y}⚠${C_X} $*"; }
_err()   { echo -e "${C_R}✘${C_X} $*" >&2; }

# ─── JSON helpers (python3 required) ──────────────────────
_jq() {
  python3 -c "import json,sys; d=json.load(sys.stdin); $1" 2>/dev/null
}

_jq_file() {
  python3 -c "import json; d=json.load(open('$1')); $2" 2>/dev/null
}

# ─── Init config ──────────────────────────────────────────
cc_profiles_init() {
  if [[ ! -f "$CC_PROFILES_CONF" ]]; then
    mkdir -p "$CC_PROFILES_DIR"
    cat > "$CC_PROFILES_CONF" << 'DEFAULTS'
{
  "current": "glm",
  "profiles": {
    "glm": {
      "name": "GLM-5.1",
      "base_url": "https://open.bigmodel.cn/api/anthropic",
      "api_key": "",
      "model": "glm-5.1"
    },
    "deepseek": {
      "name": "DeepSeek-v4-pro",
      "base_url": "https://api.deepseek.com",
      "api_key": "",
      "model": "deepseek-v4-pro"
    },
    "mimo": {
      "name": "Mimo-v2.5",
      "base_url": "https://api.mimo.com/v1",
      "api_key": "",
      "model": "mimo-v2.5"
    }
  }
}
DEFAULTS
    _info "Created $CC_PROFILES_CONF"
    _warn "Edit it to fill in your API keys"
    return 1
  fi
  return 0
}

# ─── List profiles ────────────────────────────────────────
cc_profiles_list() {
  cc_profiles_init || return 0
  local current
  current=$(_jq_file "$CC_PROFILES_CONF" "print(d.get('current',''))")
  echo -e "${C_B}Claude Code Profiles:${C_X}"
  _jq_file "$CC_PROFILES_CONF" "
for k,v in d.get('profiles',{}).items():
    marker = ' ← current' if k == '$current' else ''
    key_s = '🔑' if v.get('api_key') else '❌ no key'
    print(f'  {C_C}{k:14s}{C_X} → {v.get(\"name\",\"?\"):22s} [{v.get(\"model\",\"?\")}]  {key_s}{marker}')
" | while IFS= read -r line; do echo -e "$line"; done
}

# ─── Sync from settings.json ──────────────────────────────
cc_profiles_sync() {
  cc_profiles_init || return 0
  local settings="$HOME/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then
    _err "No $settings found"
    return 1
  fi

  local base_url api_key model
  base_url=$(_jq_file "$settings" "print(d.get('env',{}).get('ANTHROPIC_BASE_URL',''))")
  api_key=$(_jq_file "$settings" "print(d.get('env',{}).get('ANTHROPIC_AUTH_TOKEN','') or d.get('env',{}).get('ANTHROPIC_API_KEY',''))")
  model=$(_jq_file "$settings" "print(d.get('env',{}).get('ANTHROPIC_MODEL',''))")

  if [[ -z "$model" ]]; then
    _err "No model config found in settings.json"
    return 1
  fi

  echo -e "Current ${C_B}claude-code${C_X} config:"
  echo "  Base URL: $base_url"
  echo "  Model:    $model"
  echo "  API Key:  ${api_key:0:12}..."
  echo ""
  read -rp "Save as profile name [synced]: " name
  name="${name:-synced}"
  name="${name//[^a-zA-Z0-9_-]/_}"

  python3 -c "
import json
d = json.load(open('$CC_PROFILES_CONF'))
d['profiles']['$name'] = {
    'name': '$model (synced)',
    'base_url': '$base_url',
    'api_key': '$api_key',
    'model': '$model'
}
json.dump(d, open('$CC_PROFILES_CONF','w'), indent=2, ensure_ascii=False)
"
  _info "Saved as profile: $name"
}

# ─── Add profile ──────────────────────────────────────────
cc_profiles_add() {
  cc_profiles_init || return 0
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    read -rp "Profile key (e.g. glm, deepseek): " name
  fi
  name="${name//[^a-zA-Z0-9_-]/_}"
  [[ -z "$name" ]] && { _err "Profile key required"; return 1; }

  read -rp "Display name [e.g. GLM-5.1]: " display_name
  read -rp "API Base URL: " base_url
  read -rp "API Key: " api_key
  read -rp "Model ID: " model

  python3 -c "
import json
d = json.load(open('$CC_PROFILES_CONF'))
d['profiles']['$name'] = {
    'name': '$display_name',
    'base_url': '$base_url',
    'api_key': '$api_key',
    'model': '$model'
}
json.dump(d, open('$CC_PROFILES_CONF','w'), indent=2, ensure_ascii=False)
"
  _info "Added profile: $name → $display_name"
  echo "Re-source this script to load new alias: source $(cc_profiles_script_path)"
}

# ─── Remove profile ───────────────────────────────────────
cc_profiles_remove() {
  cc_profiles_init || return 0
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    cc_profiles_list
    read -rp "Profile key to remove: " name
  fi
  python3 -c "
import json
d = json.load(open('$CC_PROFILES_CONF'))
if '$name' in d.get('profiles',{}):
    del d['profiles']['$name']
    json.dump(d, open('$CC_PROFILES_CONF','w'), indent=2, ensure_ascii=False)
    print('removed')
else:
    print('not_found')
"
}

# ─── Edit config ──────────────────────────────────────────
cc_profiles_edit() {
  ${EDITOR:-vim} "$CC_PROFILES_CONF"
}

# ─── Generate aliases ─────────────────────────────────────
cc_profiles_load() {
  cc_profiles_init 2>/dev/null || return 0
  _jq_file "$CC_PROFILES_CONF" "
import os
for k,v in d.get('profiles',{}).items():
    if not v.get('api_key'): continue
    base = v.get('base_url','')
    key = v.get('api_key','')
    model = v.get('model','')
    alias_name = 'c' + k
    print(f'alias {alias_name}=\\'ANTHROPIC_BASE_URL=\"{base}\" ANTHROPIC_API_KEY=\"{key}\" ANTHROPIC_MODEL=\"{model}\" $CC_PROFS_BIN\\'')
"
}

# ─── Script path (for re-source hint) ─────────────────────
cc_profiles_script_path() {
  local src="${BASH_SOURCE[0]:-$0}"
  if [[ -L "$src" ]]; then
    src="$(readlink "$src")"
  fi
  echo "$src"
}

# ─── Help ─────────────────────────────────────────────────
cc_profiles_help() {
  cat << EOF
${C_B}cc-profiles${C_X} v$CC_PROFILES_VERSION — Claude Code multi-model profile manager

${C_B}Usage:${C_X}
  cc-profiles <command>

${C_B}Commands:${C_X}
  list, ls        List all profiles
  sync            Sync current settings.json as a profile
  add [name]      Add a new profile interactively
  remove [name]   Remove a profile
  edit            Open profiles.json in \$EDITOR
  aliases         Print alias commands (for debugging)
  help            Show this help

${C_B}Quick Start:${C_X}
  1. source cc-profiles.sh        # Load into shell
  2. cc-profiles edit             # Fill in your API keys
  3. cglm / cds / cmimo ...       # Launch different models

${C_B}Environment Variables:${C_X}
  CC_PROFILES_DIR   Config directory  (default: ~/.claude/profiles)
  CC_PROFS_BIN      Claude binary     (default: claude)

EOF
}

# ─── Main entry ───────────────────────────────────────────
cc-profiles() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true
  case "$cmd" in
    list|ls)    cc_profiles_list ;;
    sync)       cc_profiles_sync ;;
    add)        cc_profiles_add "$@" ;;
    remove|rm)  cc_profiles_remove "$@" ;;
    edit)       cc_profiles_edit ;;
    aliases)    cc_profiles_load ;;
    version|-v) echo "cc-profiles $CC_PROFILES_VERSION" ;;
    help|--help|-h) cc_profiles_help ;;
    *)
      # If cmd matches a profile name, launch it directly
      if _jq_file "$CC_PROFILES_CONF" "
v = d.get('profiles',{}).get('$cmd')
if v and v.get('api_key'):
    print('found')
else:
    print('not_found')
" | grep -q "found"; then
        local base_url api_key model
        base_url=$(_jq_file "$CC_PROFILES_CONF" "print(d['profiles']['$cmd'].get('base_url',''))")
        api_key=$(_jq_file "$CC_PROFILES_CONF" "print(d['profiles']['$cmd'].get('api_key',''))")
        model=$(_jq_file "$CC_PROFILES_CONF" "print(d['profiles']['$cmd'].get('model',''))")
        _info "Launching $model ..."
        exec env ANTHROPIC_BASE_URL="$base_url" ANTHROPIC_API_KEY="$api_key" ANTHROPIC_MODEL="$model" "$CC_PROFS_BIN" "$@"
      else
        _err "Unknown command or profile: $cmd"
        cc_profiles_help
        return 1
      fi
      ;;
  esac
}

# ─── Auto-load aliases when sourced ───────────────────────
eval "$(cc_profiles_load 2>/dev/null)"

# If executed directly (not sourced), run command
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]] && [[ $# -gt 0 ]]; then
  cc-profiles "$@"
fi
