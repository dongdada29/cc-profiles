#!/usr/bin/env bash
# install.sh - cc-profiles one-click installer
set -uo pipefail

C_G="\033[0;32m" C_Y="\033[0;33m" C_B="\033[1m" C_X="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.local/bin"
SHELL_RC=""

# ─── Detect shell rc ──────────────────────────────────────
detect_rc() {
  if [ -n "$ZSH_VERSION" ]; then SHELL_RC="$HOME/.zshrc"
  elif [ -n "$BASH_VERSION" ]; then SHELL_RC="$HOME/.bashrc"
  else SHELL_RC="$HOME/.profile"
  fi
}

# ─── Install script ───────────────────────────────────────
do_install() {
  mkdir -p "$TARGET_DIR"
  cp "$SCRIPT_DIR/cc-profiles.sh" "$TARGET_DIR/cc-profiles"
  chmod +x "$TARGET_DIR/cc-profiles"

  detect_rc

  # Ensure ~/.local/bin in PATH
  if ! grep -q '.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo '' >> "$SHELL_RC"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
  fi

  # Add auto-load line
  if ! grep -q 'cc-profiles aliases' "$SHELL_RC" 2>/dev/null; then
    echo '' >> "$SHELL_RC"
    echo '# cc-profiles - Claude Code multi-model manager' >> "$SHELL_RC"
    echo 'eval "$(cc-profiles aliases 2>/dev/null)"' >> "$SHELL_RC"
  fi

  echo -e "${C_G}✔${C_X} Installed to $TARGET_DIR/cc-profiles"
  echo -e "${C_G}✔${C_X} Shell config updated ($SHELL_RC)"
}

# ─── Sync first profile from settings.json ───────────────
do_init() {
  local settings="$HOME/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then
    echo -e "${C_Y}⚠${C_X} No $settings found, skip sync"
    echo -e "  Run ${C_B}cc-profiles sync${C_X} after configuring claude-code"
    return
  fi

  local base_url api_key model
  base_url=$(python3 -c "import json; d=json.load(open('$settings')); print(d.get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
  api_key=$(python3 -c "import json; d=json.load(open('$settings')); print(d.get('env',{}).get('ANTHROPIC_AUTH_TOKEN','') or d.get('env',{}).get('ANTHROPIC_API_KEY',''))" 2>/dev/null)
  model=$(python3 -c "import json; d=json.load(open('$settings')); print(d.get('env',{}).get('ANTHROPIC_MODEL',''))" 2>/dev/null)

  if [[ -z "$model" ]]; then
    echo -e "${C_Y}⚠${C_X} No model config in settings.json, skip sync"
    return
  fi

  # Auto-guess a key name from model
  local key
  key=$(echo "$model" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | cut -c1-20 | sed 's/_$//')

  local conf="$HOME/.claude/profiles/profiles.json"
  mkdir -p "$(dirname "$conf")"

  python3 << PYEOF
import json, os
conf = "$conf"
if os.path.exists(conf):
    d = json.load(open(conf))
else:
    d = {"current": "", "profiles": {}}
d["current"] = "$key"
d["profiles"]["$key"] = {
    "name": "$model",
    "base_url": "$base_url",
    "api_key": "$api_key",
    "model": "$model"
}
json.dump(d, open(conf, "w"), indent=2, ensure_ascii=False)
PYEOF

  echo -e "${C_G}✔${C_X} Synced current model: $model → profile '$key'"
  echo -e "  alias: ${C_B}c${key}${C_X}"
}

# ─── Uninstall ────────────────────────────────────────────
do_uninstall() {
  rm -f "$TARGET_DIR/cc-profiles"
  detect_rc
  # Remove cc-profiles lines from shell rc
  if [[ -f "$SHELL_RC" ]]; then
    sed -i.bak '/cc-profiles/d' "$SHELL_RC" 2>/dev/null || true
    rm -f "$SHELL_RC.bak"
  fi
  echo -e "${C_Y}⚠${C_X} Uninstalled. Run ${C_B}source $SHELL_RC${C_X} to clean up."
}

# ─── Main ─────────────────────────────────────────────────
echo -e "${C_B}cc-profiles installer${C_X}"
echo ""

case "${1:-install}" in
  install)
    do_install
    echo ""
    do_init
    echo ""
    echo -e "${C_B}Next:${C_X}"
    echo -e "  1. source $SHELL_RC"
    echo -e "  2. cc-profiles list           # see your profiles"
    echo -e "  3. cc-profiles batch file.tsv # add more models"
    echo -e "  4. c${key:-glm}                 # launch! 🚀"
    ;;
  uninstall)
    do_uninstall
    ;;
  *)
    echo "Usage: $0 [install|uninstall]"
    exit 1
    ;;
esac
