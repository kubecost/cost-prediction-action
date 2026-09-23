#!/usr/bin/env bash
# test-action-logic.sh
#
# Unit/integration tests for the shell logic in action-enhanced/action.yaml.
# Tests are grouped into three suites:
#   1. Cost parsing  — grep/regex that extracts totals from PREDICTION_TABLE
#   2. Threshold checks — bc arithmetic for absolute and percentage limits
#   3. Budget checks — live calls to demo.kubecost.io
#
# Usage:
#   bash test/test-action-logic.sh
#
# Requirements: bash, bc, jq, curl
#
# Exit code: 0 if all tests pass, non-zero on any failure.

set -euo pipefail

DEMO_API="https://demo.kubecost.io/model"

# ── IDs chosen from demo.kubecost.io/model/budgets ──────────────────────────
# "Large Budget": spendLimit=10000, currentSpend=0  → always has headroom
BUDGET_ID_PLENTY="fd97bdee-25cc-4fb7-b7f4-ecfb8c678041"
# "Cluster - Production": spendLimit=500, currentSpend≈895 → already over limit
BUDGET_ID_OVER="9e55753e-5859-4cc0-a304-2b0ffe66a673"

PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────
pass() { echo "  ✅ PASS: $1"; PASS=$(( PASS + 1 )); }
fail() { echo "  ❌ FAIL: $1"; FAIL=$(( FAIL + 1 )); }

assert_eq() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$desc"
  else
    fail "$desc — expected '$expected', got '$actual'"
  fi
}

assert_true() {
  local desc="$1" result="$2"
  if [ "$result" = "true" ]; then
    pass "$desc"
  else
    fail "$desc — expected true, got '$result'"
  fi
}

assert_false() {
  local desc="$1" result="$2"
  if [ "$result" = "false" ]; then
    pass "$desc"
  else
    fail "$desc — expected false, got '$result'"
  fi
}

# ── Suite 1: Cost parsing ─────────────────────────────────────────────────────
echo ""
echo "=== Suite 1: Cost Parsing ==="
echo "(Mirrors the grep in action-enhanced step 'Parse and compare predictions')"
echo ""

parse_cost() {
  echo "$1" | grep -i "total" | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0.00"
}

# Typical kubecost ASCII table format
TABLE_TYPICAL="
| Namespace | Controller | Monthly Cost |
|-----------|------------|-------------|
| default   | nginx      | 28.33        |
| Total     |            | 28.33        |
"
assert_eq "parse standard table" "$(parse_cost "$TABLE_TYPICAL")" "28.33"

# Capital TOTAL
TABLE_CAPS="
TOTAL MONTHLY COST: 125.50
"
assert_eq "parse TOTAL uppercase" "$(parse_cost "$TABLE_CAPS")" "125.50"

# Multiple numbers on total line — should grab first
TABLE_MULTI="
| Total    | 3 pods  | 244.86  |
"
assert_eq "parse first number from total line" "$(parse_cost "$TABLE_MULTI")" "244.86"

# No total line — should fall back to 0.00
TABLE_NO_TOTAL="
| default | nginx | 28.33 |
"
assert_eq "fallback when no total line" "$(parse_cost "$TABLE_NO_TOTAL")" "0.00"

# Whole-dollar amount (no decimal)
TABLE_WHOLE="
| Total | 100 |
"
# Our regex requires [0-9]+\.[0-9]+ so whole numbers won't match — expected fallback
assert_eq "whole dollar falls back (regex requires decimal)" "$(parse_cost "$TABLE_WHOLE")" "0.00"

# ── Suite 2: Threshold checks ─────────────────────────────────────────────────
echo ""
echo "=== Suite 2: Threshold Logic ==="
echo "(Mirrors the bc arithmetic in action-enhanced step 'Check cost thresholds')"
echo ""

check_exceeds() {
  local cost_change="$1" max="$2"
  echo $(( $(echo "$cost_change > $max" | bc -l) == 1 && 1 || 0 ))
}

exceeds_abs() {
  local val
  val=$(echo "$1 > $2" | bc -l)
  [ "$val" -eq 1 ] && echo "true" || echo "false"
}

exceeds_pct() {
  local val
  val=$(echo "$1 > $2" | bc -l)
  [ "$val" -eq 1 ] && echo "true" || echo "false"
}

calc_pct() {
  local change="$1" base="$2"
  if [ "$base" != "0.00" ] && [ "$base" != "0" ]; then
    echo "scale=4; ($change / $base) * 100" | bc
  else
    echo "0.00"
  fi
}

# Absolute threshold
assert_true  "absolute: 60 > 50 → exceeds"    "$(exceeds_abs 60 50)"
assert_false "absolute: 40 > 50 → within"      "$(exceeds_abs 40 50)"
assert_false "absolute: 50 > 50 → equal = ok"  "$(exceeds_abs 50 50)"
assert_true  "absolute: 50.01 > 50.00 → exceeds" "$(exceeds_abs 50.01 50.00)"
assert_false "absolute: negative change never exceeds" "$(exceeds_abs -10 50)"

