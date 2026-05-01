#!/usr/bin/env bash
# cc-profiles - Claude Code multi-model profile manager
# https://github.com/dongdada29/cc-profiles
#
# Run different models in different terminal windows without global config conflicts.
# Each profile sets ANTHROPIC_BASE_URL, ANTHROPIC_API_KEY, ANTHROPIC_MODEL per shell process.

set -uo pipefail
# Note: no -e, since init/sync may return 1 intentionally

CC_PROFILES_VERSION="0.2.0"
CC_PROFILES_DIR="${CC_PROFILES_DIR:-$HOME/.claude/profiles}"
CC_PROFILES_CONF="$CC_PROFILES_DIR/profiles.json"

# Auto-detect claude binary
_cc_detect_bin() {
  if command -v claude &>/dev/null; then
    echo "claude"
  elif [[ -x "$HOME/.local/bin/claude" ]]; then
    echo "$HOME/.local/bin/claude"
  elif [[ -x "/usr/local/bin/claude" ]]; then
    echo "/usr/local/bin/claude"
  else
    echo "claude"
  fi
}
CC_PROFS_BIN="${CC_PROFS_BIN:-$(_cc_detect_bin)}"

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

# ─── Sanitize key name ───────────────────────────────────
_cc_sanitize() {
  local s="$1"
  s="${s//[^a-zA-Z0-9_-]/_}"
  echo "$s"
}

# ─── Init config ──────────────────────────────────────────
cc_profiles_init() {
  if [[ ! -f "$CC_PROFILES_CONF" ]]; then
    mkdir -p "$CC_PROFILES_DIR"
    cat > "$CC_PROFILES_CONF" << 'DEFAULTS'
{
  "current": "",
  "profiles": {}
}
DEFAULTS
    echo -e "${C_G}✔${C_X} Created $CC_PROFILES_CONF"
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
  echo -e "  bin: $CC_PROFS_BIN"
  echo ""
  python3 - "$CC_PROFILES_CONF" "$current" "$C_C" "$C_X" << 'PYEOF'
import json, sys
conf_path, current, cc, cx = sys.argv[1:]
profiles = json.load(open(conf_path)).get("profiles", {})
for k, v in profiles.items():
    marker = " ← default" if k == current else ""
    key_s = "🔑" if v.get("api_key") else "❌ no key"
    alias_name = v.get("alias", "") or ("c" + k)
    alias_s = f"  alias: {alias_name}" if v.get("alias") and v["alias"] != ("c" + k) else ""
    print(f"  {cc}{k:14s}{cx} → {v.get('name','?'):22s} [{v.get('model','?')}]  {key_s}{marker}{alias_s}")
PYEOF
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
  name="$(_cc_sanitize "${name:-synced}")"

  python3 << PYEOF
import json
d = json.load(open("$CC_PROFILES_CONF"))
d["profiles"]["$name"] = {
    "name": "$model (synced)",
    "base_url": "$base_url",
    "api_key": "$api_key",
    "model": "$model"
}
json.dump(d, open("$CC_PROFILES_CONF","w"), indent=2, ensure_ascii=False)
PYEOF
  _info "Saved as profile: $name"
}

# ─── Batch import ─────────────────────────────────────────
cc_profiles_batch() {
  cc_profiles_init || return 0
  local src="${1:-}"

  if [[ -n "$src" ]] && [[ -f "$src" ]]; then
    # From file
    _cc_batch_from_file "$src"
  elif [[ ! -t 0 ]]; then
    # From stdin / pipe
    _cc_batch_from_file "/dev/stdin"
  else
    # Interactive paste mode
    echo "Paste profiles in TSV format (key|name|base_url|api_key|model), one per line."
    echo "Empty line to finish."
    echo ""
    local count=0
    while IFS= read -rp "> " line; do
      [[ -z "$line" ]] && break
      _cc_batch_add_line "$line" && ((count++))
    done
    _info "Imported $count profile(s)"
  fi
}

_cc_batch_from_file() {
  local file="$1" count=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue  # skip comments
    _cc_batch_add_line "$line" && ((count++))
  done < "$file"
  _info "Imported $count profile(s)"
}

