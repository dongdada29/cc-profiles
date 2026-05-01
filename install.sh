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

# ─── Install ──────────────────────────────────────────────
do_install() {
  mkdir -p "$TARGET_DIR"
  cp "$SCRIPT_DIR/cc-profiles.sh" "$TARGET_DIR/cc-profiles"
  chmod +x "$TARGET_DIR/cc-profiles"

  detect_rc

  if ! grep -q '.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo '' >> "$SHELL_RC"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
  fi

  if ! grep -q 'cc-profiles aliases' "$SHELL_RC" 2>/dev/null; then
    echo '' >> "$SHELL_RC"
    echo '# cc-profiles - Claude Code multi-model manager' >> "$SHELL_RC"
    echo 'eval "$(cc-profiles aliases 2>/dev/null)"' >> "$SHELL_RC"
  fi

  echo -e "${C_G}✔${C_X} Installed to $TARGET_DIR/cc-profiles"
  echo -e "${C_G}✔${C_X} Shell config updated ($SHELL_RC)"

  # Zsh completions
  if [ -n "$ZSH_VERSION" ] || [[ "$SHELL" == */zsh ]]; then
    local zfunc="$HOME/.zfunc"
    mkdir -p "$zfunc"
    cp "$SCRIPT_DIR/completions/_cc-profiles" "$zfunc/_cc-profiles" 2>/dev/null || true
    if ! grep -q 'fpath.*\.zfunc' "$SHELL_RC" 2>/dev/null; then
      echo 'fpath+=(~/.zfunc)' >> "$SHELL_RC"
    fi
    if ! grep -q 'autoload -Uz compinit && compinit' "$SHELL_RC" 2>/dev/null; then
      echo 'autoload -Uz compinit && compinit' >> "$SHELL_RC"
    fi
    echo -e "${C_G}✔${C_X} Zsh completions installed (~/.zfunc/_cc-profiles)"
  fi
}

# ─── Sync first profile ──────────────────────────────────
do_init() {
  local settings="$HOME/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then
    echo -e "${C_Y}⚠${C_X} No $settings found, skip sync"
    echo -e "  Run ${C_B}cc-profiles sync${C_X} after configuring claude-code"
    return
  fi

  # Use python3 to safely read and write (no injection risk)
  python3 - "$settings" "$HOME/.claude/profiles/profiles.json" << 'PYEOF'
import json, os, sys, re

settings_path = sys.argv[1]
profiles_path = sys.argv[2]

s = json.load(open(settings_path))
env = s.get("env", {})
base_url = env.get("ANTHROPIC_BASE_URL", "")
api_key = env.get("ANTHROPIC_AUTH_TOKEN", "") or env.get("ANTHROPIC_API_KEY", "")
model = env.get("ANTHROPIC_MODEL", "")

if not model:
    print("⚠ No model config in settings.json, skip sync")
    sys.exit(0)

# Generate safe key from model name
key = re.sub(r'[^a-z0-9]', '_', model.lower())[:20].rstrip('_')

os.makedirs(os.path.dirname(profiles_path), exist_ok=True)

if os.path.exists(profiles_path):
    d = json.load(open(profiles_path))
else:
    d = {"current": "", "profiles": {}}

d["current"] = key
d["profiles"][key] = {
    "name": model,
    "base_url": base_url,
    "api_key": api_key,
    "model": model
}
json.dump(d, open(profiles_path, "w"), indent=2, ensure_ascii=False)

print(f"✔ Synced current model: {model} → profile '{key}'")
print(f"  alias: c{key}")
PYEOF
}

# ─── Uninstall ────────────────────────────────────────────
do_uninstall() {
  rm -f "$TARGET_DIR/cc-profiles"
  rm -f "$HOME/.zfunc/_cc-profiles"
  detect_rc
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
    detect_rc
    echo -e "${C_B}Next:${C_X}"
    echo -e "  1. source $SHELL_RC"
    echo -e "  2. cc-profiles list           # see your profiles"
    echo -e "  3. cc-profiles batch file.tsv # add more models"
    echo -e "  4. cc-profiles test glm       # test connectivity"
    echo -e "  5. cglm                       # launch! 🚀"
    ;;
  uninstall)
    do_uninstall
    ;;
  *)
    echo "Usage: $0 [install|uninstall]"
    exit 1
    ;;
esac