# Percentage calculation (action uses scale=4; bc carries 4dp through division then multiply)
# 15.50/110.00 = 0.1409 (4dp), * 100 = 14.0900
assert_eq "pct: +15.50 on 110.00 base" "$(calc_pct 15.50 110.00)" "14.0900"
assert_eq "pct: zero base returns 0.00" "$(calc_pct 10 0.00)" "0.00"
assert_eq "pct: negative change" "$(calc_pct -5.25 110.00)" "-4.7700"

# Percentage threshold
assert_true  "pct threshold: 28% > 20% → exceeds"  "$(exceeds_pct 28 20)"
assert_false "pct threshold: 14% > 20% → within"   "$(exceeds_pct 14 20)"
assert_false "pct threshold: -5% > 20% → within"   "$(exceeds_pct -5 20)"

# ── Suite 3: Budget checks against demo.kubecost.io ──────────────────────────
echo ""
echo "=== Suite 3: Budget API Integration (demo.kubecost.io) ==="
echo ""

# Helper: runs the budget check logic exactly as the action does
# Args: budget_id  predicted_cost  fail_on_exceeded(true|false)
# Echoes: budget_status exit_code
run_budget_check() {
  local BUDGET_ID="$1"
  local PREDICTED_COST="$2"
  local FAIL_ON_EXCEEDED="$3"
  local STATUS=""

  HTTP_STATUS=$(curl -s -o /tmp/kc_test_budget.json -w "%{http_code}" \
    "${DEMO_API}/budget?id=${BUDGET_ID}")

  if [ "$HTTP_STATUS" != "200" ]; then
    echo "API_ERROR"
    return 1
  fi

  BUDGET_TOTAL=$(jq -r '.data.spendLimit // 0' /tmp/kc_test_budget.json)
  CURRENT_SPEND=$(jq -r '.data.currentSpend // 0' /tmp/kc_test_budget.json)

  if [ "$BUDGET_TOTAL" = "null" ] || [ "$BUDGET_TOTAL" = "0" ]; then
    echo "INVALID_BUDGET"
    return 1
  fi

  BUDGET_REMAINING=$(echo "$BUDGET_TOTAL - $CURRENT_SPEND" | bc)

  if (( $(echo "$PREDICTED_COST > $BUDGET_REMAINING" | bc -l) )); then
    STATUS="EXCEEDS_BUDGET"
  else
    STATUS="WITHIN_BUDGET"
  fi

  echo "$STATUS"
}

echo "  Fetching budget data from demo.kubecost.io..."

# Test 3a: Small predicted cost against large-headroom budget → WITHIN_BUDGET
RESULT=$(run_budget_check "$BUDGET_ID_PLENTY" "50.00" "false")
assert_eq "within budget: \$50 vs Large Budget (10k limit, \$0 spend)" \
  "$RESULT" "WITHIN_BUDGET"

# Test 3b: Huge predicted cost against large-headroom budget → still WITHIN
RESULT=$(run_budget_check "$BUDGET_ID_PLENTY" "5000.00" "false")
assert_eq "within budget: \$5000 vs Large Budget (\$10000 limit, \$0 spend)" \
  "$RESULT" "WITHIN_BUDGET"

# Test 3c: Even $1 against over-limit budget → EXCEEDS_BUDGET
# "Cluster - Production" already has currentSpend > spendLimit so remaining is negative
RESULT=$(run_budget_check "$BUDGET_ID_OVER" "1.00" "false")
assert_eq "exceeds budget: \$1 vs already-over-limit 'Cluster - Production'" \
  "$RESULT" "EXCEEDS_BUDGET"

# Test 3d: Budget not found → expect API_ERROR / non-200
BAD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${DEMO_API}/budget?id=00000000-0000-0000-0000-000000000000")
if [ "$BAD_STATUS" != "200" ]; then
  pass "invalid budget ID returns non-200 (got HTTP $BAD_STATUS)"
else
  # Some APIs return 200 with empty data — check that our parser catches it
  BAD_TOTAL=$(curl -s "${DEMO_API}/budget?id=00000000-0000-0000-0000-000000000000" \
    | jq -r '.data.spendLimit // 0')
  if [ "$BAD_TOTAL" = "null" ] || [ "$BAD_TOTAL" = "0" ]; then
    pass "invalid budget ID: parser correctly identifies zero/null spend limit"
  else
    fail "invalid budget ID: expected null/zero spend limit, got '$BAD_TOTAL'"
  fi
fi

# Test 3e: Verify demo API budget fields match what our action expects
RAW=$(curl -s "${DEMO_API}/budget?id=${BUDGET_ID_PLENTY}")
HAS_SPEND_LIMIT=$(echo "$RAW" | jq 'has("data") and (.data | has("spendLimit"))')
HAS_CURRENT_SPEND=$(echo "$RAW" | jq 'has("data") and (.data | has("currentSpend"))')
assert_eq "API response has .data.spendLimit"   "$HAS_SPEND_LIMIT"   "true"
assert_eq "API response has .data.currentSpend" "$HAS_CURRENT_SPEND" "true"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
