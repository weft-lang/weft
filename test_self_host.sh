#!/bin/bash
set -e

rm -f /tmp/weft1 /tmp/weft2 /tmp/weft3 /tmp/t /tmp/t2 /tmp/t3

echo "=== Bootstrap: checked-in weft → weft1 ==="
./weft < compiler/main.weft > /tmp/weft1
codesign -fs - /tmp/weft1 && chmod +x /tmp/weft1

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
run_test "while" "42" 'fn main() -> i64 { let mut x = 0 while x < 42 { x = x + 1 } x }'
run_test "match_int" "42" 'fn main() -> i64 { match 1 { 1 -> 42 } }'
run_test "match_ctor" "25" 'type Shape { Circle(i64) } fn main() -> i64 { let s = Circle(5) match s { Circle(r) -> r * r } }'
run_test "record" "42" 'type Point { x: i64, y: i64 } fn main() -> i64 { let p = Point { x: 30, y: 12 } p.x + p.y }'
echo "weft1: $PASS passed, $FAIL failed"

echo ""
echo "=== weft1 → weft2 ==="
/tmp/weft1 < compiler/main.weft > /tmp/weft2
codesign -fs - /tmp/weft2 && chmod +x /tmp/weft2

echo "=== weft2 comprehensive tests ==="
PASS2=0; FAIL2=0
run_test2() {
  local name="$1" expected="$2" input="$3"
  echo "$input" | /tmp/weft2 > /tmp/t2 && codesign -s - /tmp/t2 2>/dev/null && chmod +x /tmp/t2
  local got=$(/tmp/t2 2>/dev/null; echo $?)
  if [ "$got" = "$expected" ]; then
    PASS2=$((PASS2+1))
  else
    echo "  ✗ $name = $got (expected $expected)"
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
  echo "$input" | /tmp/weft2 > /tmp/t2 && codesign -s - /tmp/t2 2>/dev/null && chmod +x /tmp/t2
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
echo "weft2: $PASS2 passed, $FAIL2 failed"

echo ""
echo "=== weft2 → weft3 (bootstrap gate) ==="
/tmp/weft2 < compiler/main.weft > /tmp/weft3
codesign -fs - /tmp/weft3 && chmod +x /tmp/weft3

echo "=== weft3 spot checks ==="
PASS3=0; FAIL3=0
run_test3() {
  local name="$1" expected="$2" input="$3"
  echo "$input" | /tmp/weft3 > /tmp/t3 && codesign -s - /tmp/t3 2>/dev/null && chmod +x /tmp/t3
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
cp /tmp/weft2 /tmp/weft2_cmp && codesign --remove-signature /tmp/weft2_cmp 2>/dev/null
cp /tmp/weft3 /tmp/weft3_cmp && codesign --remove-signature /tmp/weft3_cmp 2>/dev/null
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
