#!/usr/bin/env bash
# cc-profiles - Claude Code multi-model profile manager
# https://github.com/dongdada29/cc-profiles
#
# Run different models in different terminal windows without global config conflicts.
# Each profile sets ANTHROPIC_BASE_URL, ANTHROPIC_API_KEY, ANTHROPIC_MODEL per shell process.

set -uo pipefail

CC_PROFILES_VERSION="1.0.0"
CC_PROFILES_DIR="${CC_PROFILES_DIR:-$HOME/.claude/profiles}"
CC_PROFILES_CONF="$CC_PROFILES_DIR/profiles.json"

# Auto-detect claude binary
_cc_detect_bin() {
  if command -v claude &>/dev/null; then echo "claude"
  elif [[ -x "$HOME/.local/bin/claude" ]]; then echo "$HOME/.local/bin/claude"
  elif [[ -x "/usr/local/bin/claude" ]]; then echo "/usr/local/bin/claude"
  else echo "claude"
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

# ─── JSON helpers ─────────────────────────────────────────
# All python calls pass values via sys.argv (safe, no injection)

_cc_get() {
  local field="$1"
  python3 - "$CC_PROFILES_CONF" "$field" << 'PYEOF'
import json, sys
conf, field = sys.argv[1:3]
d = json.load(open(conf))
print(d.get(field, ""))
PYEOF
}

_cc_get_nested() {
  local key="$1" field="$2"
  python3 - "$CC_PROFILES_CONF" "$key" "$field" << 'PYEOF'
import json, sys
conf, key, field = sys.argv[1:4]
d = json.load(open(conf))
print(d.get("profiles",{}).get(key,{}).get(field,""))
PYEOF
}

_cc_set_current() {
  local key="$1"
  python3 - "$CC_PROFILES_CONF" "$key" << 'PYEOF'
import json, sys
conf, key = sys.argv[1:3]
d = json.load(open(conf))
d["current"] = key
json.dump(d, open(conf,"w"), indent=2, ensure_ascii=False)
PYEOF
}

_cc_profile_exists() {
  local key="$1"
  python3 - "$CC_PROFILES_CONF" "$key" << 'PYEOF'
import json, sys
conf, key = sys.argv[1:3]
d = json.load(open(conf))
print("yes" if key in d.get("profiles",{}) and d["profiles"][key].get("api_key") else "no")
PYEOF
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
  current=$(_cc_get "current")
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

# ─── Current default ─────────────────────────────────────
cc_profiles_current() {
  cc_profiles_init || return 0
  local cur
  cur=$(_cc_get "current")
  if [[ -z "$cur" ]]; then
    echo "No default profile set"
    return
  fi
  local model
  model=$(_cc_get_nested "$cur" "model")
  echo -e "Default: ${C_C}$cur${C_X} → $model"
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
  base_url=$(python3 -c "import json; d=json.load(open('$settings')); print(d.get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
  api_key=$(python3 -c "import json; d=json.load(open('$settings')); print(d.get('env',{}).get('ANTHROPIC_AUTH_TOKEN','') or d.get('env',{}).get('ANTHROPIC_API_KEY',''))" 2>/dev/null)
  model=$(python3 -c "import json; d=json.load(open('$settings')); print(d.get('env',{}).get('ANTHROPIC_MODEL',''))" 2>/dev/null)

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

  python3 - "$CC_PROFILES_CONF" "$name" "$model" "$base_url" "$api_key" << 'PYEOF'
import json, sys
conf, key, model, base_url, api_key = sys.argv[1:6]
d = json.load(open(conf))
d["profiles"][key] = {
    "name": model + " (synced)",
    "base_url": base_url,
    "api_key": api_key,
    "model": model
}
json.dump(d, open(conf, "w"), indent=2, ensure_ascii=False)
PYEOF
  _info "Saved as profile: $name"
}

# ─── Batch import ─────────────────────────────────────────
cc_profiles_batch() {
  cc_profiles_init || return 0
  local src="${1:-}"

  if [[ -n "$src" ]] && [[ -f "$src" ]]; then
    _cc_batch_from_file "$src"
  elif [[ ! -t 0 ]]; then
    _cc_batch_from_file "/dev/stdin"
  else
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
  # Collect all valid lines, then write once
  local lines=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    lines+=("$line")
  done < "$file"

  if (( ${#lines[@]} == 0 )); then
    _warn "No valid lines found"
    return
  fi

  # Write all at once via python
  python3 - "$CC_PROFILES_CONF" "${lines[@]}" << 'PYEOF'
import json, sys
conf = sys.argv[1]
lines = sys.argv[2:]
d = json.load(open(conf))
count = 0
for line in lines:
    parts = line.split("|")
    if len(parts) < 5:
        print(f"  ⚠ Skip invalid line: {line}")
        continue
    key, name, base_url, api_key, model = parts[0], parts[1], parts[2], parts[3], parts[4]
    # Sanitize key
    import re
    key = re.sub(r'[^a-zA-Z0-9_-]', '_', key)
    if not key or not model:
        print(f"  ⚠ Skip invalid line: {line}")
        continue
    d["profiles"][key] = {
        "name": name,
        "base_url": base_url,
        "api_key": api_key,
        "model": model
    }
    print(f"  + {key} → {name} [{model}]")
    count += 1
json.dump(d, open(conf, "w"), indent=2, ensure_ascii=False)
print(f"✔ Imported {count} profile(s)")
PYEOF
}

_cc_batch_add_line() {
  # Single line add (used in interactive mode)
  local IFS='|'
  read -r key display_name base_url api_key model <<< "$1"
  key="$(_cc_sanitize "$key")"
  [[ -z "$key" || -z "$model" ]] && { _warn "Skip invalid line: $1"; return 1; }

  python3 - "$CC_PROFILES_CONF" "$key" "$display_name" "$base_url" "$api_key" "$model" << 'PYEOF'
import json, sys
conf, key, name, base_url, api_key, model = sys.argv[1:7]
d = json.load(open(conf))
d["profiles"][key] = {
    "name": name,
    "base_url": base_url,
    "api_key": api_key,
    "model": model
}
json.dump(d, open(conf, "w"), indent=2, ensure_ascii=False)
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

  python3 - "$CC_PROFILES_CONF" "$name" "$display_name" "$base_url" "$api_key" "$model" "$custom_alias" << 'PYEOF'
import json, sys
conf, key, name, base_url, api_key, model, alias = sys.argv[1:8]
d = json.load(open(conf))
d["profiles"][key] = {
    "name": name,
    "base_url": base_url,
    "api_key": api_key,
    "model": model,
    "alias": alias
}
json.dump(d, open(conf, "w"), indent=2, ensure_ascii=False)
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
  result=$(python3 - "$CC_PROFILES_CONF" "$name" << 'PYEOF'
import json, sys
conf, key = sys.argv[1:3]
d = json.load(open(conf))
if key in d.get("profiles", {}):
    del d["profiles"][key]
    json.dump(d, open(conf, "w"), indent=2, ensure_ascii=False)
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
  exists=$(_cc_profile_exists "$name")
  if [[ "$exists" != "yes" ]]; then
    _err "Profile not found: $name"
    return 1
  fi

  local base_url api_key model
  base_url=$(_cc_get_nested "$name" "base_url")
  api_key=$(_cc_get_nested "$name" "api_key")
  model=$(_cc_get_nested "$name" "model")

  _cc_set_current "$name"

  # Also write to settings.json as the default
  local settings="$HOME/.claude/settings.json"
  if [[ -f "$settings" ]]; then
    python3 - "$settings" "$base_url" "$api_key" "$model" << 'PYEOF'
import json, sys
settings_path, base_url, api_key, model = sys.argv[1:5]
s = json.load(open(settings_path))
s.setdefault("env", {})
s["env"]["ANTHROPIC_BASE_URL"] = base_url
s["env"]["ANTHROPIC_AUTH_TOKEN"] = api_key
s["env"]["ANTHROPIC_MODEL"] = model
json.dump(s, open(settings_path, "w"), indent=2, ensure_ascii=False)
PYEOF
    _info "Default set to: $name → $model (settings.json updated)"
  else
    _info "Default set to: $name → $model"
  fi
}

# ─── Test API connectivity ───────────────────────────────
cc_profiles_test() {
  cc_profiles_init || return 0
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    cc_profiles_list
    read -rp "Profile to test: " name
  fi
  local exists
  exists=$(_cc_profile_exists "$name")
  if [[ "$exists" != "yes" ]]; then
    _err "Profile not found: $name"
    return 1
  fi

  local base_url api_key model
  base_url=$(_cc_get_nested "$name" "base_url")
  api_key=$(_cc_get_nested "$name" "api_key")
  model=$(_cc_get_nested "$name" "model")

  echo "Testing $name ($model)..."
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -d "{\"model\":\"$model\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
    "$base_url/messages" 2>/dev/null) || code="000"

  case "$code" in
    200) _info "$name → API OK ($code)" ;;
    401|403) _err "$name → Auth failed ($code), check API key" ;;
    429) _warn "$name → Rate limited ($code)" ;;
    000) _err "$name → Connection failed, check base_url" ;;
    *) _warn "$name → HTTP $code" ;;
  esac
}

# ─── Edit config ──────────────────────────────────────────
cc_profiles_edit() {
  ${EDITOR:-vim} "$CC_PROFILES_CONF"
}

# ─── Generate aliases ─────────────────────────────────────
cc_profiles_load() {
  cc_profiles_init 2>/dev/null || return 0
  python3 - "$CC_PROFILES_CONF" "$CC_PROFS_BIN" << 'PYEOF'
import json, sys
conf, claude_bin = sys.argv[1:3]
d = json.load(open(conf))
for k, v in d.get("profiles", {}).items():
    if not v.get("api_key"): continue
    base = v.get("base_url", "")
    key = v.get("api_key", "")
    model = v.get("model", "")
    alias_name = v.get("alias", "") or ("c" + k)
    # Use json.dumps to safely escape all values
    b = json.dumps(base)
    k_ = json.dumps(key)
    m = json.dumps(model)
    print(f"alias {alias_name}='ANTHROPIC_BASE_URL={b} ANTHROPIC_API_KEY={k_} ANTHROPIC_MODEL={m} {claude_bin}'")
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
  current             Show current default profile
  sync                Sync current settings.json as a profile
  batch [file]        Batch import from TSV (key|name|url|key|model)
  add [name]          Add a new profile interactively
  remove [name]       Remove a profile
  use [name]          Set default profile (updates settings.json)
  test [name]         Test API connectivity
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
    current)      cc_profiles_current ;;
    sync)         cc_profiles_sync ;;
    batch)        cc_profiles_batch "$@" ;;
    add)          cc_profiles_add "$@" ;;
    remove|rm)    cc_profiles_remove "$@" ;;
    use)          cc_profiles_use "$@" ;;
    test)         cc_profiles_test "$@" ;;
    edit)         cc_profiles_edit ;;
    aliases)      cc_profiles_load ;;
    version|-v)   echo "cc-profiles $CC_PROFILES_VERSION" ;;
    help|--help|-h) cc_profiles_help ;;
    *)
      # If cmd matches a profile name, launch it directly
      local exists
      exists=$(_cc_profile_exists "$cmd")
      if [[ "$exists" == "yes" ]]; then
        local base_url api_key model
        base_url=$(_cc_get_nested "$cmd" "base_url")
        api_key=$(_cc_get_nested "$cmd" "api_key")
        model=$(_cc_get_nested "$cmd" "model")
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
