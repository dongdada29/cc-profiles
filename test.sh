#!/bin/bash
# test.sh - basic smoke tests for cc-profiles
set -e

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc-profiles.sh"
PASS=0 FAIL=0

assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  ✅ $desc"
    ((PASS++))
  else
    echo "  ❌ $desc"
    echo "     expected: $expected"
    echo "     got:      $actual"
    ((FAIL++))
  fi
}

# Setup: use temp dir
export CC_PROFILES_DIR=$(mktemp -d)
export CC_PROFILES_CONF="$CC_PROFILES_DIR/profiles.json"

echo "🧪 Testing cc-profiles"
echo ""

# Test 1: init creates default config
echo "1. Init"
source "$SCRIPT"
[[ -f "$CC_PROFILES_CONF" ]] && assert "creates profiles.json" "glm" "$(cat "$CC_PROFILES_CONF")" || assert "creates profiles.json" "fail" "fail"

# Test 2: list
echo "2. List"
out=$(cc-profiles list 2>&1)
assert "shows glm profile" "glm" "$out"
assert "shows deepseek profile" "deepseek" "$out"

# Test 3: sync from settings.json
echo "3. Sync"
TEST_SETTINGS="$CC_PROFILES_DIR/test_settings.json"
cat > "$TEST_SETTINGS" << 'EOF'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.test.com",
    "ANTHROPIC_AUTH_TOKEN": "test-key-123",
    "ANTHROPIC_MODEL": "test-model-v1"
  }
}
EOF
# Temporarily override HOME to use test settings
ORIG_HOME="$HOME"
export HOME="$CC_PROFILES_DIR/fake_home"
mkdir -p "$HOME/.claude"
cp "$TEST_SETTINGS" "$HOME/.claude/settings.json"
echo "test_sync" | cc-profiles sync 2>&1
out=$(cc-profiles list 2>&1)
assert "sync creates profile" "test_sync" "$out"
export HOME="$ORIG_HOME"

# Test 4: aliases generation
echo "4. Aliases"
source "$SCRIPT"
out=$(cc-profiles aliases 2>&1)
assert "generates cglm alias" "cglm" "$out"

# Cleanup
rm -rf "$CC_PROFILES_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
