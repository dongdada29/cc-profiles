#!/bin/bash
# install.sh - cc-profiles installer
set -e

GREEN='\033[0;32m' YELLOW='\033[0;33m' NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_RC=""

detect_shell_rc() {
  if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
  elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
  else
    SHELL_RC="$HOME/.profile"
  fi
}

install() {
  local target="$HOME/.local/bin"
  mkdir -p "$target"

  cp "$SCRIPT_DIR/cc-profiles.sh" "$target/cc-profiles"
  chmod +x "$target/cc-profiles"

  # Ensure ~/.local/bin in PATH
  detect_shell_rc
  if ! grep -q '.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
  fi

  # Add eval line for aliases
  if ! grep -q 'cc-profiles aliases' "$SHELL_RC" 2>/dev/null; then
    echo '' >> "$SHELL_RC"
    echo '# cc-profiles - Claude Code multi-model manager' >> "$SHELL_RC"
    echo 'eval "$(cc-profiles aliases 2>/dev/null)"' >> "$SHELL_RC"
  fi

  echo -e "${GREEN}✔${NC} Installed to $target/cc-profiles"
  echo -e "${GREEN}✔${NC} Added to $SHELL_RC"
  echo ""
  echo "Next steps:"
  echo "  1. source $SHELL_RC"
  echo "  2. cc-profiles edit    # Fill in your API keys"
  echo "  3. cglm / cds / cmimo  # Launch!"
}

uninstall() {
  rm -f "$HOME/.local/bin/cc-profiles"
  detect_shell_rc
  # Remove from shell rc
  sed -i.bak '/cc-profiles/d' "$SHELL_RC" 2>/dev/null || true
  rm -f "$SHELL_RC.bak"
  echo -e "${YELLOW}⚠${NC} Uninstalled. Run 'source $SHELL_RC' to clean up."
}

case "${1:-install}" in
  install)   install ;;
  uninstall) uninstall ;;
  *)         echo "Usage: $0 [install|uninstall]"; exit 1 ;;
esac
