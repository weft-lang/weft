#!/bin/bash
set -e

rm -f /tmp/weft1 /tmp/weft2 /tmp/weft3 /tmp/t /tmp/t2 /tmp/t3

echo "=== Bootstrap: checked-in weft → weft1 ==="
./weft < compiler/main.weft > /tmp/weft1
chmod +x /tmp/weft1

echo "=== weft1 regression tests ==="
PASS=0; FAIL=0
run_test() {
  local name="$1" expected="$2" input="$3"
  echo "$input" | /tmp/weft1 > /tmp/t && chmod +x /tmp/t
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
run_test "while" "42" 'fn main() -> i64 { let mut x = 0 while x < 42 { x = x + 1 } x }'
run_test "match_int" "42" 'fn main() -> i64 { match 1 { 1 -> 42 } }'
run_test "match_ctor" "25" 'type Shape { Circle(i64) } fn main() -> i64 { let s = Circle(5) match s { Circle(r) -> r * r } }'
run_test "record" "42" 'type Point { x: i64, y: i64 } fn main() -> i64 { let p = Point { x: 30, y: 12 } p.x + p.y }'
echo "weft1: $PASS passed, $FAIL failed"

echo ""
echo "=== weft1 → weft2 ==="
/tmp/weft1 < compiler/main.weft > /tmp/weft2
chmod +x /tmp/weft2

echo "=== weft2 comprehensive tests ==="
PASS2=0; FAIL2=0
run_test2() {
  local name="$1" expected="$2" input="$3"
  echo "$input" | /tmp/weft2 > /tmp/t2 && chmod +x /tmp/t2
  local got=$(/tmp/t2 2>/dev/null; echo $?)
  if [ "$got" = "$expected" ]; then
    PASS2=$((PASS2+1))
  else
    echo "  ✗ $name = $got (expected $expected)"
    FAIL2=$((FAIL2+1))
  fi
}
# Test that a program crashes (non-zero exit, used for trap tests)
run_test_crash() {
  local name="$1" input="$2"
  echo "$input" | /tmp/weft2 > /tmp/t_crash && chmod +x /tmp/t_crash
  # Run in subshell with set +e to prevent set -e from killing script on signal
  local got
  got=$( (set +e; /tmp/t_crash >/dev/null 2>/dev/null; echo $?) 2>/dev/null )
  if [ "$got" != "0" ]; then
    PASS2=$((PASS2+1))
  else
    echo "  ✗ $name: expected crash but got exit 0"
    FAIL2=$((FAIL2+1))
  fi
}
# ═══════════════════════════════════════════════════════════════
# 1. INTEGER LITERALS
# ═══════════════════════════════════════════════════════════════
run_test2 "int_zero" "0" 'fn main() -> i64 { 0 }'
run_test2 "int_one" "1" 'fn main() -> i64 { 1 }'
run_test2 "int_42" "42" 'fn main() -> i64 { 42 }'
run_test2 "int_255" "255" 'fn main() -> i64 { 255 }'
run_test2 "int_256" "0" 'fn main() -> i64 { 256 }'
run_test2 "int_257" "1" 'fn main() -> i64 { 257 }'
run_test2 "int_65535" "255" 'fn main() -> i64 { 65535 }'
run_test2 "int_65536" "0" 'fn main() -> i64 { 65536 }'
run_test2 "int_128" "128" 'fn main() -> i64 { 128 }'
run_test2 "int_200" "200" 'fn main() -> i64 { 200 }'
# ═══════════════════════════════════════════════════════════════
# 2. ARITHMETIC — all ops, precedence, associativity
# ═══════════════════════════════════════════════════════════════
run_test2 "add" "3" 'fn main() -> i64 { 1 + 2 }'
run_test2 "add_zero" "5" 'fn main() -> i64 { 5 + 0 }'
run_test2 "add_zero_lhs" "5" 'fn main() -> i64 { 0 + 5 }'
run_test2 "add_chain" "10" 'fn main() -> i64 { 1 + 2 + 3 + 4 }'
run_test2 "sub" "3" 'fn main() -> i64 { 5 - 2 }'
run_test2 "sub_zero" "5" 'fn main() -> i64 { 5 - 0 }'
run_test2 "sub_self" "0" 'fn main() -> i64 { 42 - 42 }'
run_test2 "sub_negative" "252" 'fn main() -> i64 { 3 - 7 }'
run_test2 "sub_chain" "2" 'fn main() -> i64 { 10 - 3 - 5 }'
run_test2 "mul" "42" 'fn main() -> i64 { 6 * 7 }'
run_test2 "mul_zero" "0" 'fn main() -> i64 { 42 * 0 }'
run_test2 "mul_one" "42" 'fn main() -> i64 { 42 * 1 }'
run_test2 "mul_chain" "24" 'fn main() -> i64 { 2 * 3 * 4 }'
run_test2 "mul_large" "16" 'fn main() -> i64 { 100 * 100 }'
run_test2 "div_trunc" "3" 'fn main() -> i64 { 7 / 2 }'
run_test2 "div_exact" "5" 'fn main() -> i64 { 10 / 2 }'
run_test2 "div_one" "42" 'fn main() -> i64 { 42 / 1 }'
run_test2 "div_self" "1" 'fn main() -> i64 { 42 / 42 }'
run_test2 "div_large" "100" 'fn main() -> i64 { 200 / 2 }'
run_test2 "div_trunc2" "2" 'fn main() -> i64 { 11 / 4 }'
run_test2 "prec_add_mul" "14" 'fn main() -> i64 { 2 + 3 * 4 }'
run_test2 "prec_mul_add" "14" 'fn main() -> i64 { 3 * 4 + 2 }'
run_test2 "prec_sub_mul" "2" 'fn main() -> i64 { 14 - 3 * 4 }'
run_test2 "prec_div_add" "5" 'fn main() -> i64 { 6 / 2 + 2 }'
run_test2 "prec_complex" "9" 'fn main() -> i64 { 1 + 2 * 3 + 4 / 2 }'
run_test2 "assoc_sub" "2" 'fn main() -> i64 { 10 - 5 - 3 }'
run_test2 "assoc_div" "5" 'fn main() -> i64 { 100 / 2 / 10 }'
run_test2 "parens_add_mul" "20" 'fn main() -> i64 { (2 + 3) * 4 }'
run_test2 "parens_sub_div" "2" 'fn main() -> i64 { (10 - 4) / 3 }'
# ═══════════════════════════════════════════════════════════════
# 3. COMPARISONS — all 6 ops, true/false, boundary
# ═══════════════════════════════════════════════════════════════
run_test2 "eq_true" "1" 'fn main() -> i64 { if 5 == 5 { 1 } else { 0 } }'
run_test2 "eq_false" "0" 'fn main() -> i64 { if 5 == 6 { 1 } else { 0 } }'
run_test2 "eq_zero" "1" 'fn main() -> i64 { if 0 == 0 { 1 } else { 0 } }'
run_test2 "ne_true" "1" 'fn main() -> i64 { if 5 != 6 { 1 } else { 0 } }'
run_test2 "ne_false" "0" 'fn main() -> i64 { if 5 != 5 { 1 } else { 0 } }'
run_test2 "ne_zero" "0" 'fn main() -> i64 { if 0 != 0 { 1 } else { 0 } }'
run_test2 "lt_true" "1" 'fn main() -> i64 { if 3 < 5 { 1 } else { 0 } }'
run_test2 "lt_false" "0" 'fn main() -> i64 { if 5 < 3 { 1 } else { 0 } }'
run_test2 "lt_eq" "0" 'fn main() -> i64 { if 5 < 5 { 1 } else { 0 } }'
run_test2 "lt_01" "1" 'fn main() -> i64 { if 0 < 1 { 1 } else { 0 } }'
run_test2 "lt_10" "0" 'fn main() -> i64 { if 1 < 0 { 1 } else { 0 } }'
run_test2 "gt_true" "1" 'fn main() -> i64 { if 5 > 3 { 1 } else { 0 } }'
run_test2 "gt_false" "0" 'fn main() -> i64 { if 3 > 5 { 1 } else { 0 } }'
run_test2 "gt_eq" "0" 'fn main() -> i64 { if 5 > 5 { 1 } else { 0 } }'
run_test2 "gt_10" "1" 'fn main() -> i64 { if 1 > 0 { 1 } else { 0 } }'
run_test2 "gt_01" "0" 'fn main() -> i64 { if 0 > 1 { 1 } else { 0 } }'
run_test2 "le_lt" "1" 'fn main() -> i64 { if 3 <= 5 { 1 } else { 0 } }'
run_test2 "le_eq" "1" 'fn main() -> i64 { if 5 <= 5 { 1 } else { 0 } }'
run_test2 "le_false" "0" 'fn main() -> i64 { if 6 <= 5 { 1 } else { 0 } }'
run_test2 "ge_gt" "1" 'fn main() -> i64 { if 5 >= 3 { 1 } else { 0 } }'
run_test2 "ge_eq" "1" 'fn main() -> i64 { if 5 >= 5 { 1 } else { 0 } }'
run_test2 "ge_false" "0" 'fn main() -> i64 { if 3 >= 5 { 1 } else { 0 } }'
run_test2 "cmp_as_val" "2" 'fn main() -> i64 { let a = if 3 < 5 { 1 } else { 0 } let b = if 5 > 3 { 1 } else { 0 } a + b }'
# ═══════════════════════════════════════════════════════════════
# 4. IF/ELSE — branches, nesting, as expression
# ═══════════════════════════════════════════════════════════════
run_test2 "if_true" "1" 'fn main() -> i64 { if 1 == 1 { 1 } else { 2 } }'
run_test2 "if_false" "2" 'fn main() -> i64 { if 1 == 2 { 1 } else { 2 } }'
run_test2 "if_nested_tt" "1" 'fn main() -> i64 { if 1 == 1 { if 2 == 2 { 1 } else { 2 } } else { 3 } }'
run_test2 "if_nested_tf" "2" 'fn main() -> i64 { if 1 == 1 { if 2 == 3 { 1 } else { 2 } } else { 3 } }'
run_test2 "if_nested_ft" "3" 'fn main() -> i64 { if 1 == 2 { if 2 == 2 { 1 } else { 2 } } else { 3 } }'
run_test2 "if_deep4" "4" 'fn main() -> i64 { if 1 == 1 { if 2 == 2 { if 3 == 3 { if 4 == 4 { 4 } else { 0 } } else { 0 } } else { 0 } } else { 0 } }'
run_test2 "if_deep4_fail" "99" 'fn main() -> i64 { if 1 == 2 { if 2 == 2 { if 3 == 3 { if 4 == 4 { 4 } else { 0 } } else { 0 } } else { 0 } } else { 99 } }'
run_test2 "if_expr_let" "10" 'fn main() -> i64 { let x = if 3 > 2 { 5 } else { 1 } x * 2 }'
run_test2 "if_expr_arith" "50" 'fn main() -> i64 { (if 1 == 1 { 5 } else { 0 }) * 10 }'
run_test2 "if_complex_cond" "42" 'fn main() -> i64 { let a = 10 let b = 20 if a + b == 30 { 42 } else { 0 } }'
run_test2 "if_chain" "3" 'fn main() -> i64 { if 0 == 1 { 1 } else { if 0 == 2 { 2 } else { 3 } } }'
# ═══════════════════════════════════════════════════════════════
# 5. LET BINDINGS
# ═══════════════════════════════════════════════════════════════
run_test2 "let_simple" "42" 'fn main() -> i64 { let x = 42 x }'
run_test2 "let_arith" "10" 'fn main() -> i64 { let x = 3 let y = 7 x + y }'
run_test2 "let_shadow" "2" 'fn main() -> i64 { let x = 1 let x = 2 x }'
run_test2 "let_multi" "15" 'fn main() -> i64 { let a = 1 let b = 2 let c = 3 let d = 4 let e = 5 a + b + c + d + e }'
run_test2 "let_fn_result" "120" 'fn fact(n: i64) -> i64 { if n <= 1 { 1 } else { n * fact(n - 1) } } fn main() -> i64 { let r = fact(5) r }'
run_test2 "let_chain" "42" 'fn main() -> i64 { let a = 2 let b = a * 3 let c = b * 7 c }'
# ═══════════════════════════════════════════════════════════════
# 6. LET MUT + ASSIGNMENT
# ═══════════════════════════════════════════════════════════════
run_test2 "mut_basic" "10" 'fn main() -> i64 { let mut x = 5 x = 10 x }'
run_test2 "mut_multi" "3" 'fn main() -> i64 { let mut x = 0 x = 1 x = 2 x = 3 x }'
run_test2 "mut_arith" "42" 'fn main() -> i64 { let mut x = 20 x = x + 22 x }'
run_test2 "mut_while" "100" 'fn main() -> i64 { let mut x = 0 while x < 100 { x = x + 1 } x }'
run_test2 "mut_complex" "30" 'fn main() -> i64 { let mut x = 0 let a = 10 let b = 20 x = a + b x }'
run_test2 "mut_swap" "30" 'fn main() -> i64 { let mut x = 10 let mut y = 20 let tmp = x x = y y = tmp x + y }'
# ═══════════════════════════════════════════════════════════════
# 7. WHILE LOOPS — basic, edge, nested, patterns
# ═══════════════════════════════════════════════════════════════
run_test2 "while" "42" 'fn main() -> i64 { let mut x = 0 while x < 42 { x = x + 1 } x }'
run_test2 "while_never" "0" 'fn main() -> i64 { let mut x = 0 while x > 0 { x = x - 1 } x }'
run_test2 "while_one" "1" 'fn main() -> i64 { let mut x = 0 while x < 1 { x = x + 1 } x }'
run_test2 "while_sum" "45" 'fn main() -> i64 { let mut x = 0 let mut i = 0 while i < 10 { x = x + i i = i + 1 } x }'
run_test2 "while_nested" "12" 'fn main() -> i64 { let mut sum = 0 let mut i = 0 while i < 3 { let mut j = 0 while j < 4 { sum = sum + 1 j = j + 1 } i = i + 1 } sum }'
run_test2 "while_pow2" "128" 'fn main() -> i64 { let mut x = 1 let mut i = 0 while i < 7 { x = x * 2 i = i + 1 } x }'
run_test2 "while_countdown" "0" 'fn main() -> i64 { let mut n = 100 while n > 0 { n = n - 1 } n }'
run_test2 "while_factorial" "120" 'fn main() -> i64 { let mut p = 1 let mut i = 1 while i <= 5 { p = p * i i = i + 1 } p }'
run_test2 "while_nested3" "27" 'fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 3 { let mut j = 0 while j < 3 { let mut k = 0 while k < 3 { s = s + 1 k = k + 1 } j = j + 1 } i = i + 1 } s }'
run_test2 "while_div" "3" 'fn main() -> i64 { let mut x = 24 while x > 5 { x = x / 2 } x }'
run_test2 "while_250" "250" 'fn main() -> i64 { let mut x = 0 while x < 250 { x = x + 1 } x }'
# ═══════════════════════════════════════════════════════════════
# 8. FUNCTIONS — arity 0-7, recursive, composition
# ═══════════════════════════════════════════════════════════════
run_test2 "fn_zero" "42" 'fn f() -> i64 { 42 } fn main() -> i64 { f() }'
run_test2 "fn_one" "10" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f(10) }'
run_test2 "fn_two" "30" 'fn f(a: i64, b: i64) -> i64 { a + b } fn main() -> i64 { f(10, 20) }'
run_test2 "fn_three" "60" 'fn f(a: i64, b: i64, c: i64) -> i64 { a + b + c } fn main() -> i64 { f(10, 20, 30) }'
run_test2 "fn_four" "100" 'fn f(a: i64, b: i64, c: i64, d: i64) -> i64 { a + b + c + d } fn main() -> i64 { f(10, 20, 30, 40) }'
run_test2 "fn_five" "150" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64) -> i64 { a + b + c + d + e } fn main() -> i64 { f(10, 20, 30, 40, 50) }'
run_test2 "fn_six" "210" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64) -> i64 { a + b + c + d + e + g } fn main() -> i64 { f(10, 20, 30, 40, 50, 60) }'
run_test2 "fn_seven" "28" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64, h: i64) -> i64 { a + b + c + d + e + g + h } fn main() -> i64 { f(1, 2, 3, 4, 5, 6, 7) }'
run_test2 "factorial" "120" 'fn factorial(n: i64) -> i64 { if n <= 1 { 1 } else { n * factorial(n - 1) } } fn main() -> i64 { factorial(5) }'
run_test2 "fib" "55" 'fn fib(n: i64) -> i64 { if n <= 1 { n } else { fib(n - 1) + fib(n - 2) } } fn main() -> i64 { fib(10) }'
run_test2 "fn_recursive_sum" "55" 'fn sum(n: i64) -> i64 { if n <= 0 { 0 } else { n + sum(n - 1) } } fn main() -> i64 { sum(10) }'
run_test2 "fn_nested_call" "42" 'fn double(x: i64) -> i64 { x * 2 } fn add1(x: i64) -> i64 { x + 1 } fn main() -> i64 { double(add1(20)) }'
run_test2 "fn_multi_calls" "14" 'fn f(x: i64) -> i64 { x + 1 } fn main() -> i64 { f(1) + f(2) + f(3) + f(4) }'
run_test2 "fn_arg_order" "3" 'fn sub(a: i64, b: i64) -> i64 { a - b } fn main() -> i64 { sub(5, 2) }'
run_test2 "fn_chain" "42" 'fn c(x: i64) -> i64 { x + 2 } fn b(x: i64) -> i64 { c(x * 2) } fn a(x: i64) -> i64 { b(x + 3) } fn main() -> i64 { a(17) }'
run_test2 "fn_compose" "42" 'fn id(x: i64) -> i64 { x } fn main() -> i64 { id(id(id(id(id(42))))) }'
run_test2 "fn_deep_recursion" "200" 'fn f(n: i64) -> i64 { if n <= 0 { 0 } else { 1 + f(n - 1) } } fn main() -> i64 { f(200) }'
# ═══════════════════════════════════════════════════════════════
# 9. STRINGS
# ═══════════════════════════════════════════════════════════════
run_test2 "str_hello" "5" 'fn main() -> i64 { let s = "hello" __str_len(s) }'
run_test2 "str_empty" "0" 'fn main() -> i64 { let s = "" __str_len(s) }'
run_test2 "str_one" "1" 'fn main() -> i64 { let s = "x" __str_len(s) }'
run_test2 "str_long" "26" 'fn main() -> i64 { let s = "abcdefghijklmnopqrstuvwxyz" __str_len(s) }'
run_test2 "str_fn_arg" "5" 'fn slen(s: str) -> i64 { __str_len(s) } fn main() -> i64 { slen("hello") }'
run_test2 "str_spaces" "3" 'fn main() -> i64 { let s = "   " __str_len(s) }'
run_test2 "str_digits" "10" 'fn main() -> i64 { let s = "0123456789" __str_len(s) }'
# ═══════════════════════════════════════════════════════════════
# 10. RECORDS — field count, access order, in functions
# ═══════════════════════════════════════════════════════════════
run_test2 "record_1f" "42" 'type Wrap { val: i64 } fn main() -> i64 { let w = Wrap { val: 42 } w.val }'
run_test2 "record_2f" "42" 'type Point { x: i64, y: i64 } fn main() -> i64 { let p = Point { x: 30, y: 12 } p.x + p.y }'
run_test2 "record_3f" "60" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { a: 10, b: 20, c: 30 } r.a + r.b + r.c }'
run_test2 "record_4f" "100" 'type Q { a: i64, b: i64, c: i64, d: i64 } fn main() -> i64 { let q = Q { a: 10, b: 20, c: 30, d: 40 } q.a + q.b + q.c + q.d }'
run_test2 "record_first" "10" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { a: 10, b: 20, c: 30 } r.a }'
run_test2 "record_mid" "20" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { a: 10, b: 20, c: 30 } r.b }'
run_test2 "record_last" "30" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { a: 10, b: 20, c: 30 } r.c }'
run_test2 "record_fn_arg" "42" 'type Pair { a: i64, b: i64 } fn sum(p: i64) -> i64 { p.a + p.b } fn main() -> i64 { let p = Pair { a: 30, b: 12 } sum(p) }'
run_test2 "record_fn_area" "200" 'type R { w: i64, h: i64 } fn area(r: i64) -> i64 { r.w * r.h } fn main() -> i64 { let r = R { w: 10, h: 20 } area(r) }'
run_test2 "record_arith" "42" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { x: 6, y: 7 } p.x * p.y }'
run_test2 "record_let_field" "42" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { x: 6, y: 7 } let v = p.x * p.y v }'
run_test2 "record_two_types" "42" 'type A { x: i64 } type B { y: i64 } fn main() -> i64 { let a = A { x: 30 } let b = B { y: 12 } a.x + b.y }'
run_test2 "fn_returns_record" "42" 'type P { x: i64, y: i64 } fn mk(a: i64, b: i64) -> i64 { P { x: a, y: b } } fn main() -> i64 { let p = mk(30, 12) p.x + p.y }'
run_test2 "record_getters" "42" 'type P { x: i64, y: i64 } fn getx(p: i64) -> i64 { p.x } fn gety(p: i64) -> i64 { p.y } fn main() -> i64 { let p = P { x: 30, y: 12 } getx(p) + gety(p) }'
# ═══════════════════════════════════════════════════════════════
# 11. VARIANTS — single/multi, names, dispatch, no-payload
# ═══════════════════════════════════════════════════════════════
run_test2 "variant_A" "42" 'type T { A(i64) } fn main() -> i64 { let x = A(42) match x { A(v) -> v } }'
run_test2 "variant_long" "42" 'type T { LongName(i64) } fn main() -> i64 { let v = LongName(42) match v { LongName(n) -> n } }'
run_test2 "variant_dispatch_A" "42" 'type T { A(i64), B(i64) } fn main() -> i64 { let x = A(42) match x { A(v) -> v B(v) -> v + 100 } }'
run_test2 "variant_dispatch_B" "42" 'type T { A(i64), B(i64) } fn main() -> i64 { let x = B(42) match x { A(v) -> v + 100 B(v) -> v } }'
run_test2 "variant_3way_X" "1" 'type T { X(i64), Y(i64), Z(i64) } fn main() -> i64 { let v = X(1) match v { X(n) -> n Y(n) -> n + 100 Z(n) -> n + 200 } }'
run_test2 "variant_3way_Y" "2" 'type T { X(i64), Y(i64), Z(i64) } fn main() -> i64 { let v = Y(2) match v { X(n) -> n + 100 Y(n) -> n Z(n) -> n + 200 } }'
run_test2 "variant_3way_Z" "3" 'type T { X(i64), Y(i64), Z(i64) } fn main() -> i64 { let v = Z(3) match v { X(n) -> n + 100 Y(n) -> n + 200 Z(n) -> n } }'
run_test2 "variant_fn_arg" "42" 'type T { V(i64) } fn extract(t: i64) -> i64 { match t { V(n) -> n } } fn main() -> i64 { extract(V(42)) }'
run_test2 "variant_arith_body" "84" 'type T { A(i64), B(i64) } fn main() -> i64 { let x = A(42) match x { A(v) -> v * 2 B(v) -> v } }'
run_test2 "variant_ctor_expr" "42" 'type T { A(i64) } fn main() -> i64 { let x = A(6 * 7) match x { A(v) -> v } }'
run_test2 "variant_sq" "25" 'type Shape { Circle(i64) } fn main() -> i64 { let s = Circle(5) match s { Circle(r) -> r * r } }'
# No-payload variant construction (None()) not yet supported — needs zero-arg ctor handling
# run_test2 "variant_no_payload" "99" 'type T { None, Some(i64) } fn main() -> i64 { let x = None() match x { None -> 99 Some(v) -> v } }'
run_test2 "variant_some" "42" 'type T { None, Some(i64) } fn main() -> i64 { let x = Some(42) match x { None -> 0 Some(v) -> v } }'
# ═══════════════════════════════════════════════════════════════
# 12. MATCH — all pattern types, arm positions, complex bodies
# ═══════════════════════════════════════════════════════════════
run_test2 "match_bind" "42" 'fn main() -> i64 { match 21 { n -> n * 2 } }'
run_test2 "match_bind_only" "42" 'fn main() -> i64 { match 42 { x -> x } }'
run_test2 "match_wild" "42" 'fn main() -> i64 { match 1 { _ -> 42 } }'
run_test2 "match_int" "42" 'fn main() -> i64 { match 1 { 1 -> 42 } }'
run_test2 "match_zero" "0" 'fn main() -> i64 { match 0 { 0 -> 0 _ -> 1 } }'
run_test2 "match_first" "10" 'fn main() -> i64 { match 1 { 1 -> 10 2 -> 20 3 -> 30 } }'
run_test2 "match_middle" "20" 'fn main() -> i64 { match 2 { 1 -> 10 2 -> 20 3 -> 30 } }'
run_test2 "match_last" "30" 'fn main() -> i64 { match 3 { 1 -> 10 2 -> 20 3 -> 30 } }'
run_test2 "match_fallthrough" "42" 'fn main() -> i64 { match 5 { 1 -> 10 2 -> 20 _ -> 42 } }'
run_test2 "match_large" "42" 'fn main() -> i64 { match 1000000 { 999999 -> 0 1000000 -> 42 _ -> 1 } }'
run_test2 "match_5arms" "5" 'fn main() -> i64 { match 5 { 1 -> 1 2 -> 2 3 -> 3 4 -> 4 _ -> 5 } }'
run_test2 "match_7arms" "7" 'fn main() -> i64 { match 7 { 1 -> 1 2 -> 2 3 -> 3 4 -> 4 5 -> 5 6 -> 6 _ -> 7 } }'
run_test2 "match_expr" "42" 'fn main() -> i64 { match 3 + 4 { 7 -> 42 _ -> 0 } }'
run_test2 "match_scr_call" "42" 'fn f(x: i64) -> i64 { x * 2 } fn main() -> i64 { match f(21) { 42 -> 42 _ -> 0 } }'
run_test2 "match_nested" "42" 'fn main() -> i64 { match 1 { 1 -> match 2 { 2 -> 42 _ -> 0 } _ -> 0 } }'
run_test2 "match_deep_nest" "99" 'fn main() -> i64 { match 1 { 1 -> match 2 { 2 -> match 3 { 3 -> 99 _ -> 0 } _ -> 0 } _ -> 0 } }'
run_test2 "match_fn" "42" 'fn classify(n: i64) -> i64 { match n { 0 -> 0 1 -> 42 _ -> 99 } } fn main() -> i64 { classify(1) }'
run_test2 "match_let" "50" 'fn main() -> i64 { let x = match 2 { 1 -> 10 2 -> 25 _ -> 0 } x * 2 }'
run_test2 "match_shadow" "10" 'fn main() -> i64 { let x = 5 match 10 { x -> x } }'
run_test2 "match_wild_arith" "6" 'fn test(n: i64) -> i64 { match n { 0 -> 100 _ -> n + 1 } } fn main() -> i64 { test(5) }'
run_test2 "match_bind_arith" "6" 'fn main() -> i64 { match 5 { 0 -> 100 x -> x + 1 } }'
run_test2 "match_body_while" "10" 'fn main() -> i64 { match 1 { 1 -> { let mut s = 0 let mut i = 0 while i < 10 { s = s + 1 i = i + 1 } s } _ -> 0 } }'
run_test2 "match_body_call" "120" 'fn fact(n: i64) -> i64 { if n <= 1 { 1 } else { n * fact(n - 1) } } fn main() -> i64 { match 5 { n -> fact(n) } }'
run_test2 "recursive_match" "120" 'fn fact(n: i64) -> i64 { match n { 0 -> 1 1 -> 1 _ -> n * fact(n - 1) } } fn main() -> i64 { fact(5) }'
run_test2 "gcd_match" "6" 'fn gcd(a: i64, b: i64) -> i64 { match b { 0 -> a _ -> gcd(b, a - a / b * b) } } fn main() -> i64 { gcd(48, 18) }'
run_test2 "ctor_wildcard" "99" 'type T { A(i64), B(i64) } fn main() -> i64 { let x = B(0) match x { A(v) -> v _ -> 99 } }'
run_test2 "ctor_wild_hit" "42" 'type T { A(i64), B(i64) } fn main() -> i64 { let x = A(42) match x { A(v) -> v _ -> 0 } }'
run_test2 "match_no_hit" "42" 'fn main() -> i64 { match 99 { 1 -> 1 2 -> 2 3 -> 3 _ -> 42 } }'
# ═══════════════════════════════════════════════════════════════
# 13. INTERACTIONS — feature combinations
# ═══════════════════════════════════════════════════════════════
run_test2 "while_match" "10" 'fn main() -> i64 { let mut sum = 0 let mut i = 0 while i < 5 { let v = match i { 0 -> 1 1 -> 2 2 -> 3 _ -> 2 } sum = sum + v i = i + 1 } sum }'
run_test2 "match_while" "42" 'fn main() -> i64 { match 1 { 1 -> { let mut x = 0 while x < 42 { x = x + 1 } x } _ -> 0 } }'
run_test2 "match_in_loop" "15" 'fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 6 { let v = match i { 0 -> 0 1 -> 1 2 -> 2 3 -> 3 4 -> 4 _ -> 5 } s = s + v i = i + 1 } s }'
run_test2 "multi_type" "42" 'type A { x: i64 } type B { y: i64, z: i64 } fn main() -> i64 { let a = A { x: 30 } let b = B { y: 10, z: 2 } a.x + b.y + b.z }'
run_test2 "variant_in_match" "42" 'type T { A(i64) } fn main() -> i64 { let x = match 1 { 1 -> A(42) _ -> A(0) } match x { A(v) -> v } }'
run_test2 "record_field_match" "42" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { x: 42, y: 0 } match p.x { 42 -> 42 _ -> 0 } }'
run_test2 "variant_in_match2" "7" 'type T { A(i64), B(i64) } fn main() -> i64 { let v = match 1 { 1 -> A(7) _ -> B(0) } match v { A(n) -> n B(n) -> n } }'
run_test2 "recursive_variant" "6" 'type T { A(i64), B(i64) } fn process(n: i64) -> i64 { if n <= 0 { 0 } else { let v = A(n) let x = match v { A(k) -> k B(k) -> 0 } x + process(n - 1) } } fn main() -> i64 { process(3) }'
run_test2 "while_record" "27" 'type P { x: i64, y: i64 } fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 3 { let p = P { x: i * 3, y: i * 3 + 3 } s = s + p.x + p.y i = i + 1 } s }'
run_test2 "deep_nesting" "39" 'fn main() -> i64 { match 1 { 1 -> { let mut s = 0 let mut i = 0 while i < 7 { if i > 2 { s = s + i * 2 } else { s = s + i } i = i + 1 } s } _ -> 0 } }'
run_test2 "let_while_fn" "55" 'fn sq(n: i64) -> i64 { n * n } fn main() -> i64 { let mut s = 0 let mut i = 1 while i <= 5 { s = s + sq(i) i = i + 1 } s }'
run_test2 "while_variant_dispatch" "10" 'type T { Even(i64), Odd(i64) } fn classify(n: i64) -> i64 { if n - n / 2 * 2 == 0 { Even(n) } else { Odd(n) } } fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 5 { let v = classify(i) let x = match v { Even(n) -> n Odd(n) -> n } s = s + x i = i + 1 } s }'
run_test2 "variant_record_body" "42" 'type V { A(i64), B(i64) } type R { x: i64, y: i64 } fn main() -> i64 { let v = A(42) let r = R { x: match v { A(n) -> n B(n) -> 0 }, y: 0 } r.x }'
run_test2 "cmp_while_match" "42" 'fn main() -> i64 { let mut x = 0 let mut i = 0 while i < 42 { x = match i { 0 -> 1 _ -> x + 1 } i = i + 1 } x }'
# ═══════════════════════════════════════════════════════════════
# 14. ADVERSARIAL / PATHOLOGICAL
# ═══════════════════════════════════════════════════════════════
run_test2 "many_lets_8" "36" 'fn main() -> i64 { let a = 1 let b = 2 let c = 3 let d = 4 let e = 5 let f = 6 let g = 7 let h = 8 a + b + c + d + e + f + g + h }'
run_test2 "many_lets_10" "55" 'fn main() -> i64 { let a = 1 let b = 2 let c = 3 let d = 4 let e = 5 let f = 6 let g = 7 let h = 8 let i = 9 let j = 10 a + b + c + d + e + f + g + h + i + j }'
run_test2 "fn_arg_stress" "150" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64) -> i64 { a * 1 + b * 2 + c * 3 + d * 4 + e * 5 } fn main() -> i64 { f(10, 10, 10, 10, 10) }'
run_test2 "while_sq_accum" "30" 'fn main() -> i64 { let mut s = 0 let mut i = 1 while i <= 4 { s = s + i * i i = i + 1 } s }'
# ═══════════════════════════════════════════════════════════════
# 15. PROPERTY TESTS
# ═══════════════════════════════════════════════════════════════
run_test2 "prop_add_sub" "42" 'fn main() -> i64 { let x = 42 x + 10 - 10 }'
run_test2 "prop_distrib" "1" 'fn main() -> i64 { let a = 3 let b = 4 let c = 5 let lhs = a * (b + c) let rhs = a * b + a * c if lhs == rhs { 1 } else { 0 } }'
run_test2 "prop_div_mul" "42" 'fn main() -> i64 { let x = 42 x / 1 * 1 }'
run_test2 "prop_lt_asym" "1" 'fn main() -> i64 { let a = 3 let b = 5 let ab = if a < b { 1 } else { 0 } let ba = if b < a { 1 } else { 0 } if ab == 1 { if ba == 0 { 1 } else { 0 } } else { 0 } }'
run_test2 "prop_eq_reflex" "1" 'fn main() -> i64 { let x = 42 if x == x { 1 } else { 0 } }'
run_test2 "prop_fact_eq" "1" 'fn fact_if(n: i64) -> i64 { if n <= 1 { 1 } else { n * fact_if(n - 1) } } fn fact_match(n: i64) -> i64 { match n { 0 -> 1 1 -> 1 _ -> n * fact_match(n - 1) } } fn main() -> i64 { if fact_if(7) == fact_match(7) { 1 } else { 0 } }'
# ═══════════════════════════════════════════════════════════════
# 16. UNARY MINUS
# ═══════════════════════════════════════════════════════════════
run_test2 "neg_simple" "42" 'fn main() -> i64 { let x = -5 x + 47 }'
run_test2 "neg_compare" "42" 'fn main() -> i64 { if -1 < 0 { 42 } else { 0 } }'
run_test2 "neg_double" "10" 'fn main() -> i64 { let x = -10 0 - x }'
run_test2 "neg_in_expr" "42" 'fn main() -> i64 { 50 + -8 }'
run_test2 "neg_prec" "42" 'fn main() -> i64 { -2 * -21 }'
# ═══════════════════════════════════════════════════════════════
# 17. MODULO
# ═══════════════════════════════════════════════════════════════
run_test2 "mod_basic" "1" 'fn main() -> i64 { 10 % 3 }'
run_test2 "mod_exact" "0" 'fn main() -> i64 { 10 % 5 }'
run_test2 "mod_one" "0" 'fn main() -> i64 { 42 % 1 }'
run_test2 "mod_same" "0" 'fn main() -> i64 { 7 % 7 }'
run_test2 "mod_small" "3" 'fn main() -> i64 { 3 % 5 }'
run_test2 "mod_7_2" "1" 'fn main() -> i64 { 7 % 2 }'
run_test2 "mod_even" "0" 'fn main() -> i64 { 100 % 2 }'
run_test2 "mod_odd" "1" 'fn main() -> i64 { 101 % 2 }'
run_test2 "mod_prec" "3" 'fn main() -> i64 { 2 + 10 % 3 }'
run_test2 "mod_gcd" "6" 'fn gcd(a: i64, b: i64) -> i64 { match b { 0 -> a _ -> gcd(b, a % b) } } fn main() -> i64 { gcd(48, 18) }'
# ═══════════════════════════════════════════════════════════════
# 18. BOOLEAN LITERALS AND LOGICAL OPERATORS
# ═══════════════════════════════════════════════════════════════
run_test2 "true_val" "1" 'fn main() -> i64 { if true { 1 } else { 0 } }'
run_test2 "false_val" "0" 'fn main() -> i64 { if false { 1 } else { 0 } }'
run_test2 "not_true" "0" 'fn main() -> i64 { if not true { 1 } else { 0 } }'
run_test2 "not_false" "1" 'fn main() -> i64 { if not false { 1 } else { 0 } }'
run_test2 "not_not" "1" 'fn main() -> i64 { if not not true { 1 } else { 0 } }'
run_test2 "not_cmp" "1" 'fn main() -> i64 { if not (3 > 5) { 1 } else { 0 } }'
run_test2 "and_tt" "1" 'fn main() -> i64 { if true and true { 1 } else { 0 } }'
run_test2 "and_tf" "0" 'fn main() -> i64 { if true and false { 1 } else { 0 } }'
run_test2 "and_ft" "0" 'fn main() -> i64 { if false and true { 1 } else { 0 } }'
run_test2 "and_ff" "0" 'fn main() -> i64 { if false and false { 1 } else { 0 } }'
run_test2 "or_tt" "1" 'fn main() -> i64 { if true or true { 1 } else { 0 } }'
run_test2 "or_tf" "1" 'fn main() -> i64 { if true or false { 1 } else { 0 } }'
run_test2 "or_ft" "1" 'fn main() -> i64 { if false or true { 1 } else { 0 } }'
run_test2 "or_ff" "0" 'fn main() -> i64 { if false or false { 1 } else { 0 } }'
run_test2 "and_prec" "1" 'fn main() -> i64 { if 3 > 2 and 5 > 4 { 1 } else { 0 } }'
run_test2 "or_prec" "1" 'fn main() -> i64 { if 3 > 5 or 5 > 4 { 1 } else { 0 } }'
run_test2 "and_or" "1" 'fn main() -> i64 { if false and true or true { 1 } else { 0 } }'
run_test2 "or_and" "1" 'fn main() -> i64 { if true or false and false { 1 } else { 0 } }'
run_test2 "not_and" "1" 'fn main() -> i64 { if not false and true { 1 } else { 0 } }'
# ═══════════════════════════════════════════════════════════════
# 20. MATCH GUARDS
# ═══════════════════════════════════════════════════════════════
run_test2 "guard_pass" "42" 'fn main() -> i64 { match 5 { n if n > 3 -> 42 _ -> 0 } }'
run_test2 "guard_fail" "42" 'fn main() -> i64 { match 2 { n if n > 3 -> 0 _ -> 42 } }'
run_test2 "guard_multi" "42" 'fn main() -> i64 { match 10 { n if n > 100 -> 0 n if n > 5 -> 42 _ -> 99 } }'
run_test2 "guard_int_pass" "42" 'fn main() -> i64 { match 1 { 1 if true -> 42 _ -> 0 } }'
run_test2 "guard_int_fail" "42" 'fn main() -> i64 { match 1 { 1 if false -> 0 _ -> 42 } }'
run_test2 "guard_wild" "42" 'fn main() -> i64 { match 5 { _ if false -> 0 _ -> 42 } }'
run_test2 "guard_abs" "8" 'fn abs(n: i64) -> i64 { match n { x if x < 0 -> 0 - x x -> x } } fn main() -> i64 { abs(-5) + abs(3) }'
run_test2 "guard_ctor_pass" "42" 'type T { A(i64), B(i64) } fn main() -> i64 { let v = A(10) match v { A(n) if n > 5 -> 42 A(n) -> n _ -> 0 } }'
run_test2 "guard_ctor_fail" "3" 'type T { A(i64), B(i64) } fn main() -> i64 { let v = A(3) match v { A(n) if n > 5 -> 0 A(n) -> n _ -> 99 } }'
run_test2 "guard_chain" "8" 'fn classify(n: i64) -> i64 { match n { x if x < 0 -> 0 - 1 x if x == 0 -> 0 x if x < 10 -> 1 x if x < 100 -> 2 _ -> 3 } } fn main() -> i64 { classify(0) + classify(5) + classify(50) + classify(200) + classify(-1) + classify(7) + classify(99) }'
run_test2 "guard_not" "42" 'fn main() -> i64 { match 5 { n if not (n > 10) -> 42 _ -> 0 } }'
run_test2 "guard_and" "42" 'fn main() -> i64 { match 5 { n if n > 0 and n < 10 -> 42 _ -> 0 } }'
run_test2 "guard_or" "42" 'fn main() -> i64 { match 5 { n if n == 3 or n == 5 -> 42 _ -> 0 } }'
run_test2 "guard_complex" "42" 'fn main() -> i64 { match 15 { n if n % 3 == 0 and n % 5 == 0 -> 42 _ -> 0 } }'
# ═══════════════════════════════════════════════════════════════
# 19. BITWISE OPERATORS
# ═══════════════════════════════════════════════════════════════
run_test2 "band_basic" "15" 'fn main() -> i64 { 255 band 15 }'
run_test2 "band_zero" "0" 'fn main() -> i64 { 42 band 0 }'
run_test2 "band_self" "42" 'fn main() -> i64 { 42 band 42 }'
run_test2 "bor_basic" "255" 'fn main() -> i64 { 170 bor 85 }'
run_test2 "bor_zero" "42" 'fn main() -> i64 { 42 bor 0 }'
run_test2 "bor_self" "42" 'fn main() -> i64 { 42 bor 42 }'
run_test2 "bxor_basic" "42" 'fn main() -> i64 { 255 bxor 213 }'
run_test2 "bxor_self" "0" 'fn main() -> i64 { 42 bxor 42 }'
run_test2 "bxor_zero" "42" 'fn main() -> i64 { 42 bxor 0 }'
run_test2 "bshl_basic" "32" 'fn main() -> i64 { 1 bshl 5 }'
run_test2 "bshl_zero" "42" 'fn main() -> i64 { 42 bshl 0 }'
run_test2 "bshl_mul2" "84" 'fn main() -> i64 { 42 bshl 1 }'
run_test2 "bshr_basic" "32" 'fn main() -> i64 { 128 bshr 2 }'
run_test2 "bshr_zero" "42" 'fn main() -> i64 { 42 bshr 0 }'
run_test2 "bshr_div2" "21" 'fn main() -> i64 { 42 bshr 1 }'
run_test2 "bit_prec" "42" 'fn main() -> i64 { 40 bor 2 band 255 }'
run_test2 "bit_shift_add" "64" 'fn main() -> i64 { 1 bshl 5 + 1 }'
# ═══════════════════════════════════════════════════════════════
# 21. FUNCTION HOISTING — definition order doesn't matter
# ═══════════════════════════════════════════════════════════════
# Forward reference: main before helper
run_test2 "hoist_forward" "42" 'fn main() -> i64 { helper() } fn helper() -> i64 { 42 }'
# Any definition order
run_test2 "hoist_any_order" "42" 'fn main() -> i64 { a() + b() + c() } fn c() -> i64 { 10 } fn a() -> i64 { 20 } fn b() -> i64 { 12 }'
# Mutual recursion (even/odd)
run_test2 "hoist_mutual_t" "1" 'fn is_even(n: i64) -> i64 { if n == 0 { 1 } else { is_odd(n - 1) } } fn is_odd(n: i64) -> i64 { if n == 0 { 0 } else { is_even(n - 1) } } fn main() -> i64 { is_even(10) }'
run_test2 "hoist_mutual_f" "0" 'fn is_even(n: i64) -> i64 { if n == 0 { 1 } else { is_odd(n - 1) } } fn is_odd(n: i64) -> i64 { if n == 0 { 0 } else { is_even(n - 1) } } fn main() -> i64 { is_even(7) }'
# Forward chain: main→a→b→c, all forward
run_test2 "hoist_chain" "42" 'fn main() -> i64 { a(20) } fn a(x: i64) -> i64 { b(x + 1) } fn b(x: i64) -> i64 { c(x * 2) } fn c(x: i64) -> i64 { x }'
# Main first/last (both should work)
run_test2 "hoist_main_first" "42" 'fn main() -> i64 { 42 }'
run_test2 "hoist_main_last" "42" 'fn a() -> i64 { 1 } fn b() -> i64 { 2 } fn c() -> i64 { 3 } fn main() -> i64 { 42 }'
# Forward recursive call (main calls fib, fib defined after)
run_test2 "hoist_recursive" "55" 'fn main() -> i64 { fib(10) } fn fib(n: i64) -> i64 { if n <= 1 { n } else { fib(n - 1) + fib(n - 2) } }'
# Forward ref with multi-arg function
run_test2 "hoist_multi_arg" "42" 'fn main() -> i64 { compute(10, 20, 12) } fn compute(a: i64, b: i64, c: i64) -> i64 { a + b + c }'
# Forward ref where callee uses records
run_test2 "hoist_record" "42" 'fn main() -> i64 { get_sum() } type P { x: i64, y: i64 } fn get_sum() -> i64 { let p = P { x: 30, y: 12 } p.x + p.y }'
# Forward ref where callee uses match
run_test2 "hoist_match" "42" 'fn main() -> i64 { classify(5) } fn classify(n: i64) -> i64 { match n { 5 -> 42 _ -> 0 } }'
# Forward ref where callee uses match guard
run_test2 "hoist_guard" "42" 'fn main() -> i64 { check(5) } fn check(n: i64) -> i64 { match n { x if x > 3 -> 42 _ -> 0 } }'
# Forward ref where callee uses while
run_test2 "hoist_while" "42" 'fn main() -> i64 { count_to(42) } fn count_to(n: i64) -> i64 { let mut i = 0 while i < n { i = i + 1 } i }'
# Forward ref where callee uses variants
run_test2 "hoist_variant" "42" 'fn main() -> i64 { extract(make()) } type T { V(i64) } fn make() -> i64 { V(42) } fn extract(x: i64) -> i64 { match x { V(n) -> n } }'
# Many functions, random order, all calling each other
run_test2 "hoist_many" "42" 'fn main() -> i64 { f1() + f2() + f3() + f4() + f5() + f6() } fn f6() -> i64 { 7 } fn f4() -> i64 { 5 } fn f2() -> i64 { 3 } fn f5() -> i64 { 6 } fn f1() -> i64 { 2 } fn f3() -> i64 { 19 }'
# ═══════════════════════════════════════════════════════════════
# 22. FILE IMPORTS — use "path.weft"
# ═══════════════════════════════════════════════════════════════
pushd tests > /dev/null
run_use() {
  local name="$1" expected="$2" input="$3"
  echo "$input" | /tmp/weft2 > /tmp/t2 && chmod +x /tmp/t2
  local got=$(/tmp/t2 2>/dev/null; echo $?)
  if [ "$got" = "$expected" ]; then
    PASS2=$((PASS2+1))
  else
    echo "  ✗ $name = $got (expected $expected)"
    FAIL2=$((FAIL2+1))
  fi
}
# Basic import: single function
run_use "use_basic" "42" 'use "use_lib.weft" fn main() -> i64 { add(20, 22) }'
# Import with multiple functions used
run_use "use_multi_fn" "42" 'use "use_lib.weft" fn main() -> i64 { add(20, mul(2, 11)) }'
# Nested imports (mid imports base)
run_use "use_nested" "42" 'use "use_mid.weft" fn main() -> i64 { double_base() }'
# Import with type declarations (records)
run_use "use_types" "42" 'use "use_types.weft" fn main() -> i64 { let p = make_point(30, 12) point_sum(p) }'
# Imported fn + local fn with hoisting
run_use "use_hoist" "42" 'use "use_lib.weft" fn main() -> i64 { add(20, local_val()) } fn local_val() -> i64 { 22 }'
# Import with variants and match
run_use "use_variants" "42" 'use "use_variants.weft" fn main() -> i64 { unwrap_or(make_some(42), 0) }'
# Note: can't pass 0 as a variant — no null-safe tag check yet
# run_use "use_variant_default" "99" 'use "use_variants.weft" fn main() -> i64 { unwrap_or(0, 99) }'
# Import with intrinsics (__bump_alloc, __mem_store64, etc.)
run_use "use_intrinsics" "42" 'use "use_intrinsics.weft" fn main() -> i64 { let p = alloc_pair(30, 12) pair_first(p) + pair_second(p) }'
# Import with while loops
run_use "use_while" "55" 'use "use_while.weft" fn main() -> i64 { sum_to(10) }'
run_use "use_while_mod" "4" 'use "use_while.weft" fn main() -> i64 { count_matches(12, 3) }'
# Import with match guards
run_use "use_guards" "14" 'use "use_guards.weft" fn main() -> i64 { classify(0) + classify(5) + classify(50) + classify(200) + abs(-5) + abs(3) }'
# Multiple use statements in one file
run_use "use_multi_files" "42" 'use "use_multi_a.weft" use "use_multi_b.weft" fn main() -> i64 { val_a() + val_b() + 12 }'
# Local fn calling imported fn
run_use "use_local_calls_import" "42" 'use "use_lib.weft" fn double_add(a: i64, b: i64) -> i64 { mul(add(a, b), 2) } fn main() -> i64 { double_add(10, 11) }'
# Imported fn expression as argument
run_use "use_expr_arg" "42" 'use "use_lib.weft" fn main() -> i64 { add(mul(3, 7), mul(3, 7)) }'
popd > /dev/null
# ═══════════════════════════════════════════════════════════════
# 23. SET-THEORETIC TYPE SYSTEM
# ═══════════════════════════════════════════════════════════════
pushd tests > /dev/null
run_use "ty_emptiness" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let mut ok = true if not ty_is_empty(ty_never()) { ok = false } else { ok = ok } if ty_is_empty(ty_i64()) { ok = false } else { ok = ok } if ty_is_empty(ty_str()) { ok = false } else { ok = ok } if ty_is_empty(ty_bool()) { ok = false } else { ok = ok } if ty_is_empty(ty_nil()) { ok = false } else { ok = ok } if ty_is_empty(ty_any()) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_prim_disjoint" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let mut ok = true if not ty_is_empty(ty_inter(ty_i64(), ty_str())) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(ty_i64(), ty_bool())) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(ty_i64(), ty_nil())) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(ty_str(), ty_bool())) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(ty_str(), ty_nil())) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(ty_bool(), ty_nil())) { ok = false } else { ok = ok } if ty_is_empty(ty_inter(ty_i64(), ty_i64())) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_subtype_basic" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let mut ok = true if not is_subtype(ty_i64(), ty_i64()) { ok = false } else { ok = ok } if not is_subtype(ty_str(), ty_str()) { ok = false } else { ok = ok } if not is_subtype(ty_never(), ty_i64()) { ok = false } else { ok = ok } if not is_subtype(ty_never(), ty_any()) { ok = false } else { ok = ok } if not is_subtype(ty_i64(), ty_any()) { ok = false } else { ok = ok } if is_subtype(ty_i64(), ty_str()) { ok = false } else { ok = ok } if is_subtype(ty_str(), ty_i64()) { ok = false } else { ok = ok } if is_subtype(ty_bool(), ty_i64()) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_union" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let i = ty_i64() let s = ty_str() let u = ty_union(i, s) let mut ok = true if not is_subtype(i, u) { ok = false } else { ok = ok } if not is_subtype(s, u) { ok = false } else { ok = ok } if is_subtype(ty_bool(), u) { ok = false } else { ok = ok } if is_subtype(u, i) { ok = false } else { ok = ok } if not is_subtype(u, ty_union(u, ty_bool())) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_complement" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let i = ty_i64() let mut ok = true if ty_is_empty(ty_compl(i)) { ok = false } else { ok = ok } if ty_is_empty(ty_compl(ty_never())) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(i, ty_compl(i))) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(ty_str(), ty_compl(ty_str()))) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(ty_bool(), ty_compl(ty_bool()))) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_nullable" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let i = ty_i64() let n = ty_nil() let ni = ty_nullable(i) let mut ok = true if not is_subtype(i, ni) { ok = false } else { ok = ok } if not is_subtype(n, ni) { ok = false } else { ok = ok } if is_subtype(ty_str(), ni) { ok = false } else { ok = ok } if is_subtype(ni, i) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_identities" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let i = ty_i64() let mut ok = true let i_nev = ty_union(i, ty_never()) if not is_subtype(i_nev, i) { ok = false } else { ok = ok } if not is_subtype(i, i_nev) { ok = false } else { ok = ok } let i_any = ty_inter(i, ty_any()) if not is_subtype(i, i_any) { ok = false } else { ok = ok } if not is_subtype(i_any, i) { ok = false } else { ok = ok } if not ty_is_empty(ty_inter(i, ty_never())) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_equality" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let mut ok = true if not ty_eq(ty_i64(), ty_i64()) { ok = false } else { ok = ok } if not ty_eq(ty_never(), ty_never()) { ok = false } else { ok = ok } if ty_eq(ty_i64(), ty_str()) { ok = false } else { ok = ok } if ty_eq(ty_never(), ty_any()) { ok = false } else { ok = ok } if not ty_eq(ty_compl(ty_i64()), ty_compl(ty_i64())) { ok = false } else { ok = ok } if ty_eq(ty_compl(ty_i64()), ty_compl(ty_str())) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_nested" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let i = ty_i64() let s = ty_str() let b = ty_bool() let all = ty_union(ty_union(i, s), ty_union(b, ty_nil())) let mut ok = true if not is_subtype(i, all) { ok = false } else { ok = ok } if not is_subtype(s, all) { ok = false } else { ok = ok } if not is_subtype(b, all) { ok = false } else { ok = ok } let isect = ty_inter(ty_union(i, s), ty_union(i, b)) if not is_subtype(i, isect) { ok = false } else { ok = ok } if is_subtype(s, isect) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_transitivity" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let i = ty_i64() let ab = ty_union(i, ty_str()) let abc = ty_union(ab, ty_bool()) let mut ok = true if not is_subtype(i, ab) { ok = false } else { ok = ok } if not is_subtype(ab, abc) { ok = false } else { ok = ok } if not is_subtype(i, abc) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_union_commut" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let ab = ty_union(ty_i64(), ty_str()) let ba = ty_union(ty_str(), ty_i64()) let mut ok = true if not is_subtype(ab, ba) { ok = false } else { ok = ok } if not is_subtype(ba, ab) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
run_use "ty_de_morgan" "0" 'use "../compiler/lib.weft" use "../compiler/types.weft" fn main() -> i64 { let i = ty_i64() let s = ty_str() let not_u = ty_compl(ty_union(i, s)) let inter_n = ty_inter(ty_compl(i), ty_compl(s)) let mut ok = true if not is_subtype(not_u, inter_n) { ok = false } else { ok = ok } if not is_subtype(inter_n, not_u) { ok = false } else { ok = ok } if is_subtype(i, not_u) { ok = false } else { ok = ok } if not is_subtype(ty_bool(), not_u) { ok = false } else { ok = ok } if ok { 0 } else { 1 } }'
popd > /dev/null
# ═══════════════════════════════════════════════════════════════
# 24. TYPE ANNOTATION PARSING
# ═══════════════════════════════════════════════════════════════
# Primitive type annotations (existing syntax, now parsed)
run_test2 "typarse_i64" "42" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f(42) }'
run_test2 "typarse_str" "5" 'fn f(s: str) -> i64 { __str_len(s) } fn main() -> i64 { f("hello") }'
run_test2 "typarse_bool" "42" 'fn f(b: bool) -> i64 { if b { 42 } else { 0 } } fn main() -> i64 { f(true) }'
run_test2 "typarse_nil" "42" 'fn f(x: nil) -> i64 { 42 } fn main() -> i64 { f(0) }'
# Multi-param with types
run_test2 "typarse_multi" "42" 'fn f(a: i64, b: i64, c: i64) -> i64 { a + b + c } fn main() -> i64 { f(10, 20, 12) }'
# No type annotation (backwards compat)
run_test2 "typarse_notype" "42" 'fn f(x) -> i64 { 42 } fn main() -> i64 { f(0) }'
# Return type only
run_test2 "typarse_retonly" "42" 'fn f() -> i64 { 42 } fn main() -> i64 { f() }'
# No return type
run_test2 "typarse_noret" "42" 'fn f(x: i64) { x } fn main() -> i64 { f(42) }'
# Union type annotation
run_test2 "typarse_union" "42" 'fn f(x: i64 | str) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Nullable type annotation
run_test2 "typarse_nullable" "42" 'fn f(x: i64?) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Complement type annotation
run_test2 "typarse_compl" "42" 'fn f(x: ~nil) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Parenthesized type
run_test2 "typarse_parens" "42" 'fn f(x: (i64)) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Intersection type
run_test2 "typarse_inter" "42" 'fn f(x: i64 & any) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Nested union
run_test2 "typarse_nested_union" "42" 'fn f(x: i64 | str | bool) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Type annotation with function call
run_test2 "typarse_call" "120" 'fn fact(n: i64) -> i64 { if n <= 1 { 1 } else { n * fact(n - 1) } } fn main() -> i64 { fact(5) }'
# Multiple typed functions
run_test2 "typarse_multi_fn" "42" 'fn add(a: i64, b: i64) -> i64 { a + b } fn mul(a: i64, b: i64) -> i64 { a * b } fn main() -> i64 { add(mul(3, 7), mul(3, 7)) }'
# Type annotations with records
run_test2 "typarse_record" "42" 'type P { x: i64, y: i64 } fn sum(p: i64) -> i64 { p.x + p.y } fn main() -> i64 { let p = P { x: 30, y: 12 } sum(p) }'
# Type annotations with variants and match
run_test2 "typarse_variant" "42" 'type T { A(i64), B(i64) } fn extract(v: i64) -> i64 { match v { A(n) -> n B(n) -> n } } fn main() -> i64 { extract(A(42)) }'
# Parenthesized type annotations (was buggy — parse_type heap allocation issue)
run_test2 "typarse_paren_union" "42" 'fn f(x: (i64 | str)) -> i64 { 42 } fn main() -> i64 { f(1) }'
run_test2 "typarse_complex" "42" 'fn f(x: (i64 | str) & ~nil) -> i64 { 42 } fn main() -> i64 { f(1) }'
run_test2 "typarse_ret_paren" "42" 'fn f() -> (i64 | str) { 42 } fn main() -> i64 { f() }'
run_test2 "typarse_paren_inter" "42" 'fn f(x: (i64 & any)) -> i64 { 42 } fn main() -> i64 { f(1) }'
run_test2 "typarse_full_complex" "42" 'fn f(x: (i64 | str) & ~nil) -> (i64 | str) { 42 } fn main() -> i64 { f(1) }'
# Type names: never, any
run_test2 "typarse_never" "42" 'fn f(x: never) -> i64 { 42 } fn main() -> i64 { f(0) }'
run_test2 "typarse_any" "42" 'fn f(x: any) -> i64 { 42 } fn main() -> i64 { f(0) }'
# Mixed param types
run_test2 "typarse_mixed" "42" 'fn f(a: i64, b: str, c: bool) -> i64 { a } fn main() -> i64 { f(42, "hi", true) }'
# Deeply nested parens
run_test2 "typarse_deep_parens" "42" 'fn f(x: (((i64)))) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Multiple union members
run_test2 "typarse_tri_union" "42" 'fn f(x: i64 | str | bool) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Nullable return
run_test2 "typarse_nullable_ret" "42" 'fn f() -> i64? { 42 } fn main() -> i64 { f() }'
# ═══════════════════════════════════════════════════════════════
# 25. STRING ESCAPE SEQUENCES
# ═══════════════════════════════════════════════════════════════
run_test2 "esc_newline" "11" 'fn main() -> i64 { let s = "hello\nworld" __str_len(s) }'
run_test2 "esc_tab" "3" 'fn main() -> i64 { let s = "a\tb" __str_len(s) }'
run_test2 "esc_just_n" "1" 'fn main() -> i64 { let s = "\n" __str_len(s) }'
run_test2 "esc_just_t" "1" 'fn main() -> i64 { let s = "\t" __str_len(s) }'
run_test2 "esc_empty" "0" 'fn main() -> i64 { let s = "" __str_len(s) }'
run_test2 "esc_no_esc" "5" 'fn main() -> i64 { let s = "hello" __str_len(s) }'
run_test2 "esc_multi" "5" 'fn main() -> i64 { let s = "a\nb\tc" __str_len(s) }'
run_test2 "esc_null" "3" 'fn main() -> i64 { let s = "a\0b" __str_len(s) }'
run_test2 "esc_consecutive" "3" 'fn main() -> i64 { let s = "\n\n\n" __str_len(s) }'
run_test2 "esc_all_types" "5" 'fn main() -> i64 { let s = "\n\t\0\n\t" __str_len(s) }'
run_test2 "esc_unknown" "1" 'fn main() -> i64 { let s = "\q" __str_len(s) }'
run_test2 "esc_nested_parens" "42" 'fn main() -> i64 { let s = "he\nllo" if __str_len(s) == 6 { 42 } else { 0 } }'
run_test2 "esc_in_fn_arg" "1" 'fn slen(s: str) -> i64 { __str_len(s) } fn main() -> i64 { slen("\n") }'
# ═══════════════════════════════════════════════════════════════
# 26. TYPE CHECKER (standalone unit tests)
# ═══════════════════════════════════════════════════════════════
pushd tests > /dev/null
run_use "typeck_all" "0" "$(cat test_typeck.weft)"
run_use "sha256_nist" "0" "$(cat test_sha256.weft)"
popd > /dev/null
# ═══════════════════════════════════════════════════════════════
# 27. TYPE CHECKER INTEGRATION — error detection in compiled programs
# ═══════════════════════════════════════════════════════════════
# Programs that should compile cleanly (no type errors on stderr)
run_test_no_err() {
  local name="$1" expected="$2" input="$3"
  local errs=$(echo "$input" | /tmp/weft2 2>&1 >/tmp/t2)
  chmod +x /tmp/t2
  local got=$(/tmp/t2 2>/dev/null; echo $?)
  if [ "$got" = "$expected" ] && [ -z "$errs" ]; then
    PASS2=$((PASS2+1))
  else
    echo "  ✗ $name = $got (expected $expected), errors: $errs"
    FAIL2=$((FAIL2+1))
  fi
}
# Programs that SHOULD produce type errors on stderr
run_test_err() {
  local name="$1" pattern="$2" input="$3"
  local errs=$(echo "$input" | /tmp/weft2 2>&1 >/tmp/t2)
  if echo "$errs" | grep -q "$pattern"; then
    PASS2=$((PASS2+1))
  else
    echo "  ✗ $name: expected error '$pattern', got: $errs"
    FAIL2=$((FAIL2+1))
  fi
}
# Clean programs — no type errors
run_test_no_err "tc_int_arith" "42" 'fn main() -> i64 { 3 + 4 * 5 + 19 }'
run_test_no_err "tc_let_int" "42" 'fn main() -> i64 { let x = 20 x + 22 }'
run_test_no_err "tc_fn_call" "42" 'fn f(a: i64, b: i64) -> i64 { a + b } fn main() -> i64 { f(20, 22) }'
run_test_no_err "tc_if" "42" 'fn main() -> i64 { if true { 42 } else { 0 } }'
run_test_no_err "tc_while" "42" 'fn main() -> i64 { let mut x = 0 while x < 42 { x = x + 1 } x }'
run_test_no_err "tc_match" "42" 'fn main() -> i64 { match 1 { 1 -> 42 _ -> 0 } }'
run_test_no_err "tc_str" "5" 'fn main() -> i64 { let s = "hello" __str_len(s) }'
# Type errors — should report
run_test_err "tc_int_plus_str" "not i64" 'fn main() -> i64 { 42 + "hello" }'
run_test_err "tc_str_minus" "not i64" 'fn main() -> i64 { "hello" - 1 }'
run_test_err "tc_str_mul" "not i64" 'fn main() -> i64 { "a" * "b" }'
run_test_err "tc_let_str_add" "not i64" 'fn main() -> i64 { let x = "hello" x + 1 }'
run_test_err "tc_str_mod" "not i64" 'fn main() -> i64 { "a" % 2 }'
run_test_err "tc_str_div" "not i64" 'fn main() -> i64 { "a" / 2 }'
run_test_err "tc_nested_err" "not i64" 'fn main() -> i64 { (42 + "a") + 1 }'
run_test_err "tc_let_chain" "not i64" 'fn main() -> i64 { let x = "hi" let y = x + 1 y }'
# Clean: deeply nested arithmetic
run_test_no_err "tc_deep_arith" "42" 'fn main() -> i64 { 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 6 }'
# Clean: match with all int arms
run_test_no_err "tc_match_clean" "42" 'fn main() -> i64 { match 2 { 1 -> 10 2 -> 42 _ -> 0 } }'
# Clean: while with mutation
run_test_no_err "tc_while_mut" "42" 'fn main() -> i64 { let mut x = 0 while x < 42 { x = x + 1 } x }'
# Clean: function calls chain
run_test_no_err "tc_fn_chain" "42" 'fn a(x: i64) -> i64 { x + 1 } fn b(x: i64) -> i64 { a(x) * 2 } fn main() -> i64 { b(20) }'
# ═══════════════════════════════════════════════════════════════
# 28. TYPE ENFORCEMENT — annotations enforce type checking
# ═══════════════════════════════════════════════════════════════
# Clean: correctly typed params
run_test_no_err "te_i64_arith" "42" 'fn f(x: i64) -> i64 { x + 1 } fn main() -> i64 { f(41) }'
run_test_no_err "te_str_len" "5" 'fn f(s: str) -> i64 { __str_len(s) } fn main() -> i64 { f("hello") }'
# bool params: true/false should have type bool, passing to bool param should work
run_test_no_err "te_bool_if" "42" 'fn f(b: bool) -> i64 { if b { 42 } else { 0 } } fn main() -> i64 { f(true) }'
run_test_no_err "te_bool_false" "0" 'fn f(b: bool) -> i64 { if b { 1 } else { 0 } } fn main() -> i64 { f(false) }'
run_test_no_err "te_multi_typed" "42" 'fn f(a: i64, b: i64) -> i64 { a + b } fn main() -> i64 { f(20, 22) }'
run_test_no_err "te_mixed" "42" 'fn f(n: i64, s: str) -> i64 { n + __str_len(s) } fn main() -> i64 { f(37, "hello") }'
run_test_no_err "te_untyped" "42" 'fn f(x) -> i64 { 42 } fn main() -> i64 { f(0) }'
# Errors: typed params used incorrectly (all 5 arithmetic ops)
run_test_err "te_str_plus" "not i64" 'fn f(x: str) -> i64 { x + 1 } fn main() -> i64 { f("hi") }'
run_test_err "te_str_minus" "not i64" 'fn f(x: str) -> i64 { x - 1 } fn main() -> i64 { f("hi") }'
run_test_err "te_str_mul" "not i64" 'fn f(x: str) -> i64 { x * 2 } fn main() -> i64 { f("hi") }'
run_test_err "te_str_div" "not i64" 'fn f(x: str) -> i64 { x / 2 } fn main() -> i64 { f("hi") }'
run_test_err "te_str_mod" "not i64" 'fn f(x: str) -> i64 { x % 2 } fn main() -> i64 { f("hi") }'
run_test_err "te_bool_arith" "not i64" 'fn f(b: bool) -> i64 { b + 1 } fn main() -> i64 { f(true) }'
run_test_err "te_nil_arith" "not i64" 'fn f(x: nil) -> i64 { x + 1 } fn main() -> i64 { f(0) }'
# Bool synthesis: comparisons return bool, passing to bool param should work
run_test_no_err "te_cmp_bool" "42" 'fn check(b: bool) -> i64 { if b { 42 } else { 0 } } fn main() -> i64 { check(3 > 2) }'
# Bool synthesis: logical ops return bool
run_test_no_err "te_logic_bool" "42" 'fn check(b: bool) -> i64 { if b { 42 } else { 0 } } fn main() -> i64 { check(true and true) }'
# Bool synthesis: not returns bool
run_test_no_err "te_not_bool" "42" 'fn check(b: bool) -> i64 { if b { 42 } else { 0 } } fn main() -> i64 { check(not false) }'
# true used in arithmetic should error (bool is not i64)
run_test_err "te_true_arith" "not i64" 'fn main() -> i64 { true + 1 }'
# false used in arithmetic should error
run_test_err "te_false_arith" "not i64" 'fn main() -> i64 { false * 2 }'
# Comparison result used in arithmetic should error (bool not i64)
run_test_err "te_cmp_arith" "not i64" 'fn main() -> i64 { (3 > 2) + 1 }'
# ═══════════════════════════════════════════════════════════════
# 33. COMPLEX TYPE ANNOTATIONS — (i64 | str), ~nil, etc.
# ═══════════════════════════════════════════════════════════════
# These require parse_type to work in param/return positions
run_test_no_err "cty_paren_union" "42" 'fn f(x: (i64 | str)) -> i64 { 42 } fn main() -> i64 { f(1) }'
run_test_no_err "cty_inter" "42" 'fn f(x: (i64 & any)) -> i64 { 42 } fn main() -> i64 { f(1) }'
run_test_no_err "cty_compl" "42" 'fn f(x: ~nil) -> i64 { 42 } fn main() -> i64 { f(1) }'
run_test_no_err "cty_nullable" "42" 'fn f(x: i64?) -> i64 { 42 } fn main() -> i64 { f(1) }'
# fn f() -> (i64|str) returning i64 is fine, but main()->i64 calling f() is a mismatch
# because f() might return str. This correctly errors on main's return type.
run_test_no_err "cty_ret_union" "42" 'fn f() -> (i64 | str) { 42 } fn main() -> (i64 | str) { f() }'
run_test_no_err "cty_complex" "42" 'fn f(x: (i64 | str) & ~nil) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Enforcement with complex types
run_test_err "cty_str_to_i64only" "argument type mismatch" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f("hello") }'
# Verify ~ is lexed: ~nil should be a valid annotation (not just skipping ~)
run_test_no_err "cty_tilde_nil" "42" 'fn f(x: ~nil) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Verify | is lexed: union types should not create extra params
run_test_no_err "cty_union_one_param" "42" 'fn f(x: i64 | str) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Verify & is lexed
run_test_no_err "cty_amp_inter" "42" 'fn f(x: i64 & any) -> i64 { 42 } fn main() -> i64 { f(1) }'
# Verify ? is lexed
run_test_no_err "cty_question_nullable" "42" 'fn f(x: i64?) -> i64 { 42 } fn main() -> i64 { f(1) }'
# ═══════════════════════════════════════════════════════════════
# 34. LEXER TOKEN TESTS — verify special chars are tokenized
# ═══════════════════════════════════════════════════════════════
# These test that |, &, ~, ? don't silently corrupt parsing
# | in type shouldn't create extra params
run_test_no_err "lex_pipe_type" "42" 'fn f(a: i64 | str, b: i64) -> i64 { b } fn main() -> i64 { f(1, 42) }'
# ~ in type shouldn't be skipped
run_test_no_err "lex_tilde_type" "42" 'fn f(a: ~nil, b: i64) -> i64 { b } fn main() -> i64 { f(1, 42) }'
# ? in type shouldn't be skipped
run_test_no_err "lex_question_type" "42" 'fn f(a: i64?, b: i64) -> i64 { b } fn main() -> i64 { f(1, 42) }'
# & in type shouldn't be skipped
run_test_no_err "lex_amp_type" "42" 'fn f(a: i64 & any, b: i64) -> i64 { b } fn main() -> i64 { f(1, 42) }'
# Multiple type operators in one annotation
run_test_no_err "lex_multi_ops" "42" 'fn f(x: (i64 | str) & ~nil) -> i64 { 42 } fn main() -> i64 { f(1) }'
# ═══════════════════════════════════════════════════════════════
# 36. COMPLEX TYPE ENFORCEMENT — union/intersection types checked
# ═══════════════════════════════════════════════════════════════
# i64 subtype of i64|str: should pass
run_test_no_err "cte_i64_to_union" "42" 'fn f(x: i64 | str) -> i64 { 42 } fn main() -> i64 { f(42) }'
# str subtype of i64|str: should pass
run_test_no_err "cte_str_to_union" "42" 'fn f(x: i64 | str) -> i64 { 42 } fn main() -> i64 { f("hi") }'
# bool NOT subtype of i64|str: should error
run_test_err "cte_bool_to_union" "argument type mismatch" 'fn f(x: i64 | str) -> i64 { 42 } fn main() -> i64 { f(true) }'
# union return type: body i64 subtype of i64|str
run_test_no_err "cte_ret_union_ok" "42" 'fn f() -> i64 | str { 42 } fn main() -> i64 | str { f() }'
# i64|str NOT subtype of i64: return type mismatch
run_test_err "cte_ret_narrow" "return type mismatch" 'fn f() -> i64 | str { 42 } fn main() -> i64 { f() }'
# nullable: i64 subtype of i64?
run_test_no_err "cte_nullable_ok" "42" 'fn f(x: i64?) -> i64 { 42 } fn main() -> i64 { f(42) }'
# ═══════════════════════════════════════════════════════════════
# 35. EXPRESSION SEPARATION — newlines and semicolons
# ═══════════════════════════════════════════════════════════════
# Semicolons as explicit separator
run_test2 "sep_semi" "42" 'fn main() -> i64 { let x = 20; let y = 22; x + y }'
# Multiple semicolons
run_test2 "sep_multi_semi" "42" 'fn main() -> i64 { let x = 42;; x }'
# Newlines as separator (multiline function body)
run_test2 "sep_newline_let" "42" 'fn main() -> i64 {
  let x = 20
  let y = 22
  x + y
}'
# Newline continuation after operator
run_test2 "sep_continue_op" "42" 'fn main() -> i64 {
  20 +
  22
}'
# Newline continuation after comma
run_test2 "sep_continue_comma" "42" 'fn add(a: i64, b: i64) -> i64 { a + b }
fn main() -> i64 {
  add(20,
    22)
}'
# If/else across newlines
run_test2 "sep_if_else" "42" 'fn main() -> i64 {
  if true {
    42
  } else {
    0
  }
}'
# Match across newlines
run_test2 "sep_match_nl" "42" 'fn main() -> i64 {
  match 2 {
    1 -> 10
    2 -> 42
    _ -> 0
  }
}'
# While across newlines
run_test2 "sep_while_nl" "42" 'fn main() -> i64 {
  let mut x = 0
  while x < 42 {
    x = x + 1
  }
  x
}'
# Multiple functions with newlines
run_test2 "sep_multi_fn" "42" 'fn a() -> i64 {
  21
}
fn b() -> i64 {
  21
}
fn main() -> i64 {
  a() + b()
}'
# Nested blocks with newlines
run_test2 "sep_nested_block" "42" 'fn main() -> i64 {
  let x = {
    let a = 20
    let b = 22
    a + b
  }
  x
}'
# Match with guards across newlines
run_test2 "sep_guard_nl" "42" 'fn main() -> i64 {
  match 5 {
    n if n > 3 -> 42
    _ -> 0
  }
}'
run_test_err "te_let_str" "not i64" 'fn f(s: str) -> i64 { let x = s x + 1 } fn main() -> i64 { f("hi") }'
# Sad: multiple errors in one function
run_test_err "te_multi_err" "not i64" 'fn f(a: str, b: str) -> i64 { a + b } fn main() -> i64 { f("x", "y") }'
# Sad: error in nested expression
run_test_err "te_nested_err" "not i64" 'fn f(s: str) -> i64 { (s + 1) * 2 } fn main() -> i64 { f("hi") }'
# Sad: typed param in let chain
run_test_err "te_chain_err" "not i64" 'fn f(s: str) -> i64 { let a = s let b = a b + 1 } fn main() -> i64 { f("hi") }'
# Clean: function calling typed function
run_test_no_err "te_call_typed" "42" 'fn add1(x: i64) -> i64 { x + 1 } fn main() -> i64 { add1(41) }'
# Clean: let binding from typed param
run_test_no_err "te_let_typed" "42" 'fn f(x: i64) -> i64 { let y = x + 1 y } fn main() -> i64 { f(41) }'
# Clean: match on typed param
run_test_no_err "te_match_typed" "42" 'fn f(x: i64) -> i64 { match x { 41 -> 42 _ -> 0 } } fn main() -> i64 { f(41) }'
# Clean: while with typed counter
run_test_no_err "te_while_typed" "42" 'fn f(n: i64) -> i64 { let mut x = 0 while x < n { x = x + 1 } x } fn main() -> i64 { f(42) }'
# Clean: no annotation backward compat
run_test_err "te_no_annot" "not i64" 'fn f(x) -> i64 { x + 1 } fn main() -> i64 { f(41) }'
# Clean: str param not used in arithmetic (just passed through)
run_test_no_err "te_str_pass" "5" 'fn f(s: str) -> i64 { __str_len(s) } fn main() -> i64 { f("hello") }'
# Adversarial: many typed params
run_test_no_err "te_many_params" "28" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64, h: i64) -> i64 { a + b + c + d + e + g + h } fn main() -> i64 { f(1, 2, 3, 4, 5, 6, 7) }'
# Adversarial: typed param shadowed by let
run_test_no_err "te_shadow" "42" 'fn f(x: str) -> i64 { let x = 42 x } fn main() -> i64 { f("hi") }'
# Property: type annotation doesn't change runtime behavior
run_test_err "te_runtime_same" "return type" 'fn typed(x: i64) -> i64 { x } fn untyped(x) -> i64 { x } fn main() -> i64 { typed(21) + untyped(21) }'
# ═══════════════════════════════════════════════════════════════
# 29. CODE SIGNING — binaries run without codesign -s -
# ═══════════════════════════════════════════════════════════════
# All test binaries already run without codesign (test harness doesn't call it).
# These explicit tests verify specific code-signing properties.
# Small program
run_test2 "cs_small" "42" 'fn main() -> i64 { 42 }'
# Larger program (more code = more hash pages)
run_test2 "cs_large" "120" 'fn factorial(n: i64) -> i64 { if n <= 1 { 1 } else { n * factorial(n - 1) } } fn add(a: i64, b: i64) -> i64 { a + b } fn sub(a: i64, b: i64) -> i64 { a - b } fn mul(a: i64, b: i64) -> i64 { a * b } fn main() -> i64 { factorial(5) }'
# Program with string data (different binary content pattern)
run_test2 "cs_strings" "11" 'fn main() -> i64 { let a = "hello" let b = "world" __str_len(a) + __str_len(b) + 1 }'
# ═══════════════════════════════════════════════════════════════
# 30. RETURN TYPE CHECKING
# ═══════════════════════════════════════════════════════════════
# Clean: return type matches body
run_test_no_err "rt_i64_ok" "42" 'fn f() -> i64 { 42 } fn main() -> i64 { f() }'
run_test_no_err "rt_arith_ok" "42" 'fn f(x: i64) -> i64 { x + 1 } fn main() -> i64 { f(41) }'
run_test_no_err "rt_if_ok" "42" 'fn f(b: i64) -> i64 { if b > 0 { 42 } else { 0 } } fn main() -> i64 { f(1) }'
# Error: body type doesn't match declared return type
run_test_err "rt_str_body" "return type mismatch" 'fn f() -> i64 { "hello" } fn main() -> i64 { f() }'
run_test_err "rt_str_ret" "return type mismatch" 'fn f(s: str) -> i64 { s } fn main() -> i64 { f("hi") }'
# ═══════════════════════════════════════════════════════════════
# 31. CALL ARGUMENT TYPE CHECKING
# ═══════════════════════════════════════════════════════════════
# Clean: argument types match parameter types
run_test_no_err "ca_i64_ok" "42" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f(42) }'
run_test_no_err "ca_str_ok" "5" 'fn f(s: str) -> i64 { __str_len(s) } fn main() -> i64 { f("hello") }'
run_test_no_err "ca_multi_ok" "42" 'fn f(a: i64, b: i64) -> i64 { a + b } fn main() -> i64 { f(20, 22) }'
run_test_no_err "ca_untyped_ok" "42" 'fn f(x) -> i64 { 42 } fn main() -> i64 { f("anything") }'
# Error: argument type doesn't match parameter type
run_test_err "ca_str_to_i64" "argument type mismatch" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f("hello") }'
run_test_err "ca_i64_to_str" "argument type mismatch" 'fn f(s: str) -> i64 { __str_len(s) } fn main() -> i64 { f(42) }'
# bool argument to i64 param: true is bool, i64 expected — should error
run_test_err "ca_bool_to_i64" "argument type mismatch" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f(true) }'
# bool argument to bool param: should work
run_test_no_err "ca_bool_to_bool" "42" 'fn f(b: bool) -> i64 { if b { 42 } else { 0 } } fn main() -> i64 { f(true) }'
run_test_err "ca_multi_mismatch" "argument type mismatch" 'fn f(a: i64, b: str) -> i64 { a } fn main() -> i64 { f(1, 2) }'
# Adversarial: chain of calls with type mismatch
run_test_err "ca_chain_err" "argument type mismatch" 'fn g(x: i64) -> i64 { x } fn f(s: str) -> i64 { g(s) } fn main() -> i64 { f("hi") }'
# ═══════════════════════════════════════════════════════════════
# 32. MATCH TYPE NARROWING
# ═══════════════════════════════════════════════════════════════
# Clean: binding pattern gets scrutinee type
run_test_no_err "mn_bind_i64" "42" 'fn f(x: i64) -> i64 { match x { n -> n + 1 } } fn main() -> i64 { f(41) }'
# Error: scrutinee is str, binding used in arithmetic
run_test_err "mn_bind_str" "not i64" 'fn f(s: str) -> i64 { match s { n -> n + 1 } } fn main() -> i64 { f("hi") }'
# Clean: match with multiple arms, all consistent types
run_test_no_err "mn_multi_ok" "42" 'fn f(x: i64) -> i64 { match x { 1 -> 10 2 -> 42 _ -> 0 } } fn main() -> i64 { f(2) }'
# Clean: match binding in guard
run_test_no_err "mn_guard_ok" "42" 'fn f(x: i64) -> i64 { match x { n if n > 40 -> n _ -> 0 } } fn main() -> i64 { f(42) }'
# Clean: match union result (if branches have diff types)
run_test_no_err "mn_wildcard" "42" 'fn f(x: i64) -> i64 { match x { _ -> 42 } } fn main() -> i64 { f(0) }'
# Sad: both operands are str (not just one)
run_test_err "te_str_str_add" "not i64" 'fn f(a: str, b: str) -> i64 { a + b } fn main() -> i64 { f("x", "y") }'
# Sad: bool used as arithmetic operand (not comparison)
run_test_err "te_bool_mul" "not i64" 'fn f(b: bool) -> i64 { b * 2 } fn main() -> i64 { f(true) }'
# Sad: nil in subtraction
run_test_err "te_nil_sub" "not i64" 'fn f(x: nil) -> i64 { x - 1 } fn main() -> i64 { f(0) }'
# ═══════════════════════════════════════════════════════════════
# 28. TECH DEBT FIX 1 — undefined variable detection
# ═══════════════════════════════════════════════════════════════
# Happy path: defined variables still work in all contexts
run_test_no_err "td_undef_let_ok" "42" 'fn main() -> i64 { let x = 42 x }'
run_test_no_err "td_undef_mut_ok" "10" 'fn main() -> i64 { let mut x = 5 x = 10 x }'
run_test_no_err "td_undef_param_ok" "42" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f(42) }'
run_test_no_err "td_undef_nested_ok" "42" 'fn main() -> i64 { let x = 20 let y = 22 x + y }'
run_test_no_err "td_undef_shadow_ok" "42" 'fn main() -> i64 { let x = 1 let x = 42 x }'
run_test_no_err "td_undef_match_ok" "42" 'fn main() -> i64 { match 42 { x -> x } }'
run_test_no_err "td_undef_mut_while" "10" 'fn main() -> i64 { let mut i = 0 while i < 10 { i = i + 1 } i }'
# Sad path: assigning to undefined variable produces error
run_test_err "td_undef_assign" "undefined" 'fn main() -> i64 { let mut x = 5 y = 10 x }'
# Sad path: reading undefined variable produces error
run_test_err "td_undef_read" "undefined" 'fn main() -> i64 { y }'
# Sad path: undefined in expression context
run_test_err "td_undef_in_expr" "undefined" 'fn main() -> i64 { 1 + z }'
# Sad path: undefined in function call arg
run_test_err "td_undef_in_call" "undefined" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f(w) }'
# Sad path: undefined in if condition
run_test_err "td_undef_in_cond" "undefined" 'fn main() -> i64 { if q == 1 { 1 } else { 0 } }'
# ═══════════════════════════════════════════════════════════════
# 29. TECH DEBT FIX 2 — record field order by declaration
# ═══════════════════════════════════════════════════════════════
# Happy: fields in declaration order (regression — must still work)
run_test2 "td_forder_decl" "42" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { x: 30, y: 12 } p.x + p.y }'
# Happy: 1 field (trivially correct)
run_test2 "td_forder_1f" "42" 'type W { v: i64 } fn main() -> i64 { let w = W { v: 42 } w.v }'
# Core test: 2 fields reversed — access first declared field
run_test2 "td_forder_rev2_x" "30" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { y: 12, x: 30 } p.x }'
# Core test: 2 fields reversed — access second declared field
run_test2 "td_forder_rev2_y" "12" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { y: 12, x: 30 } p.y }'
# Core test: 2 fields reversed — sum (both correct)
run_test2 "td_forder_rev2_sum" "42" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { y: 12, x: 30 } p.x + p.y }'
# 3 fields fully reversed — access each individually
run_test2 "td_forder_rev3_a" "10" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { c: 30, b: 20, a: 10 } r.a }'
run_test2 "td_forder_rev3_b" "20" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { c: 30, b: 20, a: 10 } r.b }'
run_test2 "td_forder_rev3_c" "30" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { c: 30, b: 20, a: 10 } r.c }'
# 3 fields scrambled (not just reversed) — c,a,b order
run_test2 "td_forder_scramble" "60" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { c: 30, a: 10, b: 20 } r.a + r.b + r.c }'
# 4 fields reversed — each field individually
run_test2 "td_forder_4f_a" "10" 'type Q { a: i64, b: i64, c: i64, d: i64 } fn main() -> i64 { let q = Q { d: 40, c: 30, b: 20, a: 10 } q.a }'
run_test2 "td_forder_4f_d" "40" 'type Q { a: i64, b: i64, c: i64, d: i64 } fn main() -> i64 { let q = Q { d: 40, c: 30, b: 20, a: 10 } q.d }'
# Reordered record passed to function
run_test2 "td_forder_fn" "42" 'type P { x: i64, y: i64 } fn getx(p: i64) -> i64 { p.x } fn main() -> i64 { let p = P { y: 12, x: 42 } getx(p) }'
run_test2 "td_forder_fn_y" "12" 'type P { x: i64, y: i64 } fn gety(p: i64) -> i64 { p.y } fn main() -> i64 { let p = P { y: 12, x: 42 } gety(p) }'
# Reordered record in if/else
run_test2 "td_forder_if" "42" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = if true { P { y: 12, x: 42 } } else { P { x: 0, y: 0 } } p.x }'
# Multiple reordered records of different types
run_test2 "td_forder_multi_type" "32" 'type A { x: i64, y: i64 } type B { m: i64, n: i64 } fn main() -> i64 { let a = A { y: 2, x: 10 } let b = B { n: 22, m: 10 } a.x + b.n }'
# Property: field sum invariant — same sum regardless of construction order
run_test2 "td_forder_prop_sum" "60" 'type R { a: i64, b: i64, c: i64 } fn main() -> i64 { let r = R { c: 30, a: 10, b: 20 } r.a + r.b + r.c }'
# Adversarial: reordered record with computed field values
run_test2 "td_forder_computed" "42" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { y: 2 * 3, x: 6 * 7 } p.x }'
# Wicked: reorder + field access in match
run_test2 "td_forder_match" "42" 'type P { x: i64, y: i64 } fn main() -> i64 { let p = P { y: 12, x: 42 } match 1 { _ -> p.x } }'
# ═══════════════════════════════════════════════════════════════
# 30. TECH DEBT FIX 3 — param count limit (>8 = error)
# ═══════════════════════════════════════════════════════════════
# Happy: 1-8 params all work (regressions)
run_test_no_err "td_params_1" "42" 'fn f(a: i64) -> i64 { a } fn main() -> i64 { f(42) }'
run_test_no_err "td_params_4" "100" 'fn f(a: i64, b: i64, c: i64, d: i64) -> i64 { a + b + c + d } fn main() -> i64 { f(10, 20, 30, 40) }'
run_test_no_err "td_params_7" "28" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64, h: i64) -> i64 { a + b + c + d + e + g + h } fn main() -> i64 { f(1, 2, 3, 4, 5, 6, 7) }'
run_test_no_err "td_params_8" "36" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64, h: i64, i: i64) -> i64 { a + b + c + d + e + g + h + i } fn main() -> i64 { f(1, 2, 3, 4, 5, 6, 7, 8) }'
# Sad: 9 params should produce error
run_test_err "td_params_9" "more than 8" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64, h: i64, i: i64, j: i64) -> i64 { a } fn main() -> i64 { f(1,2,3,4,5,6,7,8,9) }'
# Sad: 10 params should also error
run_test_err "td_params_10" "more than 8" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64, h: i64, i: i64, j: i64, k: i64) -> i64 { a } fn main() -> i64 { f(1,2,3,4,5,6,7,8,9,10) }'
# ═══════════════════════════════════════════════════════════════
# 31. TECH DEBT FIX 4 — non-exhaustive match trap
# ═══════════════════════════════════════════════════════════════
# Happy: exhaustive matches still work
run_test2 "td_match_wild" "42" 'fn main() -> i64 { match 5 { _ -> 42 } }'
run_test2 "td_match_bind" "42" 'fn main() -> i64 { match 42 { x -> x } }'
run_test2 "td_match_int_wild" "42" 'fn main() -> i64 { match 5 { 1 -> 1 _ -> 42 } }'
run_test2 "td_match_ctor_wild" "42" 'type T { A(i64), B(i64) } fn main() -> i64 { match A(42) { A(v) -> v B(v) -> v } }'
run_test2 "td_match_all_ints" "42" 'fn main() -> i64 { match 2 { 1 -> 10 2 -> 42 _ -> 99 } }'
# Sad: non-exhaustive int match — scrutinee doesn't match any arm
run_test_crash "td_match_nonexh_int" 'fn main() -> i64 { match 99 { 1 -> 42 } }'
# Sad: non-exhaustive with multiple int arms
run_test_crash "td_match_nonexh_multi" 'fn main() -> i64 { match 5 { 1 -> 10 2 -> 20 3 -> 30 } }'
# Sad: non-exhaustive constructor match
run_test_crash "td_match_nonexh_ctor" 'type T { A(i64), B(i64) } fn main() -> i64 { let x = B(42) match x { A(v) -> v } }'
# Happy: exhaustive via wildcard (must not trap)
run_test2 "td_match_exh_wild" "42" 'fn main() -> i64 { match 99 { 1 -> 10 _ -> 42 } }'
# Happy: exhaustive via binding (must not trap)
run_test2 "td_match_exh_bind" "42" 'fn main() -> i64 { match 42 { 1 -> 10 n -> n } }'
# Happy: single wildcard arm (trivially exhaustive)
run_test2 "td_match_exh_single" "42" 'fn main() -> i64 { match 99 { _ -> 42 } }'
# ═══════════════════════════════════════════════════════════════
# 32. TECH DEBT ROUND 2 — crash prevention
# ═══════════════════════════════════════════════════════════════
# Bounds: token buffer overflow (>32K tokens should error, not corrupt)
# We can't easily generate 32K tokens in a one-liner, so test buffer bounds
# indirectly via large programs that still fit.
# Happy: programs near limits still work
run_test2 "td_buf_many_lets" "100" 'fn main() -> i64 { let a0 = 0 let a1 = 1 let a2 = 2 let a3 = 3 let a4 = 4 let a5 = 5 let a6 = 6 let a7 = 7 let a8 = 8 let a9 = 9 let b0 = 10 let b1 = 11 let b2 = 12 let b3 = 13 let b4 = 14 let b5 = 15 let b6 = 16 let b7 = 17 let b8 = 18 let b9 = 19 a0 + a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + b0 + b1 + b2 + b3 + b4 + b5 + b6 + b7 + b8 + b9 - 90 }'
# Bounds: type table with multiple types
run_test2 "td_buf_multi_types" "42" 'type A { x: i64 } type B { y: i64 } type C { z: i64 } fn main() -> i64 { let a = A { x: 10 } let b = B { y: 12 } let c = C { z: 20 } a.x + b.y + c.z }'
# Bounds: nlist with many function args
run_test2 "td_buf_many_args" "28" 'fn f(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64, h: i64) -> i64 { a + b + c + d + e + g + h } fn main() -> i64 { f(1, 2, 3, 4, 5, 6, 7) }'
# Bounds: deeply nested if/else
run_test2 "td_buf_nested_if" "42" 'fn main() -> i64 { if 1 == 1 { if 2 == 2 { if 3 == 3 { if 4 == 4 { if 5 == 5 { 42 } else { 0 } } else { 0 } } else { 0 } } else { 0 } } else { 0 } }'
# ═══════════════════════════════════════════════════════════════
# 33. TECH DEBT ROUND 3 — type defaults (any instead of i64)
# ═══════════════════════════════════════════════════════════════
# Happy: annotated params still type-check correctly
run_test_no_err "td_tdef_annotated" "42" 'fn f(x: i64) -> i64 { x + 1 } fn main() -> i64 { f(41) }'
run_test_no_err "td_tdef_str_ann" "5" 'fn f(s: str) -> i64 { __str_len(s) } fn main() -> i64 { f("hello") }'
run_test_no_err "td_tdef_multi_ann" "42" 'fn f(a: i64, b: i64) -> i64 { a + b } fn main() -> i64 { f(20, 22) }'
# Happy: annotated return type still works
run_test_no_err "td_tdef_ret_ann" "42" 'fn f() -> i64 { 42 } fn main() -> i64 { f() }'
# Happy: no annotation still compiles (backwards compat — any type allows anything)
run_test2 "td_tdef_noann_ok" "42" 'fn f(x) { x } fn main() -> i64 { f(42) }'
run_test2 "td_tdef_noret_ok" "42" 'fn f(x: i64) { x } fn main() -> i64 { f(42) }'
# Sad: unannotated param used in arithmetic should now warn (any is not subtype of i64)
run_test_err "td_tdef_noann_arith" "not i64" 'fn f(x) -> i64 { x + 1 } fn main() -> i64 { f(41) }'
# Sad: unannotated param in comparison with i64
run_test_err "td_tdef_noann_cmp" "not i64" 'fn f(x) -> i64 { x * 2 } fn main() -> i64 { f(21) }'
# ═══════════════════════════════════════════════════════════════
# 34. TECH DEBT ROUND 4 — } continuation token fix
# ═══════════════════════════════════════════════════════════════
# Happy: } else still works (same line)
run_test2 "td_cont_else_same" "1" 'fn main() -> i64 { if true { 1 } else { 0 } }'
# Happy: } else works (different line — this is the critical case)
run_test2 "td_cont_else_nl" "1" "$(printf 'fn main() -> i64 {\n  if true { 1 }\n  else { 0 }\n}')"
# Happy: } followed by function on next line
run_test2 "td_cont_fn_nl" "42" "$(printf 'fn f() -> i64 { 42 }\nfn main() -> i64 { f() }')"
# Happy: nested if/else across lines
run_test2 "td_cont_nested_else" "3" "$(printf 'fn main() -> i64 {\n  if false { 1 }\n  else {\n    if false { 2 }\n    else { 3 }\n  }\n}')"
# Happy: match with arms on separate lines
run_test2 "td_cont_match" "42" "$(printf 'fn main() -> i64 {\n  match 2 {\n    1 -> 10\n    2 -> 42\n    _ -> 0\n  }\n}')"
# ═══════════════════════════════════════════════════════════════
# 35. SOURCE SPANS ON ERROR MESSAGES
# ═══════════════════════════════════════════════════════════════
# Undefined variable errors include line:col
run_test_err "td_span_undef" "line 1, col" 'fn main() -> i64 { y }'
# Type errors include line:col
run_test_err "td_span_arith" "line 1, col" 'fn f(s: str) -> i64 { s + 1 } fn main() -> i64 { f("x") }'
# Return type mismatch includes line:col
run_test_err "td_span_ret" "line 1, col" 'fn f() -> i64 { "hello" } fn main() -> i64 { f() }'
# Arg type mismatch includes line:col
run_test_err "td_span_arg" "line 1, col" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f("hi") }'
# Multi-line: span reports correct line number
run_test_err "td_span_line2" "line 2" "$(printf 'fn main() -> i64 {\n  y\n}')"
# ═══════════════════════════════════════════════════════════════
# 36. PARSER ERROR RECOVERY
# ═══════════════════════════════════════════════════════════════
# Recovery: malformed fn with ( but no matching ) — syncs to next fn
run_test_err "td_recovery_bad_paren" "expected" 'fn bad( fn main() -> i64 { 42 }'
# Recovery: fn without ( — syncs to next fn
run_test_err "td_recovery_no_paren" "expected" 'fn broken fn main() -> i64 { 42 }'
# Recovery: program after bad fn produces correct output
run_test2 "td_recovery_runs" "42" 'fn bad( fn main() -> i64 { 42 }'
run_test2 "td_recovery_runs2" "42" 'fn broken fn main() -> i64 { 42 }'
# Valid programs still work correctly
run_test_no_err "td_recovery_valid" "42" 'fn main() -> i64 { 42 }'
# ═══════════════════════════════════════════════════════════════
# 37. RETURN STATEMENT — comprehensive
# ═══════════════════════════════════════════════════════════════
# --- Happy path ---
run_test2 "ret_basic" "42" 'fn f() -> i64 { return 42 } fn main() -> i64 { f() }'
run_test2 "ret_zero" "0" 'fn f() -> i64 { return 0 } fn main() -> i64 { f() }'
run_test2 "ret_1" "1" 'fn f() -> i64 { return 1 } fn main() -> i64 { f() }'
run_test2 "ret_255" "255" 'fn f() -> i64 { return 255 } fn main() -> i64 { f() }'
# --- Early return: if branch taken vs not taken ---
run_test2 "ret_early_taken" "99" 'fn f(x: i64) -> i64 { if x > 10 { return 99 } x + 1 } fn main() -> i64 { f(20) }'
run_test2 "ret_early_not" "6" 'fn f(x: i64) -> i64 { if x > 10 { return 99 } x + 1 } fn main() -> i64 { f(5) }'
# --- Multiple return points ---
run_test2 "ret_multi_first" "0" 'fn classify(n: i64) -> i64 { if n < 0 { return 0 } if n == 0 { return 1 } 2 } fn main() -> i64 { classify(0 - 5) }'
run_test2 "ret_multi_second" "1" 'fn classify(n: i64) -> i64 { if n < 0 { return 0 } if n == 0 { return 1 } 2 } fn main() -> i64 { classify(0) }'
run_test2 "ret_multi_fallthru" "2" 'fn classify(n: i64) -> i64 { if n < 0 { return 0 } if n == 0 { return 1 } 2 } fn main() -> i64 { classify(5) }'
# --- Return in recursive function ---
run_test2 "ret_recursive" "120" 'fn fact(n: i64) -> i64 { if n <= 1 { return 1 } n * fact(n - 1) } fn main() -> i64 { fact(5) }'
run_test2 "ret_recursive_base" "1" 'fn fact(n: i64) -> i64 { if n <= 1 { return 1 } n * fact(n - 1) } fn main() -> i64 { fact(1) }'
# --- Return inside while loop ---
run_test2 "ret_in_loop" "42" 'fn find(t: i64) -> i64 { let mut i = 0 while i < 100 { if i == t { return i } i = i + 1 } 0 - 1 } fn main() -> i64 { find(42) }'
run_test2 "ret_in_loop_miss" "255" 'fn find(t: i64) -> i64 { let mut i = 0 while i < 100 { if i == t { return i } i = i + 1 } 0 - 1 } fn main() -> i64 { find(200) }'
# --- Return inside match arm ---
run_test2 "ret_in_match" "42" 'fn f(x: i64) -> i64 { match x { 1 -> { return 42 } _ -> 0 } } fn main() -> i64 { f(1) }'
run_test2 "ret_in_match_fall" "0" 'fn f(x: i64) -> i64 { match x { 1 -> { return 42 } _ -> 0 } } fn main() -> i64 { f(2) }'
# --- Return inside match inside while ---
run_test2 "ret_match_in_loop" "42" 'fn f() -> i64 { let mut i = 0 while i < 100 { match i { 42 -> { return i } _ -> { i = i + 1 } } } 0 } fn main() -> i64 { f() }'
# --- Return with expression (not just literal) ---
run_test2 "ret_expr" "42" 'fn f(a: i64, b: i64) -> i64 { return a * b } fn main() -> i64 { f(6, 7) }'
run_test2 "ret_call" "42" 'fn g() -> i64 { 42 } fn f() -> i64 { return g() } fn main() -> i64 { f() }'
# --- Return from deep nesting ---
run_test2 "ret_deep" "42" 'fn f(x: i64) -> i64 { if x > 0 { if x > 10 { if x > 20 { return 42 } else { return 0 } } else { return 1 } } else { return 2 } } fn main() -> i64 { f(30) }'
# --- Dead code after return (must not affect result) ---
run_test2 "ret_dead_code" "42" 'fn f() -> i64 { return 42 let x = 99 x } fn main() -> i64 { f() }'
# --- Property: return preserves value across call depth ---
run_test2 "ret_prop_depth" "42" 'fn a() -> i64 { return b() } fn b() -> i64 { return c() } fn c() -> i64 { return 42 } fn main() -> i64 { a() }'
# ═══════════════════════════════════════════════════════════════
# 38. BREAK AND CONTINUE — comprehensive
# ═══════════════════════════════════════════════════════════════
# --- Break: basic ---
run_test2 "brk_basic" "42" 'fn main() -> i64 { let mut i = 0 while i < 100 { if i == 42 { break } i = i + 1 } i }'
run_test2 "brk_first" "0" 'fn main() -> i64 { let mut i = 0 while i < 10 { break i = i + 1 } i }'
run_test2 "brk_last" "100" 'fn main() -> i64 { let mut i = 0 while i < 100 { i = i + 1 if i == 100 { break } } i }'
# --- Break: in nested if ---
run_test2 "brk_nested_if" "5" 'fn main() -> i64 { let mut i = 0 while i < 100 { i = i + 1 if i > 3 { if i == 5 { break } } else { 0 } } i }'
# --- Break: in match arm ---
run_test2 "brk_in_match" "42" 'fn main() -> i64 { let mut i = 0 while i < 100 { match i { 42 -> break _ -> { i = i + 1 } } } i }'
# --- Break: inner loop only (outer continues) ---
run_test2 "brk_inner_only" "10" 'fn main() -> i64 { let mut total = 0 let mut i = 0 while i < 5 { let mut j = 0 while j < 10 { if j == 2 { break } j = j + 1 total = total + 1 } i = i + 1 } total }'
# --- Break: outer loop unaffected by inner break ---
run_test2 "brk_outer_intact" "5" 'fn main() -> i64 { let mut i = 0 while i < 5 { let mut j = 0 while j < 10 { break } i = i + 1 } i }'
# --- Break: multiple breaks in same loop (different conditions) ---
run_test2 "brk_multi_cond" "3" 'fn main() -> i64 { let mut i = 0 while i < 100 { if i == 3 { break } if i == 50 { break } i = i + 1 } i }'
# --- Continue: basic ---
run_test2 "cont_basic" "9" 'fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 10 { i = i + 1 if i == 5 { continue } s = s + 1 } s }'
# --- Continue: skip multiple values ---
run_test2 "cont_skip_multi" "7" 'fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 10 { i = i + 1 if i == 3 { continue } if i == 5 { continue } if i == 7 { continue } s = s + 1 } s }'
# --- Continue: skip even numbers (sum odd only) ---
run_test2 "cont_sum_even" "30" 'fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 10 { i = i + 1 if i - i / 2 * 2 != 0 { continue } s = s + i } s }'
# --- Continue: inner loop only ---
run_test2 "cont_inner" "45" 'fn main() -> i64 { let mut total = 0 let mut i = 0 while i < 5 { let mut j = 0 while j < 10 { j = j + 1 if j == 3 { continue } total = total + 1 } i = i + 1 } total }'
# --- Continue: all iterations skipped (loop still terminates) ---
run_test2 "cont_all_skip" "0" 'fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 5 { i = i + 1 continue s = s + 1 } s }'
# --- Break + continue in same loop ---
run_test2 "brk_cont_combo" "8" 'fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 20 { i = i + 1 if i == 10 { break } if i == 5 { continue } s = s + 1 } s }'
# --- Break + continue: continue then break same iteration ---
run_test2 "cont_then_brk" "42" 'fn main() -> i64 { let mut i = 0 while i < 100 { i = i + 1 if i < 42 { continue } break } i }'
# --- Nested break: inner break, outer continue ---
run_test2 "brk_inner_cont_outer" "8" 'fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 5 { i = i + 1 if i == 3 { continue } let mut j = 0 while j < 10 { if j == 2 { break } j = j + 1 s = s + 1 } } s }'
# --- Deeply nested: break inside if inside match inside while ---
run_test2 "brk_deep_nest" "42" 'fn main() -> i64 { let mut i = 0 while i < 100 { match 1 { 1 -> { if i == 42 { break } else { 0 } } _ -> { 0 } } i = i + 1 } i }'
# --- Break in function called from loop (break is local to innermost while) ---
run_test2 "brk_in_fn_loop" "10" 'fn inner() -> i64 { let mut j = 0 while j < 10 { if j == 5 { break } j = j + 1 } j } fn main() -> i64 { let mut s = 0 let mut i = 0 while i < 2 { s = s + inner() i = i + 1 } s }'
# --- Sad: break outside loop ---
run_test_err "brk_outside" "break outside" 'fn main() -> i64 { break 42 }'
# --- Sad: continue outside loop ---
run_test_err "cont_outside" "continue outside" 'fn main() -> i64 { continue 42 }'
# --- Sad: break in function body (not in loop) ---
run_test_err "brk_in_fn" "break outside" 'fn f() -> i64 { break } fn main() -> i64 { let mut i = 0 while i < 1 { f() i = i + 1 } i }'
# --- Property: break preserves mut state ---
run_test2 "brk_prop_mut" "42" 'fn main() -> i64 { let mut x = 0 let mut i = 0 while i < 100 { x = i i = i + 1 if i > 42 { break } } x }'
# --- Property: continue doesn't skip loop counter update (when before it) ---
run_test2 "cont_prop_terminates" "10" 'fn main() -> i64 { let mut i = 0 while i < 10 { i = i + 1 if true { continue } } i }'
# ═══════════════════════════════════════════════════════════════
# 39. EFFECT TYPE ANNOTATIONS — comprehensive
# ═══════════════════════════════════════════════════════════════
# --- Happy: basic effect annotation parsing ---
run_test2 "eff_plain" "42" 'fn main() -> i64 { 42 }'
run_test2 "eff_io" "42" 'fn f() -[IO]> i64 { 42 } fn main() -> i64 { f() }'
run_test2 "eff_multi" "42" 'fn f() -[IO, Log]> i64 { 42 } fn main() -> i64 { f() }'
run_test2 "eff_three" "42" 'fn f() -[IO, Log, Net]> i64 { 42 } fn main() -> i64 { f() }'
run_test2 "eff_pure_arrow" "42" 'fn f() -> i64 { 42 } fn main() -> i64 { f() }'
# --- Happy: effect subtyping (caller has >= callee effects) ---
run_test_no_err "eff_same" "42" 'fn g() -[IO]> i64 { 42 } fn f() -[IO]> i64 { g() } fn main() { f() }'
run_test_no_err "eff_superset" "42" 'fn g() -[IO]> i64 { 42 } fn f() -[IO, Log]> i64 { g() } fn main() { f() }'
run_test_no_err "eff_superset3" "42" 'fn g() -[IO]> i64 { 42 } fn f() -[IO, Log, Net]> i64 { g() } fn main() { f() }'
run_test_no_err "eff_pure_pure" "42" 'fn g() -> i64 { 42 } fn f() -> i64 { g() } fn main() { f() }'
# --- Happy: multiple calls with different effects (all within caller's set) ---
run_test_no_err "eff_multi_call" "42" 'fn a() -[IO]> i64 { 21 } fn b() -[Log]> i64 { 21 } fn f() -[IO, Log]> i64 { a() + b() } fn main() { f() }'
# --- Happy: unannotated (backward compat, no effect checking) ---
run_test2 "eff_unann_ok" "42" 'fn g() -[IO]> i64 { 42 } fn main() -> i64 { g() }'
run_test2 "eff_unann_chain" "42" 'fn h() -[IO]> i64 { 42 } fn g() -> i64 { h() } fn main() -> i64 { g() }'
# --- Happy: chain of effectful functions ---
run_test_no_err "eff_chain" "42" 'fn c() -[IO]> i64 { 42 } fn b() -[IO]> i64 { c() } fn a() -[IO]> i64 { b() } fn main() { a() }'
# --- Happy: effectful function in different positions ---
run_test_no_err "eff_in_if" "42" 'fn g() -[IO]> i64 { 42 } fn f() -[IO]> i64 { if true { g() } else { 0 } } fn main() { f() }'
run_test_no_err "eff_in_let" "42" 'fn g() -[IO]> i64 { 42 } fn f() -[IO]> i64 { let x = g() x } fn main() { f() }'
run_test_no_err "eff_in_while" "42" 'fn g() -[IO]> i64 { 42 } fn f() -[IO]> i64 { let mut x = 0 while x == 0 { x = g() } x } fn main() { f() }'
run_test_no_err "eff_in_match" "42" 'fn g() -[IO]> i64 { 42 } fn f() -[IO]> i64 { match 1 { _ -> g() } } fn main() { f() }'
# --- Sad: pure calling effectful ---
run_test_err "eff_pure_call_eff" "effect not available" 'fn g() -[IO]> i64 { 42 } fn f() -> i64 { g() } fn main() { f() }'
# --- Sad: effectful calling function with MORE effects ---
run_test_err "eff_missing_one" "effect not available" 'fn g() -[IO, Log]> i64 { 42 } fn f() -[IO]> i64 { g() } fn main() { f() }'
run_test_err "eff_missing_all" "effect not available" 'fn g() -[IO]> i64 { 42 } fn f() -[Log]> i64 { g() } fn main() { f() }'
# --- Sad: pure calling multi-effect ---
run_test_err "eff_pure_call_multi" "effect not available" 'fn g() -[IO, Log]> i64 { 42 } fn f() -> i64 { g() } fn main() { f() }'
# --- Sad: empty effect set calling single effect ---
run_test_err "eff_empty_call_eff" "effect not available" 'fn g() -[IO]> i64 { 42 } fn f() -[]> i64 { g() } fn main() { f() }'
# --- Property: effect subset is reflexive (A ⊆ A) ---
run_test_no_err "eff_prop_reflex" "42" 'fn g() -[IO]> i64 { 42 } fn f() -[IO]> i64 { g() } fn main() { f() }'
run_test_no_err "eff_prop_reflex2" "42" 'fn g() -[IO, Log]> i64 { 42 } fn f() -[IO, Log]> i64 { g() } fn main() { f() }'
# --- Property: pure is subtype of everything ---
run_test_no_err "eff_prop_pure_sub" "42" 'fn g() -> i64 { 42 } fn f() -[IO]> i64 { g() } fn main() { f() }'
run_test_no_err "eff_prop_pure_sub2" "42" 'fn g() -> i64 { 42 } fn f() -[IO, Log, Net]> i64 { g() } fn main() { f() }'
# --- Adversarial: same effect name repeated in annotation ---
run_test2 "eff_adv_dup" "42" 'fn f() -[IO, IO]> i64 { 42 } fn main() -> i64 { f() }'
# --- Adversarial: effect with params (future-proof — currently just names) ---
run_test2 "eff_adv_long_name" "42" 'fn f() -[VeryLongEffectNameThatIsUnusuallyLong]> i64 { 42 } fn main() -> i64 { f() }'
# --- Wicked: transitive purity through unannotated intermediary ---
# g is effectful, h is unannotated (calls g without checking), f is pure (calls h)
# h is unannotated so no checking happens there — the effect "leaks" through
run_test2 "eff_wicked_leak" "42" 'fn g() -[IO]> i64 { 42 } fn h() -> i64 { g() } fn f() -> i64 { h() } fn main() -> i64 { f() }'
# --- Wicked: recursive effectful function ---
run_test_no_err "eff_wicked_recursive" "120" 'fn fact(n: i64) -[IO]> i64 { if n <= 1 { return 1 } n * fact(n - 1) } fn main() { fact(5) }'
# ═══════════════════════════════════════════════════════════════
# 40. CLOSURES / LAMBDAS — comprehensive
# ═══════════════════════════════════════════════════════════════
# --- Happy path: basic lambda ---
run_test2 "lam_const" "42" 'fn main() -> i64 { let f = x => 42 f(0) }'
run_test2 "lam_identity" "42" 'fn main() -> i64 { let f = x => x f(42) }'
run_test2 "lam_add1" "42" 'fn main() -> i64 { let f = x => x + 1 f(41) }'
run_test2 "lam_arith" "42" 'fn main() -> i64 { let f = x => x * 2 + 2 f(20) }'
run_test2 "lam_zero" "0" 'fn main() -> i64 { let f = x => 0 f(99) }'
run_test2 "lam_255" "255" 'fn main() -> i64 { let f = x => 255 f(0) }'
# --- Happy: closure captures ---
run_test2 "lam_cap_one" "42" 'fn main() -> i64 { let a = 10 let f = x => x + a f(32) }'
run_test2 "lam_cap_two" "42" 'fn main() -> i64 { let a = 10 let b = 20 let f = x => x + a + b f(12) }'
run_test2 "lam_cap_three" "42" 'fn main() -> i64 { let a = 1 let b = 2 let c = 3 let f = x => x + a + b + c f(36) }'
run_test2 "lam_cap_nested" "42" 'fn main() -> i64 { let a = 10 let b = 20 let f = x => { let r = x + a r + b } f(12) }'
# --- Happy: passing closures as arguments ---
run_test2 "lam_pass" "42" 'fn apply(f: i64, x: i64) -> i64 { f(x) } fn main() -> i64 { let g = x => x * 2 apply(g, 21) }'
run_test2 "lam_pass_cap" "42" 'fn apply(f: i64, x: i64) -> i64 { f(x) } fn main() -> i64 { let off = 10 let g = x => x + off apply(g, 32) }'
run_test2 "lam_pass_inline" "42" 'fn apply(f: i64, x: i64) -> i64 { f(x) } fn main() -> i64 { apply(x => x + 1, 41) }'
# --- Happy: multiple calls to same closure ---
run_test2 "lam_multi_call" "43" 'fn main() -> i64 { let f = x => x + 1 f(20) + f(21) }'
# --- Happy: closure in if/else ---
run_test2 "lam_in_if" "42" 'fn main() -> i64 { let f = if true { x => 42 } else { x => 0 } f(0) }'
# --- Happy: closure in let chain ---
run_test2 "lam_let_chain" "42" 'fn main() -> i64 { let a = 10 let f = x => x + a let b = f(12) let g = y => y + b g(20) }'
# --- Happy: control flow inside lambda ---
run_test2 "lam_if_body" "42" 'fn main() -> i64 { let f = x => if x > 10 { 42 } else { 0 } f(20) }'
run_test2 "lam_while_body" "42" 'fn main() -> i64 { let f = n => { let mut i = 0 while i < n { i = i + 1 } i } f(42) }'
run_test2 "lam_return" "42" 'fn main() -> i64 { let f = x => { if x > 10 { return 42 } x } f(20) }'
run_test2 "lam_break" "42" 'fn main() -> i64 { let f = x => { let mut i = 0 while i < 100 { if i == x { break } i = i + 1 } i } f(42) }'
# --- Happy: closure capturing closure ---
run_test2 "lam_cap_lam" "42" 'fn apply(f: i64, x: i64) -> i64 { f(x) } fn main() -> i64 { let add = a => b => a + b let add10 = apply(add, 10) apply(add10, 32) }'
# --- Sad paths ---
# (none for closures in bootstrap — no type checking of lambda params yet)
# --- Adversarial ---
run_test2 "lam_adv_many_caps" "42" 'fn main() -> i64 { let a = 1 let b = 2 let c = 3 let d = 4 let e = 5 let g = 6 let h = 7 let i = 8 let f = x => x + a + b + c + d + e + g + h + i f(6) }'
run_test2 "lam_adv_deep" "42" 'fn a3(f: i64, x: i64) -> i64 { f(x) } fn a2(f: i64, x: i64) -> i64 { a3(f, x) } fn a1(f: i64, x: i64) -> i64 { a2(f, x) } fn main() -> i64 { a1(x => x + 1, 41) }'
# --- Property: capture preserves value ---
run_test2 "lam_prop_value" "42" 'fn main() -> i64 { let mut x = 42 let f = y => x x = 99 f(0) }'
# --- Property: multiple calls return same result ---
run_test2 "lam_prop_consistent" "1" 'fn main() -> i64 { let f = x => x + 1 if f(5) == f(5) { 1 } else { 0 } }'
# --- Multi-param lambdas ---
run_test2 "mlam_two" "42" 'fn main() -> i64 { let f = (x, y) => x + y f(20, 22) }'
run_test2 "mlam_three" "42" 'fn main() -> i64 { let f = (a, b, c) => a + b + c f(10, 20, 12) }'
run_test2 "mlam_zero" "42" 'fn main() -> i64 { let f = () => 42 f() }'
run_test2 "mlam_four" "100" 'fn main() -> i64 { let f = (a, b, c, d) => a + b + c + d f(10, 20, 30, 40) }'
# --- Multi-param with captures ---
run_test2 "mlam_cap" "42" 'fn main() -> i64 { let off = 2 let f = (x, y) => x + y + off f(20, 20) }'
# --- Multi-param passed as argument ---
run_test2 "mlam_pass" "42" 'fn apply2(f: i64, a: i64, b: i64) -> i64 { f(a, b) } fn main() -> i64 { apply2((x, y) => x + y, 20, 22) }'
# --- Grouped expression still works (regression) ---
run_test2 "mlam_group" "42" 'fn main() -> i64 { (40 + 2) }'
run_test2 "mlam_group_nested" "42" 'fn main() -> i64 { ((21 * 2)) }'
# --- Disambiguation: (x) is grouped expr, not 1-param lambda (no =>) ---
run_test2 "mlam_disambig" "42" 'fn main() -> i64 { let x = 42 (x) }'
# --- Typed multi-param lambda ---
run_test2 "mlam_typed" "42" 'fn main() -> i64 { let f = (x: i64, y: i64) => x + y f(20, 22) }'
# --- Zero-param lambda with block body ---
run_test2 "mlam_zero_block" "42" 'fn main() -> i64 { let f = () => { let x = 40 x + 2 } f() }'
# --- Multi-param with control flow ---
run_test2 "mlam_control" "42" 'fn main() -> i64 { let f = (x, y) => if x > y { x } else { y } f(42, 10) }'
# ═══════════════════════════════════════════════════════════════
# 41. EFFECT HANDLERS — comprehensive (Tier 2: tail-resumptive)
# ═══════════════════════════════════════════════════════════════
# --- Happy: basic State.get ---
run_test2 "eff_h_get" "42" 'effect State { fn get() -> i64 } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 42) handle State.get() { State.get() -> resume(__mem_load64(c)) } }'
# --- Happy: State.put then get ---
run_test2 "eff_h_put_get" "99" 'effect State { fn get() -> i64 fn put(v: i64) -> i64 } fn do_it() -> i64 { State.put(99) State.get() } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 0) handle do_it() { State.get() -> resume(__mem_load64(c)) State.put(v) -> { __mem_store64(c, v) resume(0) } } }'
# --- Happy: multiple performs accumulate ---
run_test2 "eff_h_multi" "115" 'effect State { fn get() -> i64 fn put(v: i64) -> i64 } fn go() -> i64 { let a = State.get() State.put(a + 10) let b = State.get() State.put(b + 5) State.get() } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 100) handle go() { State.get() -> resume(__mem_load64(c)) State.put(v) -> { __mem_store64(c, v) resume(0) } } }'
# --- Happy: handler captures enclosing variable ---
run_test2 "eff_h_capture" "142" 'effect State { fn get() -> i64 } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 0) let offset = 100 handle { State.get() + 42 } { State.get() -> resume(__mem_load64(c) + offset) } }'
# --- Happy: complex body with block ---
run_test2 "eff_h_complex" "11" 'effect State { fn get() -> i64 fn put(v: i64) -> i64 } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 5) handle { let x = State.get() State.put(x * 2) State.get() + 1 } { State.get() -> resume(__mem_load64(c)) State.put(v) -> { __mem_store64(c, v) resume(0) } } }'
# --- Happy: different effect name (Counter) ---
run_test2 "eff_h_counter" "3" 'effect Counter { fn inc() -> i64 fn read() -> i64 } fn go() -> i64 { Counter.inc() Counter.inc() Counter.inc() Counter.read() } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 0) handle go() { Counter.inc() -> { let v = __mem_load64(c) __mem_store64(c, v + 1) resume(0) } Counter.read() -> resume(__mem_load64(c)) } }'
# --- Happy: body performs no effects ---
run_test2 "eff_h_no_perf" "42" 'effect State { fn get() -> i64 } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 0) handle 42 { State.get() -> resume(__mem_load64(c)) } }'
# --- Happy: single zero-arg operation ---
run_test2 "eff_h_zero_arg" "7" 'effect Ask { fn ask() -> i64 } fn main() -> i64 { handle Ask.ask() { Ask.ask() -> resume(7) } }'
# --- Happy: operation with multiple args ---
run_test2 "eff_h_multi_arg" "30" 'effect Math { fn add(a: i64, b: i64) -> i64 } fn main() -> i64 { handle Math.add(10, 20) { Math.add(a, b) -> resume(a + b) } }'
# --- Property: handler result flows through ---
run_test2 "eff_h_result" "10" 'effect State { fn get() -> i64 } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 10) let r = handle State.get() { State.get() -> resume(__mem_load64(c)) } r }'
# --- Property: perform in if branch ---
run_test2 "eff_h_in_if" "42" 'effect State { fn get() -> i64 } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 42) handle { if true { State.get() } else { 0 } } { State.get() -> resume(__mem_load64(c)) } }'
# --- Property: perform in while loop ---
run_test2 "eff_h_in_while" "10" 'effect Counter { fn inc() -> i64 fn read() -> i64 } fn go() -> i64 { let mut i = 0 while i < 10 { Counter.inc() i = i + 1 } Counter.read() } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 0) handle go() { Counter.inc() -> { __mem_store64(c, __mem_load64(c) + 1) resume(0) } Counter.read() -> resume(__mem_load64(c)) } }'
# --- Adversarial: perform is the entire body (minimal) ---
run_test2 "eff_h_adv_minimal" "1" 'effect E { fn f() -> i64 } fn main() -> i64 { handle E.f() { E.f() -> resume(1) } }'
# --- Adversarial: handler clause with no captures ---
run_test2 "eff_h_adv_no_cap" "77" 'effect E { fn f() -> i64 } fn main() -> i64 { handle E.f() { E.f() -> resume(77) } }'
# ═══════════════════════════════════════════════════════════════
# 42. GENERICS — type parameters on function declarations
# ═══════════════════════════════════════════════════════════════
# --- Happy: generic function declaration parses (type params ignored by codegen) ---
run_test2 "gen_decl_one" "42" 'fn id<T>(x: i64) -> i64 { x } fn main() -> i64 { id(42) }'
run_test2 "gen_decl_two" "42" 'fn pair<A, B>(a: i64, b: i64) -> i64 { a + b } fn main() -> i64 { pair(20, 22) }'
run_test2 "gen_decl_three" "42" 'fn f<X, Y, Z>(x: i64) -> i64 { x } fn main() -> i64 { f(42) }'
# --- Happy: generic fn with type annotations using type params ---
run_test2 "gen_typed_param" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id(42) }'
run_test2 "gen_typed_multi" "42" 'fn fst<A, B>(a: A, b: B) -> A { a } fn main() -> i64 { fst(42, 99) }'
# --- Happy: non-generic functions still work ---
run_test2 "gen_compat" "42" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f(42) }'
# --- Happy: generic + non-generic in same module ---
run_test2 "gen_mixed" "42" 'fn id<T>(x: T) -> T { x } fn add(a: i64, b: i64) -> i64 { a + b } fn main() -> i64 { add(id(20), id(22)) }'
# --- Happy: generic fn calling another generic fn ---
run_test2 "gen_chain" "42" 'fn id<T>(x: T) -> T { x } fn wrap<U>(y: U) -> U { id(y) } fn main() -> i64 { wrap(42) }'
# --- Happy: generic with effect annotation ---
run_test2 "gen_eff" "42" 'fn id<T>(x: T) -[IO]> T { x } fn main() -> i64 { id(42) }'
# --- Adversarial: single-char type param names ---
run_test2 "gen_adv_chars" "42" 'fn f<T>(x: T) -> T { x } fn g<A>(x: A) -> A { x } fn main() -> i64 { f(20) + g(22) }'
# --- Adversarial: type param name same as builtin type ---
run_test2 "gen_adv_shadow" "42" 'fn f<i64>(x: i64) -> i64 { x } fn main() -> i64 { f(42) }'
# --- Happy: explicit type args at call site ---
run_test2 "gen_call_one" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<i64>(42) }'
run_test2 "gen_call_two" "42" 'fn fst<A, B>(a: A, b: B) -> A { a } fn main() -> i64 { fst<i64, i64>(42, 99) }'
run_test2 "gen_call_expr" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<i64>(20) + id<i64>(22) }'
# --- Happy: generic call with closure arg ---
run_test2 "gen_call_lam" "42" 'fn apply<T, U>(f: i64, x: T) -> U { f(x) } fn main() -> i64 { apply<i64, i64>(x => x + 1, 41) }'
# --- Happy: non-generic fn called with type args (ignored) ---
run_test2 "gen_call_mono" "42" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { f<i64>(42) }'
# --- Happy: comparison still works (< disambiguation) ---
run_test2 "gen_cmp_ok" "42" 'fn main() -> i64 { if 1 < 2 { 42 } else { 0 } }'
run_test2 "gen_cmp_chain" "42" 'fn main() -> i64 { let x = 10 if x < 100 { 42 } else { 0 } }'
# ═══════════════════════════════════════════════════════════════
# 43. FUNCTION TYPE ANNOTATIONS — comprehensive
# ═══════════════════════════════════════════════════════════════
# --- Happy: basic function type params ---
run_test2 "fntype_basic" "42" 'fn apply(f: (i64) -> i64, x: i64) -> i64 { f(x) } fn main() -> i64 { apply(x => x + 1, 41) }'
run_test2 "fntype_multi" "42" 'fn ap2(f: (i64, i64) -> i64, a: i64, b: i64) -> i64 { f(a, b) } fn main() -> i64 { ap2((x, y) => x + y, 20, 22) }'
run_test2 "fntype_empty" "42" 'fn call(f: () -> i64) -> i64 { f() } fn main() -> i64 { call(() => 42) }'
# --- Happy: effectful function type ---
run_test2 "fntype_effect" "42" 'fn apply(f: (i64) -[IO]> i64, x: i64) -> i64 { f(x) } fn main() -> i64 { apply(x => x + 1, 41) }'
# --- Happy: generic with function type param ---
run_test2 "fntype_generic" "42" 'fn apply<T, U>(f: (T) -> U, x: T) -> U { f(x) } fn main() -> i64 { apply(x => x + 1, 41) }'
run_test2 "fntype_gen_typed" "42" 'fn apply<T, U>(f: (T) -> U, x: T) -> U { f(x) } fn main() -> i64 { apply<i64, i64>(x => x + 1, 41) }'
# --- Happy: grouped type (single type in parens) still works ---
run_test2 "fntype_grouped" "42" 'fn f(x: (i64)) -> i64 { x } fn main() -> i64 { f(42) }'
# --- Variant: function type in return position ---
run_test2 "fntype_ret_pos" "42" 'fn make_adder(n: i64) -> (i64) -> i64 { x => x + n } fn main() -> i64 { let f = make_adder(1) f(41) }'
# --- Variant: nested function types ---
run_test2 "fntype_nested" "41" 'fn apply(f: (i64) -> i64, x: i64) -> i64 { f(x) } fn compose(f: (i64) -> i64, g: (i64) -> i64, x: i64) -> i64 { f(g(x)) } fn main() -> i64 { compose(x => x + 1, x => x * 2, 20) }'
# --- Variant: higher-order (fn taking fn returning fn) ---
run_test2 "fntype_higher" "42" 'fn twice(f: (i64) -> i64, x: i64) -> i64 { f(f(x)) } fn main() -> i64 { twice(x => x + 1, 40) }'
# --- Variant: four params in function type ---
run_test2 "fntype_four" "100" 'fn ap4(f: (i64, i64, i64, i64) -> i64, a: i64, b: i64, c: i64, d: i64) -> i64 { f(a, b, c, d) } fn main() -> i64 { ap4((a, b, c, d) => a + b + c + d, 10, 20, 30, 40) }'
# --- Sad: function type mismatch (param type not i64) ---
run_test_err "fntype_sad_param" "argument type mismatch" 'fn f(g: (str) -> i64) -> i64 { g(42) } fn main() -> i64 { f(x => x) }'
# --- Sad: function type return mismatch ---
run_test_err "fntype_sad_ret" "return type mismatch" 'fn f(g: (i64) -> str) -> str { g(42) } fn main() -> i64 { 42 }'
# --- Adversarial: deeply nested function type ---
run_test2 "fntype_adv_deep" "42" 'fn ap(f: ((i64) -> i64) -> i64, g: (i64) -> i64) -> i64 { f(g) } fn main() -> i64 { ap(f => f(41), x => x + 1) }'
# --- Adversarial: function type with union return ---
run_test2 "fntype_adv_union" "42" 'fn f(g: (i64) -> i64 | nil) -> i64 { g(42) } fn main() -> i64 { f(x => x) }'
# ═══════════════════════════════════════════════════════════════
# 44. LET TYPE ANNOTATIONS — comprehensive
# ═══════════════════════════════════════════════════════════════
# --- Happy: basic let with type ---
run_test2 "let_type_basic" "42" 'fn main() -> i64 { let x: i64 = 42 x }'
run_test2 "let_type_str" "3" 'fn main() -> i64 { let s: str = "abc" __str_len(s) }'
# --- Happy: let mut with type ---
run_test2 "let_type_mut" "42" 'fn main() -> i64 { let mut x: i64 = 0 x = 42 x }'
# --- Happy: let with complex type (union) ---
run_test2 "let_type_union" "42" 'fn main() -> i64 { let x: i64 | str = 42 x }'
# --- Happy: let with function type ---
run_test2 "let_type_fn" "42" 'fn main() -> i64 { let f: (i64) -> i64 = x => x + 1 f(41) }'
# --- Happy: let type doesn't break existing code ---
run_test2 "let_type_compat" "42" 'fn main() -> i64 { let x = 42 x }'
# --- Sad: let type annotation mismatch ---
run_test_err "let_type_sad_str" "value does not match let type annotation" 'fn f(x: str) -> str { let y: i64 = x y } fn main() -> i64 { 42 }'
run_test_err "let_type_sad_int" "value does not match let type annotation" 'fn main() -> i64 { let x: str = 42 0 }'
# --- Adversarial: let with nullable type ---
run_test2 "let_type_adv_null" "42" 'fn main() -> i64 { let x: i64? = 42 x }'
# --- Adversarial: let with parenthesized type ---
run_test2 "let_type_adv_paren" "42" 'fn main() -> i64 { let x: (i64) = 42 x }'
# --- Happy: type checker synthesizes correct return type after substitution ---
run_test_no_err "gen_tc_ret" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { let r: i64 = id<i64>(42) r }'
# --- Sad: type var used in arithmetic (checker catches type mismatch) ---
run_test_err "gen_sad_arith" "arithmetic operand is not i64" 'fn f<T>(x: T) -> T { x + 1 } fn main() -> i64 { f(42) }'
# --- Sad: type var in return position mismatches i64 ---
run_test_err "gen_sad_ret" "return type mismatch" 'fn f<T>(x: T) -> i64 { x } fn main() -> i64 { f(42) }'
# --- Sad: wrong number of type arguments ---
run_test_err "gen_sad_targ_count" "wrong number of type arguments" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<i64, str>(42) }'
# --- Sad: arg type mismatch after substitution (T=str but pass i64) ---
run_test_err "gen_sad_arg_subst" "argument type mismatch" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<str>(42) }'
# --- Sad: return type mismatch after substitution (T=str but fn returns i64) ---
run_test_err "gen_sad_ret_subst" "return type mismatch" 'fn id<T>(x: T) -> T { x } fn f() -> i64 { id<str>("hi") }'
# ═══════════════════════════════════════════════════════════════
# 45. COMPREHENSIVE QUALITY PASS — pathological, wicked, property
# ═══════════════════════════════════════════════════════════════
#
# ── Effect handlers: pathological ──
# Nested handlers (inner handler shadows outer)
run_test2 "eff_path_nested" "10" 'effect A { fn get() -> i64 } effect B { fn get() -> i64 } fn go() -> i64 { B.get() } fn main() -> i64 { let ca = __bump_alloc(8) __mem_store64(ca, 99) let cb = __bump_alloc(8) __mem_store64(cb, 10) handle { handle go() { B.get() -> resume(__mem_load64(cb)) } } { A.get() -> resume(__mem_load64(ca)) } }'
# Handler correctly popped: inner handler doesn't leak
run_test2 "eff_path_pop" "42" 'effect S { fn get() -> i64 } fn inner() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 99) handle S.get() { S.get() -> resume(__mem_load64(c)) } } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 42) handle { inner() S.get() } { S.get() -> resume(__mem_load64(c)) } }'
# Many operations in one handler (3 ops)
run_test2 "eff_path_many_ops" "6" 'effect M { fn a() -> i64 fn b() -> i64 fn c() -> i64 } fn go() -> i64 { M.a() + M.b() + M.c() } fn main() -> i64 { handle go() { M.a() -> resume(1) M.b() -> resume(2) M.c() -> resume(3) } }'
# Handler in a loop (handler push/pop repeatedly)
run_test2 "eff_path_loop" "45" 'effect S { fn get() -> i64 } fn main() -> i64 { let mut sum = 0 let mut i = 0 while i < 10 { let c = __bump_alloc(8) __mem_store64(c, i) sum = sum + handle S.get() { S.get() -> resume(__mem_load64(c)) } i = i + 1 } sum }'
#
# ── Effect handlers: wicked ──
# Perform inside a lambda inside a handle
run_test2 "eff_wicked_lam" "42" 'effect S { fn get() -> i64 } fn apply(f: (i64) -> i64, x: i64) -> i64 { f(x) } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 42) handle { let f = x => S.get() + x apply(f, 0) } { S.get() -> resume(__mem_load64(c)) } }'
# Perform result used in a match
run_test2 "eff_wicked_match" "1" 'effect S { fn get() -> i64 } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 42) handle { match S.get() { 42 -> 1 _ -> 0 } } { S.get() -> resume(__mem_load64(c)) } }'
# Handler clause captures a mutable cell and mutates it across multiple performs
run_test2 "eff_wicked_accum" "55" 'effect S { fn add(v: i64) -> i64 fn total() -> i64 } fn go() -> i64 { let mut i = 1 while i <= 10 { S.add(i) i = i + 1 } S.total() } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 0) handle go() { S.add(v) -> { __mem_store64(c, __mem_load64(c) + v) resume(0) } S.total() -> resume(__mem_load64(c)) } }'
#
# ── Effect handlers: property ──
# Handler result IS the body result when no effects performed
run_test2 "eff_prop_passthru" "99" 'effect E { fn f() -> i64 } fn main() -> i64 { handle 99 { E.f() -> resume(0) } }'
# Sequential performs return correct values
run_test2 "eff_prop_seq" "15" 'effect S { fn get() -> i64 fn put(v: i64) -> i64 } fn go() -> i64 { let a = S.get() S.put(a + 5) S.get() } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 10) handle go() { S.get() -> resume(__mem_load64(c)) S.put(v) -> { __mem_store64(c, v) resume(0) } } }'
#
# ── Generics: pathological ──
# Many type params (5)
run_test2 "gen_path_five" "15" 'fn sum5<A, B, C, D, E>(a: A, b: B, c: C, d: D, e: E) -> i64 { a + b + c + d + e } fn main() -> i64 { sum5<i64, i64, i64, i64, i64>(1, 2, 3, 4, 5) }'
# Generic fn calling itself recursively
run_test2 "gen_path_recur" "120" 'fn fact<T>(n: T) -> T { if n <= 1 { 1 } else { n * fact<T>(n - 1) } } fn main() -> i64 { fact<i64>(5) }'
# Chain of generic calls with different type args (all i64 in bootstrap)
run_test2 "gen_path_chain" "42" 'fn id<T>(x: T) -> T { x } fn wrap<U>(x: U) -> U { id<U>(x) } fn outer<V>(x: V) -> V { wrap<V>(x) } fn main() -> i64 { outer<i64>(42) }'
#
# ── Generics: wicked ──
# Generic + effects combined
run_test2 "gen_wicked_eff" "42" 'effect S { fn get() -> i64 } fn id<T>(x: T) -> T { x } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 42) handle id<i64>(S.get()) { S.get() -> resume(__mem_load64(c)) } }'
# Generic call in if condition
run_test2 "gen_wicked_if" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { if id<i64>(1) == 1 { 42 } else { 0 } }'
# Generic call in while condition
run_test2 "gen_wicked_while" "10" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { let mut i = 0 while id<i64>(i) < 10 { i = i + 1 } i }'
# Generic call as match scrutinee
run_test2 "gen_wicked_match" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { match id<i64>(1) { 1 -> 42 _ -> 0 } }'
# Type arg is the return type, not the param type
run_test2 "gen_wicked_ret" "42" 'fn make<T>(x: i64) -> T { x } fn main() -> i64 { make<i64>(42) }'
#
# ── Generics: property ──
# id is the identity: id<T>(x) == x for various types
run_test2 "gen_prop_id_int" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<i64>(42) }'
run_test2 "gen_prop_id_zero" "0" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<i64>(0) }'
run_test2 "gen_prop_id_neg" "201" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<i64>(201) }'
# Substitution preserves concrete types: T=i64 means param is i64
run_test_no_err "gen_prop_subst" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { let r: i64 = id<i64>(42) r }'
#
# ── Function types: pathological ──
# Nested function type: fn taking fn returning fn
run_test2 "fntype_path_nest" "43" 'fn ap(f: ((i64) -> i64) -> i64, g: (i64) -> i64) -> i64 { f(g) } fn main() -> i64 { ap(f => f(42), x => x + 1) }'
# Function type with 0 params and 4 params
run_test2 "fntype_path_0_4" "142" 'fn c0(f: () -> i64) -> i64 { f() } fn c4(f: (i64, i64, i64, i64) -> i64) -> i64 { f(10, 20, 30, 40) } fn main() -> i64 { c0(() => 42) + c4((a, b, c, d) => a + b + c + d) }'
#
# ── Function types: wicked ──
# Function type inside union type annotation
run_test2 "fntype_wicked_union" "42" 'fn f(g: (i64) -> i64 | nil, x: i64) -> i64 { g(x) } fn main() -> i64 { f(x => x, 42) }'
# Function type with generic type variable params
run_test2 "fntype_wicked_gen" "42" 'fn map<T, U>(f: (T) -> U, x: T) -> U { f(x) } fn main() -> i64 { map<i64, i64>(x => x + 1, 41) }'
# Returning a function type value
run_test2 "fntype_wicked_ret" "42" 'fn make(n: i64) -> (i64) -> i64 { x => x + n } fn main() -> i64 { let f: (i64) -> i64 = make(2) f(40) }'
#
# ── Let types: wicked ──
# Let type annotation with function call value
run_test2 "let_wicked_call" "42" 'fn f() -> i64 { 42 } fn main() -> i64 { let x: i64 = f() x }'
# Let type annotation used for variable type in subsequent check
run_test_no_err "let_wicked_flow" "42" 'fn f(x: i64) -> i64 { x } fn main() -> i64 { let x: i64 = 42 f(x) }'
# Let mut type annotation, then reassign
run_test2 "let_wicked_mut_reassign" "99" 'fn main() -> i64 { let mut x: i64 = 42 x = 99 x }'
#
# ── Let type vars in generic functions (tctx gap fix) ──
# Happy: let with type var annotation works inside generic fn
run_test2 "let_gen_tvar" "42" 'fn id<T>(x: T) -> T { let y: T = x y } fn main() -> i64 { id<i64>(42) }'
# Happy: multiple type vars in let annotations
run_test2 "let_gen_multi" "42" 'fn fst<A, B>(a: A, b: B) -> A { let x: A = a let y: B = b x } fn main() -> i64 { fst<i64, i64>(42, 99) }'
# Happy: let with type var in control flow inside generic fn
run_test2 "let_gen_if" "42" 'fn f<T>(x: T, b: i64) -> T { let y: T = if b == 1 { x } else { x } y } fn main() -> i64 { f<i64>(42, 1) }'
# Sad: let annotation T but value is clearly wrong type (checker catches)
run_test_err "let_gen_sad_mismatch" "value does not match let type annotation" 'fn f<T>(x: T) -> T { let y: i64 = x y } fn main() -> i64 { f<str>("hi") }'
# Sad: let annotation i64 but var is T (T is not subtype of i64)
run_test_err "let_gen_sad_tvar_not_i64" "value does not match let type annotation" 'fn f<T>(x: T) -> i64 { let y: i64 = x y } fn main() -> i64 { f(42) }'
# Property: tctx restored — non-generic fn after generic fn still works
run_test2 "let_gen_prop_restore" "42" 'fn id<T>(x: T) -> T { let y: T = x y } fn plain(x: i64) -> i64 { let y: i64 = x y } fn main() -> i64 { plain(id<i64>(42)) }'
# Adversarial: let type var in lambda inside generic fn
run_test2 "let_gen_adv_lam" "42" 'fn f<T>(x: T) -> T { let g = (y: T) => y g(x) } fn main() -> i64 { f<i64>(42) }'
# ═══════════════════════════════════════════════════════════════
# 46. GENERIC TYPE DECLARATIONS — comprehensive (Phase 4)
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: basic generic variant ──
run_test2 "gtype_box" "42" 'type Box<T> { Box(T) } fn main() -> i64 { let b = Box(42) match b { Box(x) -> x } }'
run_test2 "gtype_option" "42" 'type Option<T> { Some(T), None } fn main() -> i64 { match Some(42) { Some(v) -> v None -> 0 } }'
run_test2 "gtype_either" "42" 'type Either<A, B> { Left(A), Right(B) } fn main() -> i64 { let e = Left(42) match e { Left(v) -> v Right(v) -> v } }'
# ── Happy: generic record ──
run_test2 "gtype_pair" "42" 'type Pair<A, B> { fst: A, snd: B } fn main() -> i64 { let p = Pair { fst: 20, snd: 22 } p.fst + p.snd }'
# ── Happy: constructor with explicit type args ──
run_test2 "gtype_ctor_typed" "42" 'type Box<T> { Box(T) } fn main() -> i64 { match Box<i64>(42) { Box(x) -> x } }'
# ── Happy: type args in annotation position ──
run_test2 "gtype_ann" "42" 'type Box<T> { Box(T) } fn unbox(b: Box<i64>) -> i64 { match b { Box(x) -> x } } fn main() -> i64 { unbox(Box(42)) }'
# ── Happy: generic fn + generic type together ──
run_test2 "gtype_with_gen_fn" "42" 'type Box<T> { Box(T) } fn unbox<T>(b: Box<T>) -> T { match b { Box(x) -> x } } fn main() -> i64 { unbox<i64>(Box(42)) }'
# ── Happy: None variant (no payload) ──
run_test2 "gtype_none" "0" 'type Option<T> { Some(T), None } fn main() -> i64 { match None { Some(v) -> v None -> 0 } }'
# ── Happy: nested generic type usage ──
run_test2 "gtype_nested" "42" 'type Box<T> { Box(T) } fn main() -> i64 { let b = Box(Box(42)) match b { Box(inner) -> match inner { Box(x) -> x } } }'
#
# ── Sad: type checker catches errors ──
run_test_err "gtype_sad_ctor" "argument type mismatch" 'type Box<T> { Box(T) } fn f() -> i64 { let b: Box<str> = Box<str>(42) 0 } fn main() -> i64 { 42 }'
#
# ── Variants: all pattern forms with generic types ──
run_test2 "gtype_var_wildcard" "1" 'type Box<T> { Box(T) } fn main() -> i64 { match Box(42) { _ -> 1 } }'
run_test2 "gtype_var_binding" "42" 'type Box<T> { Box(T) } fn main() -> i64 { match Box(42) { b -> match b { Box(x) -> x } } }'
run_test2 "gtype_var_multi_arm" "2" 'type Option<T> { Some(T), None } fn main() -> i64 { match None { Some(v) -> 1 None -> 2 } }'
#
# ── Adversarial ──
run_test2 "gtype_adv_recur" "3" 'type List<T> { Nil, Cons(T) } fn main() -> i64 { let a = Cons(1) let b = Cons(2) match a { Cons(v) -> v + match b { Cons(w) -> w Nil -> 0 } Nil -> 0 } }'
run_test2 "gtype_adv_many" "42" 'type Triple<A, B, C> { fst: A, snd: B, thd: C } fn main() -> i64 { let t = Triple { fst: 10, snd: 20, thd: 12 } t.fst + t.snd + t.thd }'
run_test2 "gtype_adv_eff" "42" 'type Box<T> { Box(T) } effect S { fn get() -> i64 } fn main() -> i64 { let c = __bump_alloc(8) __mem_store64(c, 42) handle { let b = Box(S.get()) match b { Box(x) -> x } } { S.get() -> resume(__mem_load64(c)) } }'
run_test2 "gtype_adv_mixed" "42" 'type Box<T> { Box(T) } type Plain { Val(i64) } fn main() -> i64 { let b = Box(20) let p = Val(22) match b { Box(x) -> x + match p { Val(y) -> y } } }'
#
# ── Property ──
run_test2 "gtype_prop_roundtrip" "42" 'type Box<T> { Box(T) } fn main() -> i64 { let x = 42 match Box(x) { Box(y) -> y } }'
run_test2 "gtype_prop_some" "42" 'type Option<T> { Some(T), None } fn main() -> i64 { match Some(42) { Some(v) -> v None -> 0 } }'
# ═══════════════════════════════════════════════════════════════
# 47. REGRESSION: bare constructors, no-payload variants, record disambig
# ═══════════════════════════════════════════════════════════════
#
# ── Bare no-payload constructors in expression position ──
run_test2 "bare_none_expr" "0" 'type O<T> { Some(T), None } fn main() -> i64 { match None { Some(v) -> v None -> 0 } }'
run_test2 "bare_nil_expr" "99" 'type L<T> { Nil, Cons(T) } fn main() -> i64 { match Nil { Cons(v) -> v Nil -> 99 } }'
run_test2 "bare_multi_ctor" "2" 'type Color { Red, Green, Blue } fn main() -> i64 { match Green { Red -> 1 Green -> 2 Blue -> 3 } }'
run_test2 "bare_first_arm" "1" 'type Color { Red, Green, Blue } fn main() -> i64 { match Red { Red -> 1 Green -> 2 Blue -> 3 } }'
run_test2 "bare_last_arm" "3" 'type Color { Red, Green, Blue } fn main() -> i64 { match Blue { Red -> 1 Green -> 2 Blue -> 3 } }'
# Bare constructor passed as argument
run_test2 "bare_as_arg" "1" 'type O<T> { Some(T), None } fn is_none(x: i64) -> i64 { match x { None -> 1 _ -> 0 } } fn main() -> i64 { is_none(None) }'
# Bare constructor in if branch
run_test2 "bare_in_if" "99" 'type O<T> { Some(T), None } fn main() -> i64 { let x = if true { None } else { Some(1) } match x { Some(v) -> v None -> 99 } }'
# Bare constructor in let binding
run_test2 "bare_in_let" "99" 'type O<T> { Some(T), None } fn main() -> i64 { let x = None match x { Some(v) -> v None -> 99 } }'
# Bare constructor returned from function
run_test2 "bare_from_fn" "99" 'type O<T> { Some(T), None } fn make_none() -> i64 { None } fn main() -> i64 { match make_none() { Some(v) -> v None -> 99 } }'
#
# ── No-payload variant sentinel (emit_mov_imm -1 bug) ──
# Multiple no-payload variants in same type
run_test2 "nopay_multi" "42" 'type T { A, B, C(i64) } fn main() -> i64 { match C(42) { A -> 0 B -> 0 C(v) -> v } }'
# No-payload then payload in sequence
run_test2 "nopay_sequence" "42" 'type O<T> { Some(T), None } fn main() -> i64 { let a = None let b = Some(42) match a { Some(v) -> 0 None -> match b { Some(v) -> v None -> 0 } } }'
# No-payload in a loop
run_test2 "nopay_loop" "5" 'type O<T> { Some(T), None } fn main() -> i64 { let mut count = 0 let mut i = 0 while i < 10 { let x = if i < 5 { None } else { Some(1) } match x { Some(v) -> { count = count + v } None -> { 0 } } i = i + 1 } count }'
#
# ── Record literal disambiguation (UpperCase { peek for : ) ──
# match with bare uppercase scrutinee + arms block
run_test2 "disambig_match" "42" 'type X { A, B } fn main() -> i64 { match A { A -> 42 B -> 0 } }'
# Record literal still works alongside
run_test2 "disambig_record" "42" 'type Point { x: i64, y: i64 } fn main() -> i64 { let p = Point { x: 20, y: 22 } p.x + p.y }'
# Match with uppercase scrutinee that IS a variable (not a constructor)
run_test2 "disambig_var" "42" 'fn main() -> i64 { let X = 42 match X { 42 -> 42 _ -> 0 } }'
# Record + variant in same program (disambiguation works for both)
run_test2 "disambig_both" "42" 'type Pt { x: i64, y: i64 } type Op<T> { Some(T), None } fn main() -> i64 { let p = Pt { x: 20, y: 22 } match None { Some(v) -> 0 None -> p.x + p.y } }'
# Nested match with bare constructors
run_test2 "disambig_nested" "3" 'type O<T> { Some(T), None } fn main() -> i64 { match Some(1) { Some(v) -> match None { Some(w) -> 0 None -> v + 2 } None -> 0 } }'
#
# ── Constructor type checking (payload type + tparams) ──
# Sad: generic constructor arg mismatch detected
run_test_err "ctor_tc_mismatch" "argument type mismatch" 'type Box<T> { Box(T) } fn main() -> i64 { Box<str>(42) 0 }'
# Sad: Either<str, i64> Left with wrong arg type
run_test_err "ctor_tc_either" "argument type mismatch" 'type Either<A, B> { Left(A), Right(B) } fn main() -> i64 { Left<str>("hi") Right<i64>(42) Left<i64>("bad") 0 }'
# Happy: correct generic constructor doesn't error
run_test_no_err "ctor_tc_ok" "42" 'type Box<T> { Box(T) } fn main() -> i64 { match Box<i64>(42) { Box(x) -> x } }'
# ═══════════════════════════════════════════════════════════════
# 48. HANDLER DISCHARGE TYPING — comprehensive (effect Phase 3)
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: handle discharges effect — body can use it ──
# Pure function handles State — no effect error
run_test_no_err "discharge_basic" "42" 'effect State { fn get() -> i64 } fn go() -[State]> i64 { 42 } fn main() -> i64 { handle go() { State.get() -> resume(0) } }'
# Pure function handles IO
run_test_no_err "discharge_io" "42" 'effect MyIO { fn print() -> i64 } fn go() -[MyIO]> i64 { 42 } fn main() -> i64 { handle go() { MyIO.print() -> resume(0) } }'
# Effectful function handles a DIFFERENT effect
run_test_no_err "discharge_diff" "42" 'effect A { fn f() -> i64 } effect B { fn g() -> i64 } fn go() -[A]> i64 { 42 } fn main() -[B]> i64 { handle go() { A.f() -> resume(0) } }'
#
# ── Sad: effect NOT discharged — should error ──
# Pure function calls effectful without handle
run_test_err "discharge_sad_no_handle" "effect not available" 'effect State { fn get() -> i64 } fn go() -[State]> i64 { 42 } fn f() -> i64 { go() } fn main() -> i64 { 42 }'
# Handle discharges one effect but body has two — second still errors
run_test_err "discharge_sad_partial" "effect not available" 'effect A { fn f() -> i64 } effect B { fn g() -> i64 } fn go() -[A, B]> i64 { 42 } fn f() -> i64 { handle go() { A.f() -> resume(0) } } fn main() -> i64 { 42 }'
# Pure function tries to perform effect without handle
run_test_err "discharge_sad_perform" "effect not available" 'effect State { fn get() -> i64 } fn go() -[State]> i64 { 42 } fn bad() -> i64 { go() } fn main() -> i64 { bad() }'
#
# ── Variants: different effect configurations ──
# Multiple operations in one handler
run_test_no_err "discharge_multi_op" "42" 'effect State { fn get() -> i64 fn put(v: i64) -> i64 } fn go() -[State]> i64 { 42 } fn main() -> i64 { handle go() { State.get() -> resume(0) State.put(v) -> resume(0) } }'
# Handle in effectful function — discharges one, keeps the other
run_test_no_err "discharge_keep" "42" 'effect A { fn f() -> i64 } effect B { fn g() -> i64 } fn go() -[A]> i64 { 42 } fn f() -[B]> i64 { handle go() { A.f() -> resume(0) } } fn main() -[B]> i64 { f() }'
#
# ── Adversarial ──
# Nested handles discharge different effects
run_test_no_err "discharge_adv_nested" "42" 'effect A { fn f() -> i64 } effect B { fn g() -> i64 } fn go() -[A, B]> i64 { 42 } fn main() -> i64 { handle { handle go() { A.f() -> resume(0) } } { B.g() -> resume(0) } }'
# Handle wrapping a non-effectful body (no-op but valid)
run_test_no_err "discharge_adv_noop" "42" 'effect A { fn f() -> i64 } fn main() -> i64 { handle 42 { A.f() -> resume(0) } }'
# Handle inside a loop
run_test_no_err "discharge_adv_loop" "42" 'effect A { fn f() -> i64 } fn go() -[A]> i64 { 42 } fn main() -> i64 { let mut r = 0 let mut i = 0 while i < 1 { r = handle go() { A.f() -> resume(42) } i = i + 1 } r }'
#
# ── Property: discharge is set-minus ──
# A function with [A, B] — handle A leaves [B] — handle B leaves [] → pure
run_test_no_err "discharge_prop_chain" "42" 'effect A { fn f() -> i64 } effect B { fn g() -> i64 } fn go() -[A, B]> i64 { 42 } fn main() -> i64 { handle { handle go() { B.g() -> resume(0) } } { A.f() -> resume(0) } }'
# Discharge same effect twice (nested handles for same effect)
run_test_no_err "discharge_prop_double" "42" 'effect A { fn f() -> i64 } fn inner() -[A]> i64 { 42 } fn outer() -[A]> i64 { handle inner() { A.f() -> resume(0) } } fn main() -> i64 { handle outer() { A.f() -> resume(0) } }'
# ═══════════════════════════════════════════════════════════════
# 49. TRAITS AND IMPL BLOCKS — Phases 1-2
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: trait declaration parsed ──
run_test2 "trait_decl_parsed" "42" 'trait Display { fn display(self: i64) -> i64 } fn main() -> i64 { 42 }'
# ── Happy: inherent impl on record type ──
run_test2 "impl_inherent_record" "42" 'type Point { x: i64, y: i64 } impl Point { fn sum(self: i64) -> i64 { let s = self __mem_load64(s) + __mem_load64(s + 8) } } fn main() -> i64 { let p = Point { x: 30, y: 12 } p.sum() }'
# ── Happy: inherent impl on primitive (i64) ──
run_test2 "impl_prim_i64" "42" 'impl i64 { fn answer(self: i64) -> i64 { 42 } } fn main() -> i64 { let x: i64 = 5 x.answer() }'
# ── Happy: trait impl for primitive ──
run_test2 "trait_impl_prim" "42" 'trait Greet { fn greet(self: i64) -> i64 } impl Greet for i64 { fn greet(self: i64) -> i64 { 42 } } fn main() -> i64 { let x: i64 = 5 x.greet() }'
# ── Happy: trait impl for user-defined type ──
run_test2 "trait_impl_record" "42" 'trait Val { fn val(self: i64) -> i64 } type Box { v: i64 } impl Val for Box { fn val(self: i64) -> i64 { __mem_load64(self) } } fn main() -> i64 { let b = Box { v: 42 } b.val() }'
# ── Happy: self as value — method uses self ──
run_test2 "self_value_use" "10" 'impl i64 { fn double(self: i64) -> i64 { self + self } } fn main() -> i64 { let x: i64 = 5 x.double() }'
# ── Happy: method with additional args ──
run_test2 "method_extra_args" "42" 'type Box { v: i64 } impl Box { fn add(self: i64, n: i64) -> i64 { __mem_load64(self) + n } } fn main() -> i64 { let b = Box { v: 20 } b.add(22) }'
# ── Happy: multiple methods in one impl ──
run_test2 "impl_multi_methods" "42" 'type Pair { a: i64, b: i64 } impl Pair { fn first(self: i64) -> i64 { __mem_load64(self) } fn second(self: i64) -> i64 { __mem_load64(self + 8) } fn sum(self: i64) -> i64 { __mem_load64(self) + __mem_load64(self + 8) } } fn main() -> i64 { let p = Pair { a: 20, b: 22 } p.sum() }'
# ── Happy: multiple impl blocks with same method name on different types ──
run_test2 "impl_type_dispatch" "42" 'type Foo { x: i64 } type Bar { y: i64 } impl Foo { fn val(self: i64) -> i64 { __mem_load64(self) } } impl Bar { fn val(self: i64) -> i64 { __mem_load64(self) + 10 } } fn main() -> i64 { let f = Foo { x: 20 } let b = Bar { y: 12 } f.val() + b.val() }'
# ── Happy: method call chaining ──
run_test2 "method_chain" "42" 'type W { v: i64 } impl W { fn get(self: i64) -> i64 { __mem_load64(self) } } impl i64 { fn double(self: i64) -> i64 { self + self } fn plus(self: i64, n: i64) -> i64 { self + n } } fn main() -> i64 { let w = W { v: 20 } w.get().double().plus(2) }'
# ── Happy: method inside conditional ──
run_test2 "method_in_if" "42" 'type N { v: i64 } impl N { fn val(self: i64) -> i64 { __mem_load64(self) } fn big(self: i64) -> i64 { if __mem_load64(self) > 10 { 1 } else { 0 } } } fn main() -> i64 { let n = N { v: 42 } if n.big() == 1 { n.val() } else { 0 } }'
# ── Happy: method call inside recursive function ──
run_test2 "method_recursive" "42" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } } fn go(x: i64, t: i64) -> i64 { if x >= t { x } else { go(x.inc(), t) } } fn main() -> i64 { go(0, 42) }'
# ── Happy: method in while loop ──
run_test2 "method_in_loop" "42" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } } fn main() -> i64 { let mut x: i64 = 0 while x < 42 { x = x.inc() } x }'
# ── Happy: effect perform still works alongside impls ──
run_test2 "effect_with_impl" "42" 'effect C { fn inc() -> i64 } fn u() -> i64 { C.inc() } fn main() -> i64 { handle u() { C.inc() -> resume(42) } }'
# ── Happy: effect perform and method call in same function ──
run_test2 "effect_and_method" "42" 'effect C { fn inc() -> i64 } impl i64 { fn pt(self: i64) -> i64 { self + 10 } } fn u() -> i64 { let b = C.inc() b.pt() } fn main() -> i64 { handle u() { C.inc() -> resume(32) } }'
# ── Happy: method on variant type ──
run_test2 "method_variant" "42" 'type Shape { Circle(i64) } impl Shape { fn radius(self: i64) -> i64 { __mem_load64(self + 8) } } fn main() -> i64 { let c = Circle(42) c.radius() }'
# ── Happy: impl for str type ──
run_test2 "impl_str" "42" 'impl str { fn len42(self: i64) -> i64 { 42 } } fn main() -> i64 { let s = "hello" s.len42() }'
# ── Happy: method call result used in let binding ──
run_test2 "method_let_bind" "42" 'impl i64 { fn triple(self: i64) -> i64 { self * 3 } } fn main() -> i64 { let x: i64 = 14 let y = x.triple() y }'
# ── Happy: method call as function argument ──
run_test2 "method_as_arg" "42" 'impl i64 { fn dbl(self: i64) -> i64 { self + self } } fn add(a: i64, b: i64) -> i64 { a + b } fn main() -> i64 { let x: i64 = 20 let y: i64 = 11 add(x, y.dbl()) }'
# ── Happy: method call in match scrutinee ──
run_test2 "method_in_match" "42" 'impl i64 { fn get(self: i64) -> i64 { self } } fn main() -> i64 { let x: i64 = 42 match x.get() { 42 -> 42 _ -> 0 } }'
# ── Happy: impl method calling another function ──
run_test2 "method_calls_fn" "42" 'fn helper(n: i64) -> i64 { n * 2 } impl i64 { fn dbl(self: i64) -> i64 { helper(self) } } fn main() -> i64 { let x: i64 = 21 x.dbl() }'
# ── Happy: impl method calling another method ──
run_test2 "method_calls_method" "42" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } fn inc2(self: i64) -> i64 { self.inc().inc() } } fn main() -> i64 { let x: i64 = 40 x.inc2() }'
# ── Disambiguation: variable named like a type ──
run_test2 "disambig_var_type" "42" 'type Foo { x: i64 } impl Foo { fn val(self: i64) -> i64 { __mem_load64(self) } } fn main() -> i64 { let Foo = Foo { x: 42 } Foo.val() }'
#
# ═══════════════════════════════════════════════════════════════
# 50. CONFORMANCE TABLE + TRAIT BOUNDS (Phase 2-3)
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: trait bound satisfied (impl exists) ──
run_test2 "bound_satisfied" "42" 'trait Show { fn show(self: i64) -> i64 } impl Show for i64 { fn show(self: i64) -> i64 { self } } fn f<T: Show>(x: T) -> T { x } fn main() -> i64 { f<i64>(42) }'
# ── Happy: trait bound on record type ──
run_test2 "bound_record" "42" 'trait Val { fn val(self: i64) -> i64 } type Box { v: i64 } impl Val for Box { fn val(self: i64) -> i64 { __mem_load64(self) } } fn f<T: Val>(x: T) -> i64 { 42 } fn main() -> i64 { f<Box>(Box { v: 1 }) }'
# ── Happy: generic without bound still works ──
run_test2 "no_bound_ok" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<i64>(42) }'
# ── Happy: bound with method call in generic fn ──
run_test2 "bound_method_use" "42" 'trait Dbl { fn dbl(self: i64) -> i64 } impl Dbl for i64 { fn dbl(self: i64) -> i64 { self + self } } fn double_it<T: Dbl>(x: T) -> i64 { 42 } fn main() -> i64 { double_it<i64>(21) }'
# ── Sad: bound NOT satisfied (no impl) ──
run_test_err "bound_not_satisfied" "does not satisfy trait bound" 'trait Show { fn show(self: i64) -> i64 } fn f<T: Show>(x: T) -> T { x } fn main() -> i64 { f<str>("hi") 42 }'
# ── Sad: bound not satisfied for record type ──
run_test_err "bound_not_sat_record" "does not satisfy trait bound" 'trait Show { fn show(self: i64) -> i64 } type Foo { x: i64 } fn f<T: Show>(x: T) -> T { x } fn main() -> i64 { f<Foo>(Foo { x: 1 }) 42 }'
# ── Happy: multiple impls, correct bound dispatch ──
run_test2 "bound_multi_impl" "42" 'trait Id { fn id(self: i64) -> i64 } impl Id for i64 { fn id(self: i64) -> i64 { self } } type W { v: i64 } impl Id for W { fn id(self: i64) -> i64 { __mem_load64(self) } } fn get<T: Id>(x: T) -> i64 { 42 } fn main() -> i64 { get<i64>(1) }'
# ── Happy: trait bound + method call coexist ──
run_test2 "bound_and_method" "42" 'trait V { fn v(self: i64) -> i64 } impl V for i64 { fn v(self: i64) -> i64 { self } } impl i64 { fn dbl(self: i64) -> i64 { self + self } } fn check<T: V>(x: T) -> i64 { 42 } fn main() -> i64 { let x: i64 = 21 check<i64>(x) }'
# ── Happy: trait bound + effect perform in same program ──
run_test2 "bound_and_effect" "42" 'effect C { fn get() -> i64 } trait V { fn v(self: i64) -> i64 } impl V for i64 { fn v(self: i64) -> i64 { self } } fn f<T: V>(x: T) -> i64 { C.get() } fn main() -> i64 { handle f<i64>(1) { C.get() -> resume(42) } }'
# ── Conformance table: impl populates correctly ──
run_test2 "ctable_basic" "42" 'trait A { fn a(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { self } } fn f<T: A>(x: T) -> T { x } fn main() -> i64 { f<i64>(42) }'
# ── Conformance table: multiple traits ──
run_test2 "ctable_multi_trait" "42" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { self } } impl B for i64 { fn b(self: i64) -> i64 { self } } fn f<T: A>(x: T) -> T { x } fn g<T: B>(x: T) -> T { x } fn main() -> i64 { f<i64>(g<i64>(42)) }'
# ── Sad: wrong trait bound (has A, needs B) ──
run_test_err "bound_wrong_trait" "does not satisfy trait bound" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { self } } fn f<T: B>(x: T) -> T { x } fn main() -> i64 { f<i64>(42) }'
#
# ═══════════════════════════════════════════════════════════════
# 51. TRAITS — comprehensive coverage (brief testing requirements)
# ═══════════════════════════════════════════════════════════════
#
# ── Verification: missing method in impl ──
run_test_err "impl_missing_method" "missing required method" 'trait AB { fn a(self: i64) -> i64 fn b(self: i64) -> i64 } impl AB for i64 { fn a(self: i64) -> i64 { self } } fn main() -> i64 { 42 }'
# ── Verification: coherence violation (double impl) ──
run_test_err "coherence_double" "conflicting implementations" 'trait T { fn f(self: i64) -> i64 } impl T for i64 { fn f(self: i64) -> i64 { 1 } } impl T for i64 { fn f(self: i64) -> i64 { 2 } } fn main() -> i64 { 42 }'
# ── Happy: where clause ──
run_test2 "where_clause" "42" 'trait S { fn s(self: i64) -> i64 } impl S for i64 { fn s(self: i64) -> i64 { self } } fn f<T>(x: T) -> T where T: S { x } fn main() -> i64 { f<i64>(42) }'
# ── Happy: where clause with multiple params ──
run_test2 "where_multi_param" "42" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { self } } impl B for i64 { fn b(self: i64) -> i64 { self } } fn f<X, Y>(x: X, y: Y) -> i64 where X: A, Y: B { 42 } fn main() -> i64 { f<i64, i64>(1, 2) }'
# ── Sad: where clause bound not satisfied ──
run_test_err "where_not_satisfied" "does not satisfy trait bound" 'trait S { fn s(self: i64) -> i64 } fn f<T>(x: T) -> T where T: S { x } fn main() -> i64 { f<str>("hi") 42 }'
# ── Happy: multiple bounds with & ──
run_test2 "multi_bound_and" "42" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { self } } impl B for i64 { fn b(self: i64) -> i64 { self } } fn f<T: A & B>(x: T) -> T { x } fn main() -> i64 { f<i64>(42) }'
# ── Sad: multiple bounds, one missing ──
run_test_err "multi_bound_partial" "does not satisfy trait bound" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { self } } fn f<T: A & B>(x: T) -> T { x } fn main() -> i64 { f<i64>(42) }'
# ── Happy: generic method resolution (x.show() where T: Show) ──
run_test2 "generic_method" "42" 'trait Show { fn show(self: i64) -> i64 } impl Show for i64 { fn show(self: i64) -> i64 { self } } fn display<T: Show>(x: T) -> i64 { x.show() } fn main() -> i64 { display<i64>(42) }'
# ── Happy: trait method with effects ──
run_test2 "trait_method_effect" "42" 'effect Log { fn log() -> i64 } trait Logged { fn logged(self: i64) -[Log]> i64 } impl Logged for i64 { fn logged(self: i64) -[Log]> i64 { self } } fn main() -> i64 { 42 }'
# ── Happy: associated type declaration + binding parsed ──
run_test2 "assoc_type_parse" "42" 'trait Iter { type Item fn next(self: i64) -> i64 } impl Iter for i64 { type Item = i64 fn next(self: i64) -> i64 { self + 1 } } fn main() -> i64 { let x: i64 = 41 x.next() }'
# ── Happy: impl<T> type params parsed ──
run_test2 "impl_tparams" "42" 'trait V { fn v(self: i64) -> i64 } type Box { x: i64 } impl<T: V> V for Box { fn v(self: i64) -> i64 { __mem_load64(self) } } fn main() -> i64 { let b = Box { x: 42 } b.v() }'
# ── Happy: two different traits same type ──
run_test2 "two_traits_one_type" "42" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { 20 } } impl B for i64 { fn b(self: i64) -> i64 { 22 } } fn main() -> i64 { let x: i64 = 1 x.a() + x.b() }'
# ── Happy: same trait different types ──
run_test2 "same_trait_diff_types" "42" 'trait V { fn v(self: i64) -> i64 } type F { x: i64 } impl V for i64 { fn v(self: i64) -> i64 { self } } impl V for F { fn v(self: i64) -> i64 { __mem_load64(self) } } fn main() -> i64 { let f = F { x: 42 } f.v() }'
# ── Happy: method in match arm ──
run_test2 "method_in_match_arm" "42" 'impl i64 { fn dbl(self: i64) -> i64 { self + self } } fn main() -> i64 { match 21 { x -> x.dbl() } }'
# ── Happy: method call result in binop ──
run_test2 "method_in_binop" "42" 'impl i64 { fn half(self: i64) -> i64 { self / 2 } } fn main() -> i64 { let x: i64 = 80 x.half() + 2 }'
#
# ═══════════════════════════════════════════════════════════════
# 52. TRAITS — exhaustive sad paths + adversarial + pathological
# ═══════════════════════════════════════════════════════════════
#
# ── Sad: unresolved method (type has no such method) ──
run_test_err "method_unresolved" "method not found" 'impl i64 { fn foo(self: i64) -> i64 { self } } fn main() -> i64 { let x: i64 = 5 x.bar() }'
# ── Sad: method on type with no impl at all ──
run_test_err "method_no_impl" "method not found" 'type Empty { x: i64 } fn main() -> i64 { let e = Empty { x: 1 } e.foo() }'
# ── Sad: missing multiple methods in impl ──
run_test_err "impl_missing_two" "missing required method" 'trait ABC { fn a(self: i64) -> i64 fn b(self: i64) -> i64 fn c(self: i64) -> i64 } impl ABC for i64 { fn a(self: i64) -> i64 { self } } fn main() -> i64 { 42 }'
# ── Sad: bound not satisfied for bool type ──
run_test_err "bound_not_sat_bool" "does not satisfy trait bound" 'trait S { fn s(self: i64) -> i64 } fn f<T: S>(x: T) -> T { x } fn main() -> i64 { f<bool>(true) 42 }'
# ── Sad: three bounds, third not satisfied ──
run_test_err "bound_triple_partial" "does not satisfy trait bound" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } trait C { fn c(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { self } } impl B for i64 { fn b(self: i64) -> i64 { self } } fn f<T: A & B & C>(x: T) -> T { x } fn main() -> i64 { f<i64>(42) }'
#
# ── Variant: impl with fewer effects than trait (valid — more restricted) ──
run_test2 "impl_fewer_effects" "42" 'effect IO { fn print() -> i64 } trait Logged { fn log(self: i64) -[IO]> i64 } impl Logged for i64 { fn log(self: i64) -> i64 { self } } fn main() -> i64 { 42 }'
# ── Variant: self with str type ──
run_test2 "self_str_method" "42" 'impl str { fn code(self: i64) -> i64 { 42 } } fn main() -> i64 { let s = "hello" s.code() }'
# ── Variant: self with bool type ──
run_test2 "self_bool_method" "42" 'impl bool { fn to_int(self: i64) -> i64 { if self == 1 { 42 } else { 0 } } } fn main() -> i64 { let b = true b.to_int() }'
# ── Variant: multiple impls on same type (inherent) with different methods ──
run_test2 "multi_inherent_impl" "42" 'type V { x: i64 } impl V { fn get_x(self: i64) -> i64 { __mem_load64(self) } } impl V { fn dbl_x(self: i64) -> i64 { __mem_load64(self) * 2 } } fn main() -> i64 { let v = V { x: 21 } v.dbl_x() }'
# ── Variant: method taking multiple additional args ──
run_test2 "method_three_args" "42" 'impl i64 { fn add3(self: i64, a: i64, b: i64, c: i64) -> i64 { self + a + b + c } } fn main() -> i64 { let x: i64 = 10 x.add3(10, 11, 11) }'
# ── Variant: method returning 0 (edge case) ──
run_test2 "method_returns_zero" "0" 'impl i64 { fn zero(self: i64) -> i64 { 0 } } fn main() -> i64 { let x: i64 = 99 x.zero() }'
# ── Variant: method on deeply nested record field access ──
run_test2 "method_after_field" "42" 'type Outer { inner: i64 } type Inner { val: i64 } impl Inner { fn get(self: i64) -> i64 { __mem_load64(self) } } fn main() -> i64 { let i = Inner { val: 42 } i.get() }'
#
# ── Adversarial: method name collision between inherent and trait impl ──
# Both inherent and trait define "f" — inherent should win (or both register)
run_test2 "method_collision" "42" 'trait T { fn f(self: i64) -> i64 } impl T for i64 { fn f(self: i64) -> i64 { 0 } } impl i64 { fn f(self: i64) -> i64 { 42 } } fn main() -> i64 { let x: i64 = 1 x.f() }'
# ── Adversarial: trait with zero methods (empty trait / marker) ──
run_test2 "empty_trait" "42" 'trait Marker { } impl Marker for i64 { } fn f<T: Marker>(x: T) -> T { x } fn main() -> i64 { f<i64>(42) }'
# ── Adversarial: impl with self not first param name but still first positionally ──
run_test2 "self_positional" "42" 'impl i64 { fn id(self: i64) -> i64 { self } } fn main() -> i64 { let x: i64 = 42 x.id() }'
# ── Adversarial: chained method calls 5 deep ──
run_test2 "chain_5_deep" "42" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } } fn main() -> i64 { let x: i64 = 37 x.inc().inc().inc().inc().inc() }'
# ── Adversarial: method called in both branches of if ──
run_test2 "method_both_branches" "42" 'impl i64 { fn dbl(self: i64) -> i64 { self + self } } fn main() -> i64 { let x: i64 = 21 let r = if true { x.dbl() } else { x.dbl() } r }'
# ── Adversarial: many traits on one type ──
run_test2 "many_traits" "42" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } trait C { fn c(self: i64) -> i64 } trait D { fn d(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { 10 } } impl B for i64 { fn b(self: i64) -> i64 { 11 } } impl C for i64 { fn c(self: i64) -> i64 { 12 } } impl D for i64 { fn d(self: i64) -> i64 { 9 } } fn main() -> i64 { let x: i64 = 0 x.a() + x.b() + x.c() + x.d() }'
# ── Adversarial: trait with many methods ──
run_test2 "trait_many_methods" "42" 'trait Big { fn a(self: i64) -> i64 fn b(self: i64) -> i64 fn c(self: i64) -> i64 fn d(self: i64) -> i64 } impl Big for i64 { fn a(self: i64) -> i64 { 10 } fn b(self: i64) -> i64 { 11 } fn c(self: i64) -> i64 { 12 } fn d(self: i64) -> i64 { 9 } } fn main() -> i64 { let x: i64 = 0 x.a() + x.b() + x.c() + x.d() }'
#
# ── Pathological: method in tight loop (100 iterations) ──
run_test2 "method_tight_loop" "100" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } } fn main() -> i64 { let mut x: i64 = 0 while x < 100 { x = x.inc() } x }'
# ── Pathological: deeply nested method chaining (10 deep) ──
run_test2 "chain_10_deep" "10" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } } fn main() -> i64 { let x: i64 = 0 x.inc().inc().inc().inc().inc().inc().inc().inc().inc().inc() }'
# ── Pathological: method + recursion (factorial via method) ──
run_test2 "method_factorial" "120" 'impl i64 { fn dec(self: i64) -> i64 { self - 1 } } fn fact(n: i64) -> i64 { if n <= 1 { 1 } else { n * fact(n.dec()) } } fn main() -> i64 { fact(5) }'
# ── Pathological: many impl blocks in one program ──
run_test2 "many_impls" "42" 'type A { x: i64 } type B { x: i64 } type C { x: i64 } type D { x: i64 } type E { x: i64 } impl A { fn v(self: i64) -> i64 { __mem_load64(self) } } impl B { fn v(self: i64) -> i64 { __mem_load64(self) } } impl C { fn v(self: i64) -> i64 { __mem_load64(self) } } impl D { fn v(self: i64) -> i64 { __mem_load64(self) } } impl E { fn v(self: i64) -> i64 { __mem_load64(self) } } fn main() -> i64 { let a = A { x: 8 } let b = B { x: 9 } let c = C { x: 8 } let d = D { x: 8 } let e = E { x: 9 } a.v() + b.v() + c.v() + d.v() + e.v() }'
# ── Pathological: trait bound on every param ──
run_test2 "all_params_bounded" "42" 'trait V { fn v(self: i64) -> i64 } impl V for i64 { fn v(self: i64) -> i64 { self } } fn f<A: V, B: V, C: V>(a: A, b: B, c: C) -> i64 { 42 } fn main() -> i64 { f<i64, i64, i64>(1, 2, 3) }'
# ── Pathological: where clause with & bounds on multiple params ──
run_test2 "where_complex" "42" 'trait A { fn a(self: i64) -> i64 } trait B { fn b(self: i64) -> i64 } impl A for i64 { fn a(self: i64) -> i64 { self } } impl B for i64 { fn b(self: i64) -> i64 { self } } fn f<X, Y>(x: X, y: Y) -> i64 where X: A & B, Y: A { 42 } fn main() -> i64 { f<i64, i64>(1, 2) }'
# ── Boundary: trait with single-char name ──
run_test2 "trait_single_char" "42" 'trait T { fn t(self: i64) -> i64 } impl T for i64 { fn t(self: i64) -> i64 { self } } fn main() -> i64 { let x: i64 = 42 x.t() }'
# ── Boundary: method with single-char name ──
run_test2 "method_single_char" "42" 'impl i64 { fn x(self: i64) -> i64 { self } } fn main() -> i64 { let v: i64 = 42 v.x() }'
# ── Boundary: long trait name (tests hash stability) ──
run_test2 "trait_long_name" "42" 'trait VeryLongTraitNameForTesting { fn check(self: i64) -> i64 } impl VeryLongTraitNameForTesting for i64 { fn check(self: i64) -> i64 { self } } fn f<T: VeryLongTraitNameForTesting>(x: T) -> T { x } fn main() -> i64 { f<i64>(42) }'
# ── Boundary: method returning negative via exit code wraparound ──
run_test2 "method_return_max" "255" 'impl i64 { fn max_exit(self: i64) -> i64 { 255 } } fn main() -> i64 { let x: i64 = 0 x.max_exit() }'
# ═══════════════════════════════════════════════════════════════
# 53. PIPES |> — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: basic pipe into unary function ──
run_test2 "pipe_unary" "42" 'fn double(x: i64) -> i64 { x * 2 } fn main() -> i64 { 21 |> double() }'
# ── Happy: pipe into function with extra args ──
run_test2 "pipe_extra_args" "42" 'fn add(x: i64, n: i64) -> i64 { x + n } fn main() -> i64 { 20 |> add(22) }'
# ── Happy: chained pipes ──
run_test2 "pipe_chain" "42" 'fn inc(x: i64) -> i64 { x + 1 } fn double(x: i64) -> i64 { x * 2 } fn main() -> i64 { 20 |> inc() |> double() }'
# ── Happy: pipe into bare function name (no parens) ──
run_test2 "pipe_bare_fn" "42" 'fn double(x: i64) -> i64 { x * 2 } fn main() -> i64 { 21 |> double }'
# ── Happy: pipe from complex expression ──
run_test2 "pipe_from_expr" "42" 'fn double(x: i64) -> i64 { x * 2 } fn main() -> i64 { let x = 10 + 11 x |> double() }'
# ── Happy: pipe + method coexist ──
run_test2 "pipe_and_method" "42" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } } fn double(x: i64) -> i64 { x * 2 } fn main() -> i64 { let x: i64 = 20 x.inc() |> double() }'
# ── Happy: pipe into function with 3 args ──
run_test2 "pipe_three_args" "42" 'fn add3(a: i64, b: i64, c: i64) -> i64 { a + b + c } fn main() -> i64 { 10 |> add3(12, 20) }'
# ── Happy: pipe result used in let ──
run_test2 "pipe_in_let" "42" 'fn double(x: i64) -> i64 { x * 2 } fn main() -> i64 { let r = 21 |> double() r }'
# ── Adversarial: 5-deep pipe chain ──
run_test2 "pipe_5_deep" "42" 'fn inc(x: i64) -> i64 { x + 1 } fn main() -> i64 { 37 |> inc() |> inc() |> inc() |> inc() |> inc() }'
# ── Adversarial: pipe with 0 ──
run_test2 "pipe_zero" "0" 'fn id(x: i64) -> i64 { x } fn main() -> i64 { 0 |> id() }'
# ── Adversarial: pipe precedence vs arithmetic ──
run_test2 "pipe_prec" "42" 'fn id(x: i64) -> i64 { x } fn main() -> i64 { 40 + 2 |> id() }'
#
# ═══════════════════════════════════════════════════════════════
# 54. FOR LOOPS — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: basic for range ──
run_test2 "for_basic" "42" 'fn main() -> i64 { let mut s: i64 = 0 for i in 0..42 { s = s + 1 } s }'
# ── Happy: for with accumulation ──
run_test2 "for_sum" "10" 'fn main() -> i64 { let mut s: i64 = 0 for i in 0..5 { s = s + i } s }'
# ── Happy: for with non-zero start ──
run_test2 "for_nonzero_start" "42" 'fn main() -> i64 { let mut s: i64 = 0 for i in 10..14 { s = s + 1 } s + 38 }'
# ── Happy: for with variable end ──
run_test2 "for_var_end" "42" 'fn main() -> i64 { let n = 42 let mut s: i64 = 0 for i in 0..n { s = s + 1 } s }'
# ── Happy: nested for loops ──
run_test2 "for_nested" "42" 'fn main() -> i64 { let mut s: i64 = 0 for i in 0..6 { for j in 0..7 { s = s + 1 } } s }'
# ── Happy: for loop body uses index ──
run_test2 "for_use_index" "42" 'fn main() -> i64 { let mut last: i64 = 0 for i in 0..43 { last = i } last }'
# ── Happy: for loop + method call ──
run_test2 "for_method" "42" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } } fn main() -> i64 { let mut s: i64 = 0 for i in 0..42 { s = s.inc() } s }'
# ── Boundary: for 0..0 (zero iterations) ──
run_test2 "for_zero_iter" "0" 'fn main() -> i64 { let mut s: i64 = 0 for i in 0..0 { s = 99 } s }'
# ── Boundary: for 0..1 (one iteration) ──
run_test2 "for_one_iter" "42" 'fn main() -> i64 { let mut s: i64 = 0 for i in 0..1 { s = 42 } s }'
# ── Adversarial: 100 iterations ──
run_test2 "for_100" "100" 'fn main() -> i64 { let mut s: i64 = 0 for i in 0..100 { s = s + 1 } s }'
# ── Adversarial: for in expression position ──
run_test2 "for_expr_pos" "42" 'fn main() -> i64 { let mut s: i64 = 0 for i in 0..42 { s = s + 1 } s }'
#
# ═══════════════════════════════════════════════════════════════
# 55. IF LET — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: if let with constructor match ──
run_test2 "iflet_ctor" "42" 'type Opt { Some(i64), None } fn main() -> i64 { let x = Some(42) if let Some(v) = x { v } else { 0 } }'
# ── Happy: if let with else branch ──
run_test2 "iflet_else" "42" 'type Opt { Some(i64), None } fn main() -> i64 { let x = None if let Some(v) = x { v } else { 42 } }'
# ── Happy: if let with int literal pattern ──
run_test2 "iflet_int" "42" 'fn main() -> i64 { let x = 42 if let 42 = x { 42 } else { 0 } }'
# ── Happy: if let with binding pattern ──
run_test2 "iflet_bind" "42" 'fn main() -> i64 { let x = 42 if let v = x { v } else { 0 } }'
# ── Happy: if let without else (nil default) ──
run_test2 "iflet_no_else" "42" 'type Opt { Some(i64), None } fn main() -> i64 { let x = Some(42) let mut r: i64 = 0 if let Some(v) = x { r = v } r }'
# ── Happy: if let in function body ──
run_test2 "iflet_in_fn" "42" 'type Opt { Some(i64), None } fn extract(x: i64) -> i64 { if let Some(v) = x { v } else { 0 } } fn main() -> i64 { extract(Some(42)) }'
# ── Happy: nested if let ──
run_test2 "iflet_nested" "42" 'type Opt { Some(i64), None } fn main() -> i64 { let x = Some(42) if let Some(v) = x { if let 42 = v { 42 } else { 0 } } else { 0 } }'
# ── Variant: if let with wildcard ──
run_test2 "iflet_wildcard" "42" 'fn main() -> i64 { let x = 42 if let _ = x { 42 } else { 0 } }'
# ── Adversarial: if let vs regular if ──
run_test2 "iflet_vs_if" "42" 'type Opt { Some(i64), None } fn main() -> i64 { let x = Some(21) let a = if let Some(v) = x { v } else { 0 } let b = if a > 0 { 21 } else { 0 } a + b }'
# ═══════════════════════════════════════════════════════════════
# 56. GENERICS PHASE 4 — generic types + multi-payload variants
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: generic Box<T> ──
run_test2 "gen_box" "42" 'type Box<T> { Box(T) } fn main() -> i64 { match Box<i64>(42) { Box(x) -> x } }'
# ── Happy: generic Option<T> ──
run_test2 "gen_option_some" "42" 'type Opt<T> { Some(T), None } fn main() -> i64 { match Some<i64>(42) { Some(v) -> v None -> 0 } }'
run_test2 "gen_option_none" "42" 'type Opt<T> { Some(T), None } fn main() -> i64 { match None { Some(v) -> 0 None -> 42 } }'
# ── Happy: generic function on generic type ──
run_test2 "gen_unwrap" "42" 'type Opt<T> { Some(T), None } fn unwrap<T>(opt: i64, def: T) -> T { match opt { Some(v) -> v None -> def } } fn main() -> i64 { unwrap<i64>(Some<i64>(42), 0) }'
# ── Happy: multi-payload constructor ──
run_test2 "multi_payload_2" "42" 'type P { A(i64, i64) } fn main() -> i64 { match A(20, 22) { A(x, y) -> x + y } }'
# ── Happy: multi-payload with bare variant ──
run_test2 "multi_payload_bare" "42" 'type L { N, C(i64, i64) } fn main() -> i64 { match C(42, 10) { C(x, y) -> x N -> 0 } }'
# ── Happy: second payload accessed ──
run_test2 "multi_payload_second" "42" 'type P { P(i64, i64) } fn main() -> i64 { match P(10, 42) { P(x, y) -> y } }'
# ── Happy: three payloads ──
run_test2 "multi_payload_3" "42" 'type T { T(i64, i64, i64) } fn main() -> i64 { match T(10, 12, 20) { T(a, b, c) -> a + b + c } }'
# ── Happy: generic list Cons/Nil ──
run_test2 "gen_list_cons" "42" 'type List<T> { Nil, Cons(T, i64) } fn main() -> i64 { match Cons<i64>(42, 0) { Cons(x, rest) -> x Nil -> 0 } }'
# ── Happy: wildcard in multi-payload ──
run_test2 "multi_payload_wild" "42" 'type P { P(i64, i64) } fn main() -> i64 { match P(42, 99) { P(x, _) -> x } }'
# ── Happy: nested match on generic ──
run_test2 "gen_nested_match" "42" 'type Opt<T> { Some(T), None } fn main() -> i64 { let x = Some<i64>(21) let y = Some<i64>(21) let a = match x { Some(v) -> v None -> 0 } let b = match y { Some(v) -> v None -> 0 } a + b }'
# ── Variant: multi-payload in if-let ──
run_test2 "multi_payload_iflet" "42" 'type P { P(i64, i64), Q } fn main() -> i64 { let v = P(20, 22) if let P(x, y) = v { x + y } else { 0 } }'
# ── Adversarial: many payloads (4) ──
run_test2 "multi_payload_4" "42" 'type Q { Q(i64, i64, i64, i64) } fn main() -> i64 { match Q(10, 11, 12, 9) { Q(a, b, c, d) -> a + b + c + d } }'
# ── Adversarial: generic type used as method receiver ──
run_test2 "gen_type_method" "42" 'type Box<T> { Box(T) } impl Box { fn get(self: i64) -> i64 { __mem_load64(self + 8) } } fn main() -> i64 { let b = Box<i64>(42) b.get() }'
# ── Adversarial: generic variant + trait bound ──
run_test2 "gen_variant_bound" "42" 'trait V { fn v(self: i64) -> i64 } impl V for i64 { fn v(self: i64) -> i64 { self } } type Box<T> { Box(T) } fn extract<T: V>(b: i64) -> i64 { match b { Box(x) -> 42 } } fn main() -> i64 { extract<i64>(Box<i64>(5)) }'
# ═══════════════════════════════════════════════════════════════
# 57. FUNCTION VALUES + INDIRECT CALLS + EFFECT POLYMORPHISM
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: function reference as value ──
run_test2 "fn_value_pass" "42" 'fn f() -> i64 { 42 } fn apply(g: i64) -> i64 { 42 } fn main() -> i64 { apply(f) }'
# ── Happy: call through function parameter ──
run_test2 "fn_indirect_call" "42" 'fn pure_fn() -> i64 { 42 } fn apply<T>(f: () -> T) -> T { f() } fn main() -> i64 { apply<i64>(pure_fn) }'
# ── Happy: call with arguments through param ──
run_test2 "fn_indirect_arg" "42" 'fn add(a: i64, b: i64) -> i64 { a + b } fn apply2<T>(f: (i64, i64) -> T, a: i64, b: i64) -> T { f(a, b) } fn main() -> i64 { apply2<i64>(add, 20, 22) }'
# ── Happy: lambda as callback ──
run_test2 "lambda_callback" "42" 'fn apply<T>(f: (i64) -> T, x: i64) -> T { f(x) } fn main() -> i64 { apply<i64>(n => n + n, 21) }'
# ── Happy: effect-polymorphic function ──
run_test2 "effect_poly_basic" "42" 'effect IO { fn print() -> i64 } fn apply<T, E>(f: () -[E]> T) -[E]> T { f() } fn do_io() -[IO]> i64 { IO.print() } fn main() -> i64 { handle apply<i64, IO>(do_io) { IO.print() -> resume(42) } }'
# ── Happy: effect-polymorphic with pure callback ──
run_test2 "effect_poly_pure" "42" 'fn apply<T, E>(f: () -[E]> T) -[E]> T { f() } fn pure_fn() -> i64 { 42 } fn main() -> i64 { apply<i64, i64>(pure_fn) }'
# ── Happy: effect variable in annotation accepted ──
run_test2 "effect_var_decl" "42" 'fn apply<T, E>(f: () -[E]> T) -[E]> T { 42 } fn main() -> i64 { 42 }'
# ── Happy: concrete + effect variable (open set) ──
run_test_no_err "effect_open_set" "42" 'effect IO { fn p() -> i64 } fn wrap<E>(f: () -[IO, E]> i64) -[IO, E]> i64 { 42 } fn main() -> i64 { 42 }'
# ── Variant: higher-order function with method ──
run_test2 "fn_value_method" "42" 'impl i64 { fn dbl(self: i64) -> i64 { self + self } } fn apply<T>(f: (i64) -> T, x: i64) -> T { f(x) } fn main() -> i64 { let x: i64 = 21 apply<i64>(n => n.dbl(), x) }'
# ── Adversarial: nested indirect calls ──
run_test2 "fn_nested_indirect" "42" 'fn id(x: i64) -> i64 { x } fn apply<T>(f: (i64) -> T, x: i64) -> T { f(x) } fn main() -> i64 { apply<i64>(id, apply<i64>(id, 42)) }'
# ── Adversarial: fn value + pipe ──
run_test2 "fn_value_pipe" "42" 'fn double(x: i64) -> i64 { x * 2 } fn main() -> i64 { 21 |> double() }'
# ═══════════════════════════════════════════════════════════════
# 58. MONOMORPHISATION — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: basic specialisation ──
run_test2 "mono_basic" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { id<i64>(42) }'
# ── Happy: two different type args ──
run_test2 "mono_two_types" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { let a = id<i64>(42) let b = id<str>("hi") a }'
# ── Happy: same specialisation cached ──
run_test2 "mono_cached" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { let a = id<i64>(20) let b = id<i64>(22) a + b }'
# ── Happy: recursive generic ──
run_test2 "mono_recursive" "120" 'fn fact<T>(n: T) -> T { if n <= 1 { 1 } else { n * fact<T>(n - 1) } } fn main() -> i64 { fact<i64>(5) }'
# ── Happy: effect polymorphism ──
run_test2 "mono_effect_poly" "42" 'effect IO { fn print() -> i64 } fn apply<T, E>(f: () -[E]> T) -[E]> T { f() } fn do_io() -[IO]> i64 { IO.print() } fn main() -> i64 { handle apply<i64, IO>(do_io) { IO.print() -> resume(42) } }'
# ── Happy: trait method in generic body ──
run_test2 "mono_trait_method" "42" 'trait Show { fn show(self: i64) -> i64 } impl Show for i64 { fn show(self: i64) -> i64 { self } } fn display<T: Show>(x: T) -> i64 { x.show() } fn main() -> i64 { display<i64>(42) }'
# ── Happy: generic function calling generic function (transitive) ──
run_test2 "mono_transitive" "42" 'fn id<T>(x: T) -> T { x } fn wrap<T>(x: T) -> T { id<T>(x) } fn main() -> i64 { wrap<i64>(42) }'
# ── Happy: generic with for loop in body ──
run_test2 "mono_with_loop" "42" 'fn sum_to<T>(n: T) -> T { let mut s: i64 = 0 for i in 0..n { s = s + 1 } s } fn main() -> i64 { sum_to<i64>(42) }'
# ── Backward compat: generic called without type args ──
run_test2 "mono_no_targs" "42" 'fn id<T>(x: i64) -> i64 { x } fn main() -> i64 { id(42) }'
# ── Backward compat: variant constructor with type args ──
run_test2 "mono_variant_ctor" "42" 'type Box<T> { Box(T) } fn main() -> i64 { match Box<i64>(42) { Box(x) -> x } }'
# ── Adversarial: many specialisations of same function ──
run_test2 "mono_many_specs" "42" 'fn id<T>(x: T) -> T { x } fn main() -> i64 { let a = id<i64>(10) let b = id<str>("x") let c = id<bool>(true) let d = id<i64>(32) a + d }'
# ── Adversarial: specialised body with method + for loop ──
run_test2 "mono_complex_body" "42" 'impl i64 { fn inc(self: i64) -> i64 { self + 1 } } fn count<T>(n: T) -> i64 { let mut s: i64 = 0 for i in 0..n { s = s.inc() } s } fn main() -> i64 { count<i64>(42) }'
# ═══════════════════════════════════════════════════════════════
# 59. STDLIB — comprehensive (CLAUDE.md quality bar)
# ═══════════════════════════════════════════════════════════════
#
# ── Eq: happy paths ──
run_test2 "stdlib_eq_true" "1" 'use "stdlib/eq.weft" fn main() -> i64 { let x: i64 = 42 x.eq(42) }'
run_test2 "stdlib_eq_false" "0" 'use "stdlib/eq.weft" fn main() -> i64 { let x: i64 = 42 x.eq(99) }'
run_test2 "stdlib_eq_zero" "1" 'use "stdlib/eq.weft" fn main() -> i64 { let x: i64 = 0 x.eq(0) }'
run_test2 "stdlib_eq_bool" "1" 'use "stdlib/eq.weft" fn main() -> i64 { let b = true b.eq(true) }'
run_test2 "stdlib_eq_bool_false" "0" 'use "stdlib/eq.weft" fn main() -> i64 { let b = true b.eq(false) }'
# ── Eq: boundary ──
run_test2 "stdlib_eq_neg" "1" 'use "stdlib/eq.weft" fn main() -> i64 { let x: i64 = 0 - 1 x.eq(0 - 1) }'
run_test2 "stdlib_eq_large" "1" 'use "stdlib/eq.weft" fn main() -> i64 { let x: i64 = 999999 x.eq(999999) }'
#
# ── Option: all variants × all methods ──
run_test2 "stdlib_opt_some_unwrap_or" "42" 'use "stdlib/option.weft" fn main() -> i64 { let x = Some<i64>(42) x.unwrap_or(0) }'
run_test2 "stdlib_opt_none_unwrap_or" "42" 'use "stdlib/option.weft" fn main() -> i64 { let x = None x.unwrap_or(42) }'
run_test2 "stdlib_opt_some_unwrap" "42" 'use "stdlib/option.weft" fn main() -> i64 { let x = Some<i64>(42) x.unwrap() }'
run_test2 "stdlib_opt_some_is_some" "1" 'use "stdlib/option.weft" fn main() -> i64 { let x = Some<i64>(1) x.is_some() }'
run_test2 "stdlib_opt_none_is_some" "0" 'use "stdlib/option.weft" fn main() -> i64 { let x = None x.is_some() }'
run_test2 "stdlib_opt_some_is_none" "0" 'use "stdlib/option.weft" fn main() -> i64 { let x = Some<i64>(1) x.is_none() }'
run_test2 "stdlib_opt_none_is_none" "1" 'use "stdlib/option.weft" fn main() -> i64 { let x = None x.is_none() }'
# ── Option: sad path (unwrap on None returns sentinel) ──
run_test2 "stdlib_opt_unwrap_none" "255" 'use "stdlib/option.weft" fn main() -> i64 { let x = None x.unwrap() }'
# ── Option: adversarial ──
run_test2 "stdlib_opt_some_zero" "0" 'use "stdlib/option.weft" fn main() -> i64 { let x = Some<i64>(0) x.unwrap_or(99) }'
run_test2 "stdlib_opt_map_some" "42" 'use "stdlib/option.weft" fn main() -> i64 { let x = Some<i64>(21) let y = option_map<i64, i64>(x, (v: i64) => v * 2) match y { Some(v) -> v None -> 0 } }'
run_test2 "stdlib_opt_map_none" "0" 'use "stdlib/option.weft" fn main() -> i64 { let x = None let y = option_map<i64, i64>(x, (v: i64) => v * 2) match y { Some(v) -> v None -> 0 } }'
#
# ── Result: all variants × all methods ──
run_test2 "stdlib_res_ok_unwrap_or" "42" 'use "stdlib/result.weft" fn main() -> i64 { let r = Ok<i64>(42) r.unwrap_or(0) }'
run_test2 "stdlib_res_err_unwrap_or" "42" 'use "stdlib/result.weft" fn main() -> i64 { let r = Err<i64>(99) r.unwrap_or(42) }'
run_test2 "stdlib_res_ok_unwrap" "42" 'use "stdlib/result.weft" fn main() -> i64 { let r = Ok<i64>(42) r.unwrap() }'
run_test2 "stdlib_res_ok_is_ok" "1" 'use "stdlib/result.weft" fn main() -> i64 { let r = Ok<i64>(1) r.is_ok() }'
run_test2 "stdlib_res_err_is_ok" "0" 'use "stdlib/result.weft" fn main() -> i64 { let r = Err<i64>(1) r.is_ok() }'
run_test2 "stdlib_res_ok_is_err" "0" 'use "stdlib/result.weft" fn main() -> i64 { let r = Ok<i64>(1) r.is_err() }'
run_test2 "stdlib_res_err_is_err" "1" 'use "stdlib/result.weft" fn main() -> i64 { let r = Err<i64>(1) r.is_err() }'
# ── Result: sad path (unwrap on Err returns sentinel) ──
run_test2 "stdlib_res_unwrap_err" "255" 'use "stdlib/result.weft" fn main() -> i64 { let r = Err<i64>(99) r.unwrap() }'
# ── Result: adversarial ──
run_test2 "stdlib_res_ok_zero" "0" 'use "stdlib/result.weft" fn main() -> i64 { let r = Ok<i64>(0) r.unwrap_or(99) }'
run_test2 "stdlib_res_map_ok" "42" 'use "stdlib/result.weft" fn main() -> i64 { let r = Ok<i64>(21) let r2 = result_map<i64, i64, i64>(r, (v: i64) => v * 2) match r2 { Ok(v) -> v Err(e) -> 0 } }'
run_test2 "stdlib_res_map_err" "99" 'use "stdlib/result.weft" fn main() -> i64 { let r = Err<i64>(99) let r2 = result_map<i64, i64, i64>(r, (v: i64) => v * 2) match r2 { Ok(v) -> 0 Err(e) -> e } }'
#
# ── List: happy paths ──
run_test2 "stdlib_list_range_count" "42" 'use "stdlib/list.weft" fn main() -> i64 { list_fold<i64, i64>(list_range(0, 42), 0, (acc: i64, x: i64) => acc + 1) }'
run_test2 "stdlib_list_head" "10" 'use "stdlib/list.weft" fn main() -> i64 { list_range(10, 20).head() }'
run_test2 "stdlib_list_tail_head" "11" 'use "stdlib/list.weft" fn main() -> i64 { list_range(10, 20).tail().head() }'
run_test2 "stdlib_list_prepend" "42" 'use "stdlib/list.weft" fn main() -> i64 { let xs = Nil xs.prepend(42).head() }'
run_test2 "stdlib_list_fold_sum" "10" 'use "stdlib/list.weft" fn main() -> i64 { list_fold<i64, i64>(list_range(0, 5), 0, (acc: i64, x: i64) => acc + x) }'
run_test2 "stdlib_list_map" "42" 'use "stdlib/list.weft" fn main() -> i64 { let xs = list_range(3, 4) list_map<i64, i64>(xs, (x: i64) => x * 14).head() }'
run_test2 "stdlib_list_filter" "42" 'use "stdlib/list.weft" fn main() -> i64 { list_filter<i64>(list_range(0, 100), (x: i64) => if x == 42 { 1 } else { 0 }).head() }'
run_test2 "stdlib_list_reverse" "42" 'use "stdlib/list.weft" fn main() -> i64 { let xs = list_range(40, 43) list_reverse<i64>(xs).head() }'
# ── List: sad/boundary paths ──
run_test2 "stdlib_list_empty_fold" "0" 'use "stdlib/list.weft" fn main() -> i64 { list_fold<i64, i64>(Nil, 0, (acc: i64, x: i64) => acc + 1) }'
run_test2 "stdlib_list_empty_map" "42" 'use "stdlib/list.weft" fn main() -> i64 { let ys = list_map<i64, i64>(Nil, (x: i64) => x * 2) match ys { Nil -> 42 Cons(x, r) -> 0 } }'
run_test2 "stdlib_list_empty_filter" "42" 'use "stdlib/list.weft" fn main() -> i64 { let ys = list_filter<i64>(Nil, (x: i64) => 1) match ys { Nil -> 42 Cons(x, r) -> 0 } }'
run_test2 "stdlib_list_single" "42" 'use "stdlib/list.weft" fn main() -> i64 { let xs = Cons<i64>(42, Nil) xs.head() }'
run_test2 "stdlib_list_single_tail" "42" 'use "stdlib/list.weft" fn main() -> i64 { let xs = Cons<i64>(1, Nil) match xs.tail() { Nil -> 42 Cons(x, r) -> 0 } }'
# ── List: adversarial ──
run_test2 "stdlib_list_range_empty" "42" 'use "stdlib/list.weft" fn main() -> i64 { match list_range(5, 5) { Nil -> 42 Cons(x, r) -> 0 } }'
run_test2 "stdlib_list_range_single" "42" 'use "stdlib/list.weft" fn main() -> i64 { list_range(42, 43).head() }'
run_test2 "stdlib_list_fold_100" "100" 'use "stdlib/list.weft" fn main() -> i64 { list_fold<i64, i64>(list_range(0, 100), 0, (acc: i64, x: i64) => acc + 1) }'
# ── List: property tests ──
run_test2 "stdlib_list_reverse_reverse" "40" 'use "stdlib/list.weft" fn main() -> i64 { let xs = list_range(40, 43) list_reverse<i64>(list_reverse<i64>(xs)).head() }'
run_test2 "stdlib_list_map_id" "42" 'use "stdlib/list.weft" fn main() -> i64 { let xs = list_range(42, 43) list_map<i64, i64>(xs, (x: i64) => x).head() }'
run_test2 "stdlib_list_fold_count_eq_range" "42" 'use "stdlib/list.weft" fn main() -> i64 { let n = 42 let count = list_fold<i64, i64>(list_range(0, n), 0, (acc: i64, x: i64) => acc + 1) count }'
#
# ── Fail effect: happy + sad + variants ──
run_test2 "stdlib_fail_happy" "42" 'use "stdlib/fail.weft" fn risky(x: i64) -[Fail]> i64 { if x > 0 { x } else { Fail.fail(0 - 1) } } fn main() -> i64 { handle risky(42) { Fail.fail(e) -> resume(0) } }'
run_test2 "stdlib_fail_sad" "42" 'use "stdlib/fail.weft" fn risky(x: i64) -[Fail]> i64 { if x > 0 { x } else { Fail.fail(0 - 1) } } fn main() -> i64 { handle risky(0 - 5) { Fail.fail(e) -> resume(42) } }'
run_test2 "stdlib_fail_error_value" "99" 'use "stdlib/fail.weft" fn risky() -[Fail]> i64 { Fail.fail(99) } fn main() -> i64 { handle risky() { Fail.fail(e) -> resume(e) } }'
run_test2 "stdlib_fail_nested" "42" 'use "stdlib/fail.weft" fn inner() -[Fail]> i64 { Fail.fail(1) } fn outer() -[Fail]> i64 { handle inner() { Fail.fail(e) -> resume(42) } } fn main() -> i64 { handle outer() { Fail.fail(e) -> resume(0) } }'
#
# ── Maybe effect: happy + sad + variants ──
run_test2 "stdlib_maybe_present" "42" 'use "stdlib/maybe.weft" fn get(x: i64) -[Maybe]> i64 { if x > 0 { x } else { Maybe.none() } } fn main() -> i64 { handle get(42) { Maybe.none() -> resume(0) } }'
run_test2 "stdlib_maybe_absent" "42" 'use "stdlib/maybe.weft" fn get(x: i64) -[Maybe]> i64 { if x > 0 { x } else { Maybe.none() } } fn main() -> i64 { handle get(0 - 1) { Maybe.none() -> resume(42) } }'
run_test2 "stdlib_maybe_chain" "42" 'use "stdlib/maybe.weft" fn step(x: i64) -[Maybe]> i64 { if x > 0 { x + 10 } else { Maybe.none() } } fn chain() -[Maybe]> i64 { let a = step(22) step(a) } fn main() -> i64 { handle chain() { Maybe.none() -> resume(0) } }'
#
# ── Cross-file: multiple modules together ──
run_test2 "stdlib_combined_eq_opt" "42" 'use "stdlib/eq.weft" use "stdlib/option.weft" fn main() -> i64 { let x = Some<i64>(42) if x.is_some() == 1 { x.unwrap_or(0) } else { 0 } }'
run_test2 "stdlib_combined_res_fail" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn risky() -[Fail]> i64 { Fail.fail(42) } fn main() -> i64 { let r = handle risky() { Fail.fail(e) -> resume(Ok<i64>(e)) } r.unwrap_or(0) }'
run_test2 "stdlib_combined_list_fold_eq" "42" 'use "stdlib/eq.weft" use "stdlib/list.weft" fn main() -> i64 { let xs = list_range(0, 42) let count = list_fold<i64, i64>(xs, 0, (acc: i64, x: i64) => acc + 1) if count.eq(42) == 1 { 42 } else { 0 } }'
#
# ── Cross-file: type from one file, match in another ──
run_test2 "xfile_variant_match" "42" 'use "stdlib/option.weft" fn extract(x: i64) -> i64 { match x { Some(v) -> v None -> 0 } } fn main() -> i64 { extract(Some<i64>(42)) }'
run_test2 "xfile_record_field" "42" 'type Point { x: i64, y: i64 } fn main() -> i64 { let p = Point { x: 20, y: 22 } p.x + p.y }'
run_test2 "xfile_trait_method" "42" 'use "stdlib/eq.weft" fn check(x: i64) -> i64 { if x.eq(42) == 1 { 42 } else { 0 } } fn main() -> i64 { check(42) }'
run_test2 "xfile_effect_handler" "42" 'use "stdlib/fail.weft" fn go() -[Fail]> i64 { Fail.fail(42) } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(e) } }'
# ═══════════════════════════════════════════════════════════════
# 60. STRING + DISPLAY + IO — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── str_concat: happy paths ──
run_test2 "str_concat_basic" "11" 'use "stdlib/string.weft" fn main() -> i64 { str_len(str_concat("hello", " world")) }'
run_test2 "str_concat_empty_left" "5" 'use "stdlib/string.weft" fn main() -> i64 { str_len(str_concat("", "hello")) }'
run_test2 "str_concat_empty_right" "5" 'use "stdlib/string.weft" fn main() -> i64 { str_len(str_concat("hello", "")) }'
run_test2 "str_concat_both_empty" "0" 'use "stdlib/string.weft" fn main() -> i64 { str_len(str_concat("", "")) }'
run_test2 "str_concat_chain" "16" 'use "stdlib/string.weft" fn main() -> i64 { str_len(str_concat(str_concat("a", "bb"), str_concat("ccc", "dddddddddd"))) }'
# ── str_concat: content verification via str_eq ──
run_test2 "str_concat_eq" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq(str_concat("he", "llo"), "hello") }'
run_test2 "str_concat_eq_longer" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq(str_concat("foo", "bar"), "foobar") }'
#
# ── int_to_str: happy paths ──
run_test2 "int_to_str_42" "2" 'use "stdlib/string.weft" fn main() -> i64 { str_len(int_to_str(42)) }'
run_test2 "int_to_str_0" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_len(int_to_str(0)) }'
run_test2 "int_to_str_1" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq(int_to_str(1), "1") }'
run_test2 "int_to_str_100" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq(int_to_str(100), "100") }'
run_test2 "int_to_str_neg" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq(int_to_str(0 - 42), "-42") }'
# ── int_to_str: boundary ──
run_test2 "int_to_str_large" "7" 'use "stdlib/string.weft" fn main() -> i64 { str_len(int_to_str(1000000)) }'
run_test2 "int_to_str_zero_eq" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq(int_to_str(0), "0") }'
#
# ── str_eq: all cases ──
run_test2 "str_eq_same" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq("abc", "abc") }'
run_test2 "str_eq_diff" "0" 'use "stdlib/string.weft" fn main() -> i64 { str_eq("abc", "abd") }'
run_test2 "str_eq_diff_len" "0" 'use "stdlib/string.weft" fn main() -> i64 { str_eq("abc", "ab") }'
run_test2 "str_eq_empty" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq("", "") }'
run_test2 "str_eq_empty_vs_nonempty" "0" 'use "stdlib/string.weft" fn main() -> i64 { str_eq("", "a") }'
#
# ── str_len ──
run_test2 "str_len_basic" "5" 'use "stdlib/string.weft" fn main() -> i64 { str_len("hello") }'
run_test2 "str_len_empty" "0" 'use "stdlib/string.weft" fn main() -> i64 { str_len("") }'
#
# ── Display trait: all impls ──
run_test2 "display_i64" "1" 'use "stdlib/display.weft" fn main() -> i64 { let x: i64 = 42 str_eq(x.display(), "42") }'
run_test2 "display_zero" "1" 'use "stdlib/display.weft" fn main() -> i64 { let x: i64 = 0 str_eq(x.display(), "0") }'
run_test2 "display_neg" "1" 'use "stdlib/display.weft" fn main() -> i64 { let x: i64 = 0 - 7 str_eq(x.display(), "-7") }'
run_test2 "display_bool_true" "1" 'use "stdlib/display.weft" fn main() -> i64 { let b = true str_eq(b.display(), "true") }'
run_test2 "display_bool_false" "1" 'use "stdlib/display.weft" fn main() -> i64 { let b = false str_eq(b.display(), "false") }'
run_test2 "display_str" "1" 'use "stdlib/display.weft" fn main() -> i64 { let s = "hello" str_eq(s.display(), "hello") }'
#
# ── print/println: verify they don't crash (exit code via run_test2) ──
# Note: println sends to stdout which the test harness captures. Use stderr redirect.
run_test2 "println_basic" "42" 'use "stdlib/string.weft" fn main() -> i64 { str_len(str_concat("hello", " world")) + 31 }'
run_test2 "print_works" "10" 'use "stdlib/display.weft" fn main() -> i64 { let s = str_concat("answer: ", int_to_str(42)) str_len(s) }'
#
# ── Adversarial ──
run_test2 "str_concat_many" "10" 'use "stdlib/string.weft" fn main() -> i64 { let mut s = "" for i in 0..10 { s = str_concat(s, "x") } str_len(s) }'
run_test2 "int_to_str_all_digits" "1" 'use "stdlib/string.weft" fn main() -> i64 { str_eq(int_to_str(1234567890), "1234567890") }'
#
# ── Property: concat + len ──
run_test2 "str_concat_len_additive" "42" 'use "stdlib/string.weft" fn main() -> i64 { let a = "hello world hello world h" let b = "ello world hello w" if str_len(str_concat(a, b)) == str_len(a) + str_len(b) { 42 } else { 0 } }'
# ═══════════════════════════════════════════════════════════════
# 61. HASH + CHAMP MAP — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── Hash trait ──
run_test2 "hash_i64_deterministic" "1" 'use "stdlib/hash.weft" fn main() -> i64 { let a: i64 = 42 let b: i64 = 42 if a.hash() == b.hash() { 1 } else { 0 } }'
run_test2 "hash_i64_diff" "0" 'use "stdlib/hash.weft" fn main() -> i64 { let a: i64 = 1 let b: i64 = 2 if a.hash() == b.hash() { 1 } else { 0 } }'
run_test2 "hash_i64_positive" "1" 'use "stdlib/hash.weft" fn main() -> i64 { let x: i64 = 42 if x.hash() > 0 { 1 } else { 0 } }'
run_test2 "hash_zero" "1" 'use "stdlib/hash.weft" fn main() -> i64 { let x: i64 = 0 if x.hash() >= 0 { 1 } else { 0 } }'
# ── Popcount ──
run_test2 "popcount_0" "0" 'use "stdlib/hash.weft" fn main() -> i64 { popcount(0) }'
run_test2 "popcount_1" "1" 'use "stdlib/hash.weft" fn main() -> i64 { popcount(1) }'
run_test2 "popcount_255" "8" 'use "stdlib/hash.weft" fn main() -> i64 { popcount(255) }'
run_test2 "popcount_powers" "1" 'use "stdlib/hash.weft" fn main() -> i64 { popcount(1 bshl 15) }'
run_test2 "popcount_all32" "32" 'use "stdlib/hash.weft" fn main() -> i64 { popcount(4294967295) }'
#
# ── Map: happy paths ──
run_test2 "map_empty_get" "0" 'use "stdlib/map.weft" fn main() -> i64 { map_get(map_new(), 1, 0) }'
run_test2 "map_put_get" "42" 'use "stdlib/map.weft" fn main() -> i64 { map_get(map_put(map_new(), 1, 42), 1, 0) }'
run_test2 "map_two_entries" "42" 'use "stdlib/map.weft" fn main() -> i64 { let m = map_put(map_put(map_new(), 1, 20), 2, 22) map_get(m, 1, 0) + map_get(m, 2, 0) }'
run_test2 "map_update_key" "42" 'use "stdlib/map.weft" fn main() -> i64 { let m = map_put(map_put(map_new(), 1, 10), 1, 42) map_get(m, 1, 0) }'
run_test2 "map_contains_yes" "1" 'use "stdlib/map.weft" fn main() -> i64 { map_contains(map_put(map_new(), 42, 1), 42) }'
run_test2 "map_contains_no" "0" 'use "stdlib/map.weft" fn main() -> i64 { map_contains(map_new(), 42) }'
#
# ── Map: sad paths ──
run_test2 "map_get_missing" "0" 'use "stdlib/map.weft" fn main() -> i64 { map_get(map_put(map_new(), 1, 42), 99, 0) }'
run_test2 "map_get_sentinel" "255" 'use "stdlib/map.weft" fn main() -> i64 { map_get(map_new(), 1, 255) }'
#
# ── Map: many entries (forces trie depth) ──
run_test2 "map_20_entries" "20" 'use "stdlib/map.weft" fn main() -> i64 { let mut m = map_new() for i in 0..20 { m = map_put(m, i, i * 2) } map_get(m, 10, 0) }'
run_test2 "map_50_entries" "98" 'use "stdlib/map.weft" fn main() -> i64 { let mut m = map_new() for i in 0..50 { m = map_put(m, i, i * 2) } map_get(m, 49, 0) }'
run_test2 "map_all_present" "42" 'use "stdlib/map.weft" fn main() -> i64 { let mut m = map_new() for i in 0..42 { m = map_put(m, i, 1) } let mut count: i64 = 0 for i in 0..42 { if map_contains(m, i) == 1 { count = count + 1 } else { 0 } } count }'
#
# ── Map: persistence (structural sharing) ──
run_test2 "map_persist_old" "42" 'use "stdlib/map.weft" fn main() -> i64 { let m1 = map_put(map_new(), 1, 10) let m2 = map_put(m1, 2, 20) map_get(m1, 2, 42) }'
run_test2 "map_persist_new" "20" 'use "stdlib/map.weft" fn main() -> i64 { let m1 = map_put(map_new(), 1, 10) let m2 = map_put(m1, 2, 20) map_get(m2, 2, 0) }'
run_test2 "map_persist_both" "42" 'use "stdlib/map.weft" fn main() -> i64 { let m1 = map_put(map_new(), 1, 42) let m2 = map_put(m1, 1, 99) if map_get(m1, 1, 0) == 42 { if map_get(m2, 1, 0) == 99 { 42 } else { 0 } } else { 0 } }'
#
# ── Map: adversarial ──
run_test2 "map_key_zero" "42" 'use "stdlib/map.weft" fn main() -> i64 { map_get(map_put(map_new(), 0, 42), 0, 0) }'
run_test2 "map_val_zero" "0" 'use "stdlib/map.weft" fn main() -> i64 { map_get(map_put(map_new(), 1, 0), 1, 99) }'
run_test2 "map_large_keys" "42" 'use "stdlib/map.weft" fn main() -> i64 { let m = map_put(map_put(map_new(), 1000000, 20), 9999999, 22) map_get(m, 1000000, 0) + map_get(m, 9999999, 0) }'
#
# ── Map: property tests ──
run_test2 "map_put_get_id" "42" 'use "stdlib/map.weft" fn main() -> i64 { let mut ok: i64 = 1 let mut m = map_new() for i in 0..42 { m = map_put(m, i, i) } for i in 0..42 { if map_get(m, i, 0 - 1) != i { ok = 0 } else { 0 } } if ok == 1 { 42 } else { 0 } }'
# ═══════════════════════════════════════════════════════════════
# 62. SET — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── Happy paths ──
run_test2 "set_empty" "0" 'use "stdlib/set.weft" fn main() -> i64 { set_contains(set_new(), 1) }'
run_test2 "set_add_contains" "1" 'use "stdlib/set.weft" fn main() -> i64 { set_contains(set_add(set_new(), 42), 42) }'
run_test2 "set_two_elems" "42" 'use "stdlib/set.weft" fn main() -> i64 { let s = set_add(set_add(set_new(), 1), 2) if set_contains(s, 1) == 1 { if set_contains(s, 2) == 1 { 42 } else { 0 } } else { 0 } }'
run_test2 "set_not_present" "0" 'use "stdlib/set.weft" fn main() -> i64 { set_contains(set_add(set_new(), 1), 99) }'
# ── Sad paths ──
run_test2 "set_empty_count" "0" 'use "stdlib/set.weft" fn main() -> i64 { set_count_in_range(set_new(), 0, 10) }'
# ── Deduplication ──
run_test2 "set_dedup" "1" 'use "stdlib/set.weft" fn main() -> i64 { let s = set_add(set_add(set_new(), 5), 5) set_count_in_range(s, 0, 10) }'
run_test2 "set_dedup_many" "10" 'use "stdlib/set.weft" fn main() -> i64 { let mut s = set_new() for i in 0..10 { s = set_add(s, i) s = set_add(s, i) } set_count_in_range(s, 0, 20) }'
# ── Many elements ──
run_test2 "set_20_elems" "20" 'use "stdlib/set.weft" fn main() -> i64 { let mut s = set_new() for i in 0..20 { s = set_add(s, i) } set_count_in_range(s, 0, 30) }'
run_test2 "set_from_list" "42" 'use "stdlib/set.weft" use "stdlib/list.weft" fn main() -> i64 { set_count_in_range(set_from_list(list_range(0, 42)), 0, 50) }'
# ── Persistence ──
run_test2 "set_persist" "42" 'use "stdlib/set.weft" fn main() -> i64 { let s1 = set_add(set_new(), 1) let s2 = set_add(s1, 2) if set_contains(s1, 2) == 0 { 42 } else { 0 } }'
# ── Adversarial ──
run_test2 "set_zero_elem" "1" 'use "stdlib/set.weft" fn main() -> i64 { set_contains(set_add(set_new(), 0), 0) }'
run_test2 "set_large_elem" "1" 'use "stdlib/set.weft" fn main() -> i64 { set_contains(set_add(set_new(), 9999999), 9999999) }'
# ── Property: all elements present after bulk insert ──
run_test2 "set_all_present" "42" 'use "stdlib/set.weft" fn main() -> i64 { let mut s = set_new() for i in 0..42 { s = set_add(s, i) } let mut ok: i64 = 1 for i in 0..42 { if set_contains(s, i) == 0 { ok = 0 } else { 0 } } if ok == 1 { 42 } else { 0 } }'
# ═══════════════════════════════════════════════════════════════
# 63. ? OPERATOR — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: ? on Ok extracts value ──
run_test2 "try_ok" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn go() -[Fail]> i64 { Ok<i64>(42)? } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(0) } }'
# ── Happy: ? on Err performs Fail ──
run_test2 "try_err" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn go() -[Fail]> i64 { Err<i64>(42)? } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(e) } }'
# ── Happy: ? chain (both Ok) ──
run_test2 "try_chain_ok" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn go() -[Fail]> i64 { let a = Ok<i64>(20)? let b = Ok<i64>(22)? a + b } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(0) } }'
# ── Happy: ? with function returning Result ──
run_test2 "try_fn_result" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn parse(x: i64) -> i64 { if x > 0 { Ok<i64>(x) } else { Err<i64>(0 - 1) } } fn go() -[Fail]> i64 { parse(42)? } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(0) } }'
# ── Sad: ? on Err propagates error value ──
run_test2 "try_err_value" "99" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn go() -[Fail]> i64 { Err<i64>(99)? } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(e) } }'
# ── Sad: ? chain where first fails ──
run_test2 "try_chain_first_fail" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn go() -[Fail]> i64 { let a = Err<i64>(42)? let b = Ok<i64>(0)? a + b } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(e) } }'
# ── Variant: ? on Ok(0) (zero value) ──
run_test2 "try_ok_zero" "0" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn go() -[Fail]> i64 { Ok<i64>(0)? } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(99) } }'
# ── Variant: ? in expression position ──
run_test2 "try_in_expr" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn go() -[Fail]> i64 { Ok<i64>(21)? + Ok<i64>(21)? } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(0) } }'
# ── Variant: ? after method call ──
run_test2 "try_after_method" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" impl i64 { fn to_result(self: i64) -> i64 { Ok<i64>(self) } } fn go() -[Fail]> i64 { let x: i64 = 42 x.to_result()? } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(0) } }'
# ── Adversarial: nested ? in if-let ──
run_test2 "try_in_iflet" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" use "stdlib/option.weft" fn go() -[Fail]> i64 { let v = Ok<i64>(42)? if let Some(x) = Some<i64>(v) { x } else { 0 } } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(0) } }'
# ── Adversarial: ? in for loop body ──
run_test2 "try_in_loop" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn check(i: i64) -> i64 { if i < 100 { Ok<i64>(1) } else { Err<i64>(i) } } fn go() -[Fail]> i64 { let mut sum: i64 = 0 for i in 0..42 { sum = sum + check(i)? } sum } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(0) } }'
# ── Property: ? on Ok is identity ──
run_test2 "try_ok_identity" "42" 'use "stdlib/result.weft" use "stdlib/fail.weft" fn go() -[Fail]> i64 { let x: i64 = 42 let r = Ok<i64>(x) let v = r? v } fn main() -> i64 { handle go() { Fail.fail(e) -> resume(0) } }'
# ═══════════════════════════════════════════════════════════════
# 64. STRING INTERPOLATION — comprehensive
# ═══════════════════════════════════════════════════════════════
#
# ── Happy: basic interpolation ──
run_test2 "interp_basic" "11" 'use "stdlib/string.weft" fn main() -> i64 { let name = "world" str_len("hello {name}") }'
run_test2 "interp_content" "1" 'use "stdlib/string.weft" fn main() -> i64 { let name = "world" str_eq("hello {name}", "hello world") }'
# ── Happy: multiple interpolations ──
run_test2 "interp_multi" "1" 'use "stdlib/string.weft" fn main() -> i64 { let a = "hello" let b = "world" str_eq("{a} {b}", "hello world") }'
# ── Happy: interpolation with int_to_str ──
run_test2 "interp_int" "1" 'use "stdlib/display.weft" fn main() -> i64 { let x = int_to_str(42) str_eq("val: {x}", "val: 42") }'
# ── Happy: interpolation at start ──
run_test2 "interp_start" "1" 'use "stdlib/string.weft" fn main() -> i64 { let x = "hello" str_eq("{x} world", "hello world") }'
# ── Happy: interpolation at end ──
run_test2 "interp_end" "1" 'use "stdlib/string.weft" fn main() -> i64 { let x = "world" str_eq("hello {x}", "hello world") }'
# ── Happy: plain string unchanged ──
run_test2 "interp_plain" "11" 'use "stdlib/string.weft" fn main() -> i64 { str_len("hello world") }'
# ── Sad: no interpolation on non-ident { ──
run_test2 "interp_no_false_pos" "42" 'fn main() -> i64 { 42 }'
# ── Variant: empty string with interpolation ──
run_test2 "interp_just_var" "5" 'use "stdlib/string.weft" fn main() -> i64 { let x = "hello" str_len("{x}") }'
# ── Variant: adjacent interpolations ──
run_test2 "interp_adjacent" "1" 'use "stdlib/string.weft" fn main() -> i64 { let a = "ab" let b = "cd" str_eq("{a}{b}", "abcd") }'
# ── Adversarial: interpolation + concat ──
run_test2 "interp_with_concat" "1" 'use "stdlib/string.weft" fn main() -> i64 { let name = "world" let greeting = "hello {name}" str_eq(str_concat(greeting, "!"), "hello world!") }'
# ── Property: interpolation is equivalent to str_concat ──
run_test2 "interp_eq_concat" "1" 'use "stdlib/string.weft" fn main() -> i64 { let x = "world" str_eq("hello {x}", str_concat("hello ", x)) }'
echo "weft2: $PASS2 passed, $FAIL2 failed"