_cc_batch_add_line() {
  local IFS='|'
  read -r key display_name base_url api_key model <<< "$1"
  key="$(_cc_sanitize "$key")"
  [[ -z "$key" || -z "$model" ]] && { _warn "Skip invalid line: $1"; return 1; }
  python3 << PYEOF
import json
d = json.load(open("$CC_PROFILES_CONF"))
d["profiles"]["$key"] = {
    "name": "$display_name",
    "base_url": "$base_url",
    "api_key": "$api_key",
    "model": "$model"
}
json.dump(d, open("$CC_PROFILES_CONF","w"), indent=2, ensure_ascii=False)
PYEOF
  echo -e "  ${C_G}+${C_X} $key → $display_name [$model]"
}

# ─── Add profile ──────────────────────────────────────────
cc_profiles_add() {
  cc_profiles_init || return 0
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    read -rp "Profile key (e.g. glm, deepseek): " name
  fi
  name="$(_cc_sanitize "$name")"
  [[ -z "$name" ]] && { _err "Profile key required"; return 1; }

  read -rp "Display name [e.g. GLM-5.1]: " display_name
  read -rp "API Base URL: " base_url
  read -rp "API Key: " api_key
  read -rp "Model ID: " model
  local default_alias="c$name"
  read -rp "Custom alias [$default_alias]: " custom_alias
  custom_alias="${custom_alias:-$default_alias}"

  python3 << PYEOF
import json
d = json.load(open("$CC_PROFILES_CONF"))
d["profiles"]["$name"] = {
    "name": "$display_name",
    "base_url": "$base_url",
    "api_key": "$api_key",
    "model": "$model",
    "alias": "$custom_alias"
}
json.dump(d, open("$CC_PROFILES_CONF","w"), indent=2, ensure_ascii=False)
PYEOF
  _info "Added profile: $name → $display_name (alias: $custom_alias)"
  echo "Re-source to load: source $(_cc_script_path)"
}

# ─── Remove profile ───────────────────────────────────────
cc_profiles_remove() {
  cc_profiles_init || return 0
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    cc_profiles_list
    read -rp "Profile key to remove: " name
  fi
  local result
  result=$(python3 << PYEOF
import json
d = json.load(open("$CC_PROFILES_CONF"))
if "$name" in d.get("profiles",{}):
    del d["profiles"]["$name"]
    json.dump(d, open("$CC_PROFILES_CONF","w"), indent=2, ensure_ascii=False)
    print("removed")
else:
    print("not_found")
PYEOF
  )
  if [[ "$result" == "removed" ]]; then
    _info "Removed: $name"
  else
    _err "Profile not found: $name"
    return 1
  fi
}

# ─── Use / set default ───────────────────────────────────
cc_profiles_use() {
  cc_profiles_init || return 0
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    cc_profiles_list
    read -rp "Set default profile: " name
  fi
  local exists
  exists=$(_jq_file "$CC_PROFILES_CONF" "print('yes' if '$name' in d.get('profiles',{}) else 'no')")
  if [[ "$exists" != "yes" ]]; then
    _err "Profile not found: $name"
    return 1
  fi

  local base_url api_key model
  base_url=$(_jq_file "$CC_PROFILES_CONF" "print(d['profiles']['$name'].get('base_url',''))")
  api_key=$(_jq_file "$CC_PROFILES_CONF" "print(d['profiles']['$name'].get('api_key',''))")
  model=$(_jq_file "$CC_PROFILES_CONF" "print(d['profiles']['$name'].get('model',''))")

  python3 << PYEOF
import json
d = json.load(open("$CC_PROFILES_CONF"))
d["current"] = "$name"
json.dump(d, open("$CC_PROFILES_CONF","w"), indent=2, ensure_ascii=False)
PYEOF

  # Also write to settings.json as the default
  local settings="$HOME/.claude/settings.json"
  if [[ -f "$settings" ]]; then
    python3 << PYEOF
import json
s = json.load(open("$settings"))
s.setdefault("env", {})
s["env"]["ANTHROPIC_BASE_URL"] = "$base_url"
s["env"]["ANTHROPIC_AUTH_TOKEN"] = "$api_key"
s["env"]["ANTHROPIC_MODEL"] = "$model"
json.dump(s, open("$settings","w"), indent=2, ensure_ascii=False)
PYEOF
    _info "Default set to: $name → $model (settings.json updated)"
  else
    _info "Default set to: $name → $model"
  fi
}

