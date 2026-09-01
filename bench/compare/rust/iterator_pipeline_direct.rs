use std::process;

fn direct_sum(n: i64) -> i64 {
    let mut total = 0_i64;
    let mut remaining = n / 3;
    for value in 0..n {
        let mapped = value * 3 + 1;
        if remaining > 0 && mapped % 2 == 0 {
            total += mapped;
            remaining -= 1;
        }
    }
    total
}

fn main() {
    let mut total = 0_i64;
    for _ in 0..10 {
        total += direct_sum(10000);
    }
    if total != 333300000 {
        process::exit(1);
    }
}