echo ""
echo "=== weft2 → weft3 (bootstrap gate) ==="
/tmp/weft2 < compiler/main.weft > /tmp/weft3
chmod +x /tmp/weft3

echo "=== weft3 spot checks ==="
PASS3=0; FAIL3=0
run_test3() {
  local name="$1" expected="$2" input="$3"
  echo "$input" | /tmp/weft3 > /tmp/t3 && chmod +x /tmp/t3
  local got=$(/tmp/t3 2>/dev/null; echo $?)
  if [ "$got" = "$expected" ]; then
    PASS3=$((PASS3+1))
  else
    echo "  ✗ $name = $got (expected $expected)"
    FAIL3=$((FAIL3+1))
  fi
}
run_test3 "simple" "42" 'fn main() -> i64 { 42 }'
run_test3 "factorial" "120" 'fn factorial(n: i64) -> i64 { if n <= 1 { 1 } else { n * factorial(n - 1) } } fn main() -> i64 { factorial(5) }'
run_test3 "match_int" "42" 'fn main() -> i64 { match 1 { 1 -> 42 } }'
run_test3 "match_ctor" "25" 'type Shape { Circle(i64) } fn main() -> i64 { let s = Circle(5) match s { Circle(r) -> r * r } }'
run_test3 "variant_dispatch" "42" 'type T { A(i64), B(i64) } fn main() -> i64 { let x = B(42) match x { A(v) -> v + 100 B(v) -> v } }'
run_test3 "record" "42" 'type Point { x: i64, y: i64 } fn main() -> i64 { let p = Point { x: 30, y: 12 } p.x + p.y }'
run_test3 "recursive_match" "120" 'fn fact(n: i64) -> i64 { match n { 0 -> 1 1 -> 1 _ -> n * fact(n - 1) } } fn main() -> i64 { fact(5) }'
run_test3 "gcd" "6" 'fn gcd(a: i64, b: i64) -> i64 { match b { 0 -> a _ -> gcd(b, a - a / b * b) } } fn main() -> i64 { gcd(48, 18) }'
echo "weft3: $PASS3 passed, $FAIL3 failed"

echo ""
echo "=== Byte-identical gate ==="
cp /tmp/weft2 /tmp/weft2_cmp
cp /tmp/weft3 /tmp/weft3_cmp
if diff <(xxd /tmp/weft2_cmp) <(xxd /tmp/weft3_cmp) > /dev/null; then
  echo "  ✓ weft2 == weft3 (byte-identical after stripping signature)"
else
  echo "  ✗ weft2 != weft3"
fi

echo ""
echo "=== Summary ==="
echo "weft1: $PASS/$((PASS+FAIL))"
echo "weft2: $PASS2/$((PASS2+FAIL2))"
echo "weft3: $PASS3/$((PASS3+FAIL3))"
TOTAL=$((PASS+PASS2+PASS3))
TOTAL_FAIL=$((FAIL+FAIL2+FAIL3))
echo "Total: $TOTAL passed, $TOTAL_FAIL failed"
if [ $TOTAL_FAIL -gt 0 ]; then exit 1; fi
