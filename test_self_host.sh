#!/bin/bash
set -e

echo "=== Clean rebuild ==="
rm -rf zig-out .zig-cache
zig build
rm -f /tmp/weft1 /tmp/weft2 /tmp/weft3 /tmp/t /tmp/t2 /tmp/t3

echo "=== Seed → weft1 ==="
./zig-out/bin/weft compile compiler/main.weft -o /tmp/weft1
codesign -fs - /tmp/weft1

echo "=== weft1 regression tests ==="
PASS=0; FAIL=0
run_test() {
  local name="$1" expected="$2" input="$3"
  echo "$input" | /tmp/weft1 > /tmp/t && codesign -s - /tmp/t 2>/dev/null && chmod +x /tmp/t
  local got=$(/tmp/t 2>/dev/null; echo $?)
  if [ "$got" = "$expected" ]; then
    echo "  ✓ $name = $got"
    PASS=$((PASS+1))
  else
    echo "  ✗ $name = $got (expected $expected)"
    FAIL=$((FAIL+1))
  fi
}
run_test "simple" "42" 'fn main() -> i64 { 42 }'
run_test "factorial" "120" 'fn factorial(n: i64) -> i64 { if n <= 1 { 1 } else { n * factorial(n - 1) } } fn main() -> i64 { factorial(5) }'
run_test "fib" "55" 'fn fib(n: i64) -> i64 { if n <= 1 { n } else { fib(n - 1) + fib(n - 2) } } fn main() -> i64 { fib(10) }'
run_test "string" "5" 'fn main() -> i64 { let s = "hello" __str_len(s) }'
run_test "buf_new" "100" 'fn buf_new(cap: i64) -> i64 { let h = __bump_alloc(24) let d = __bump_alloc(cap) __mem_store64(h, d) __mem_store64(h + 8, 0) __mem_store64(h + 16, cap) h } fn main() -> i64 { let b = buf_new(100) __mem_load64(b + 16) }'
run_test "while" "42" 'fn main() -> i64 { let mut x = 0 while x < 42 { x = x + 1 } x }'
run_test "sum" "45" 'fn main() -> i64 { let mut x = 0 let mut i = 0 while i < 10 { x = x + i i = i + 1 } x }'
run_test "nested_while" "12" 'fn main() -> i64 { let mut sum = 0 let mut i = 0 while i < 3 { let mut j = 0 while j < 4 { sum = sum + 1 j = j + 1 } i = i + 1 } sum }'
echo "weft1: $PASS passed, $FAIL failed"

echo "=== weft1 → weft2 ==="
/tmp/weft1 < compiler/main.weft > /tmp/weft2
codesign -fs - /tmp/weft2 && chmod +x /tmp/weft2

echo "=== weft2 tests ==="
PASS2=0; FAIL2=0
run_test2() {
  local name="$1" expected="$2" input="$3"
  echo "$input" | /tmp/weft2 > /tmp/t2 && codesign -s - /tmp/t2 2>/dev/null && chmod +x /tmp/t2
  local got=$(/tmp/t2 2>/dev/null; echo $?)
  if [ "$got" = "$expected" ]; then
    echo "  ✓ $name = $got"
    PASS2=$((PASS2+1))
  else
    echo "  ✗ $name = $got (expected $expected)"
    FAIL2=$((FAIL2+1))
  fi
}
run_test2 "simple" "42" 'fn main() -> i64 { 42 }'
run_test2 "factorial" "120" 'fn factorial(n: i64) -> i64 { if n <= 1 { 1 } else { n * factorial(n - 1) } } fn main() -> i64 { factorial(5) }'
run_test2 "while" "42" 'fn main() -> i64 { let mut x = 0 while x < 42 { x = x + 1 } x }'
echo "weft2: $PASS2 passed, $FAIL2 failed"

echo "=== weft2 → weft3 (bootstrap gate) ==="
/tmp/weft2 < compiler/main.weft > /tmp/weft3
codesign -fs - /tmp/weft3 && chmod +x /tmp/weft3
echo 'fn main() -> i64 { 42 }' | /tmp/weft3 > /tmp/t3 && codesign -s - /tmp/t3 && chmod +x /tmp/t3
got=$(/tmp/t3 2>/dev/null; echo $?)
echo "weft3 simple: $got (expected 42)"

echo ""
echo "=== Summary ==="
echo "weft1: $PASS/$((PASS+FAIL))"
echo "weft2: $PASS2/$((PASS2+FAIL2))"
