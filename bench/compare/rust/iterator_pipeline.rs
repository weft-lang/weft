use std::process;

fn iterator_sum(n: i64) -> i64 {
    (0..n)
        .map(|value| value * 3 + 1)
        .filter(|value| value % 2 == 0)
        .take((n / 3) as usize)
        .sum()
}

fn main() {
    let mut total = 0_i64;
    for repetition in 0..300 {
        total += iterator_sum(1000000 + repetition * 3);
    }
    if total != 100089626820300 {
        process::exit(1);
    }
}
