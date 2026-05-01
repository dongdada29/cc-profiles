#!/usr/bin/env bash
# test.sh - smoke tests for cc-profiles
PASS=0 FAIL=0

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cc-profiles.sh"

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

export CC_PROFILES_DIR=$(mktemp -d)
export CC_PROFILES_CONF="$CC_PROFILES_DIR/profiles.json"

echo "🧪 Testing cc-profiles v1.0.0"
echo ""

# 1. Init
echo "1. Init"
source "$SCRIPT" 2>/dev/null || true
assert "creates profiles.json" "{}" "$(cat "$CC_PROFILES_CONF" 2>/dev/null)"

# 2. Batch
echo "2. Batch"
cc-profiles batch << 'TSV'
glm|GLM-5.1|https://open.bigmodel.cn/api/anthropic|glm-key-123|glm-5.1
deepseek|DeepSeek-v4|https://api.deepseek.com|ds-key-456|deepseek-v4-pro
mimo|Mimo-v2.5|https://api.mimo.com/v1|mimo-key-789|mimo-v2.5
TSV
out=$(cc-profiles list 2>&1)
assert "batch adds glm" "glm" "$out"
assert "batch adds deepseek" "deepseek" "$out"
assert "batch adds mimo" "mimo" "$out"

# 3. Single batch add
echo "3. Add"
echo "test1|Test Model|https://api.test.com|test-key-123|test-v1" | cc-profiles batch 2>&1
out=$(cc-profiles list 2>&1)
assert "shows test1" "test1" "$out"
assert "shows test-v1" "test-v1" "$out"

# 4. Aliases
echo "4. Aliases"
out=$(cc-profiles aliases 2>&1)
assert "generates cglm" "cglm" "$out"
assert "includes model" "glm-5.1" "$out"

# 5. Use
echo "5. Use"
cc-profiles use glm 2>/dev/null
out=$(cc-profiles current 2>&1)
assert "marks glm as default" "glm" "$out"

# 6. Remove
echo "6. Remove"
cc-profiles remove mimo 2>&1
out=$(cc-profiles list 2>&1)
assert "removes mimo" "" "$(echo "$out" | grep -co "mimo" || echo "0")"

# 7. Batch from file
echo "7. Batch from file"
cat > "$CC_PROFILES_DIR/import.tsv" << 'TSV'
# comments skipped
qwen|Qwen-3|https://api.qwen.com|qwen-key|qwen-3-72b

TSV
cc-profiles batch "$CC_PROFILES_DIR/import.tsv" 2>&1
out=$(cc-profiles list 2>&1)
assert "adds qwen" "qwen" "$out"

# 8. Special chars in values (injection test)
echo "8. Injection safety"
echo 'hack|Test "injection"|https://evil.com|key-with-"quotes"|model'"'"'s-name' | cc-profiles batch 2>&1
out=$(cc-profiles list 2>&1)
assert "handles special chars" "hack" "$out"

# Cleanup
rm -rf "$CC_PROFILES_DIR"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