# ─── Edit config ──────────────────────────────────────────
cc_profiles_edit() {
  ${EDITOR:-vim} "$CC_PROFILES_CONF"
}

# ─── Generate aliases ─────────────────────────────────────
cc_profiles_load() {
  cc_profiles_init 2>/dev/null || return 0
  python3 << PYEOF
import json
d = json.load(open("$CC_PROFILES_CONF"))
for k,v in d.get("profiles",{}).items():
    if not v.get("api_key"): continue
    base = v.get("base_url","")
    key = v.get("api_key","")
    model = v.get("model","")
    alias_name = v.get("alias","") or ("c"+k)
    print(f"alias {alias_name}='ANTHROPIC_BASE_URL=\"{base}\" ANTHROPIC_API_KEY=\"{key}\" ANTHROPIC_MODEL=\"{model}\" $CC_PROFS_BIN'")
PYEOF
}

# ─── Script path (for re-source hint) ─────────────────────
_cc_script_path() {
  local src="${BASH_SOURCE[0]:-$0}"
  if [[ -L "$src" ]]; then src="$(readlink "$src")"; fi
  echo "$src"
}

# ─── Help ─────────────────────────────────────────────────
cc_profiles_help() {
  cat << EOF
${C_B}cc-profiles${C_X} v$CC_PROFILES_VERSION — Claude Code multi-model profile manager

${C_B}Usage:${C_X}
  cc-profiles <command>

${C_B}Commands:${C_X}
  list, ls            List all profiles
  sync                Sync current settings.json as a profile
  batch [file]        Batch import from TSV (key|name|url|key|model)
  add [name]          Add a new profile interactively
  remove [name]       Remove a profile
  use [name]          Set default profile (updates settings.json)
  edit                Open profiles.json in \$EDITOR
  aliases             Print alias commands (for debugging)
  version             Show version
  help                Show this help

${C_B}Quick Start:${C_X}
  1. source cc-profiles.sh        # Load into shell
  2. cc-profiles edit             # Fill in your API keys
  3. cglm / cds / cmimo ...       # Launch different models

${C_B}Batch Import:${C_X}
  # From a file (profiles.tsv):
  glm|GLM-5.1|https://open.bigmodel.cn/api/anthropic|YOUR_KEY|glm-5.1
  deepseek|DeepSeek-v4-pro|https://api.deepseek.com|YOUR_KEY|deepseek-v4-pro

  cc-profiles batch profiles.tsv

  # Or pipe:
  echo "glm|GLM-5.1|https://...|KEY|glm-5.1" | cc-profiles batch

${C_B}Environment Variables:${C_X}
  CC_PROFILES_DIR   Config directory  (default: ~/.claude/profiles)
  CC_PROFS_BIN      Claude binary     (default: auto-detect)

EOF
}

# ─── Main entry ───────────────────────────────────────────
cc-profiles() {
  local cmd="${1:-help}"
  shift 2>/dev/null || true
  case "$cmd" in
    list|ls)      cc_profiles_list ;;
    sync)         cc_profiles_sync ;;
    batch)        cc_profiles_batch "$@" ;;
    add)          cc_profiles_add "$@" ;;
    remove|rm)    cc_profiles_remove "$@" ;;
    use)          cc_profiles_use "$@" ;;
    edit)         cc_profiles_edit ;;
    aliases)      cc_profiles_load ;;
    version|-v)   echo "cc-profiles $CC_PROFILES_VERSION" ;;
    help|--help|-h) cc_profiles_help ;;
    *)
      # If cmd matches a profile name, launch it directly
      local found
      found=$(_jq_file "$CC_PROFILES_CONF" "
v = d.get('profiles',{}).get('$cmd')
print('found' if v and v.get('api_key') else 'not_found')
")
      if [[ "$found" == "found" ]]; then
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
