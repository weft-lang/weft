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
    for _ in 0..10 {
        total += iterator_sum(10000);
    }
    if total != 333300000 {
        process::exit(1);
    }
}
