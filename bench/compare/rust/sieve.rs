fn sieve_count(limit: usize) -> i64 {
    let mut arr = vec![0_i64; limit];
    for i in 0..limit {
        if i >= 2 {
            arr[i] = 1;
        }
    }
    let mut p = 2;
    while p * p < limit {
        if arr[p] == 1 {
            let mut j = p * p;
            while j < limit {
                arr[j] = 0;
                j += p;
            }
        }
        p += 1;
    }
    let mut count = 0_i64;
    for value in arr {
        if value == 1 {
            count += 1;
        }
    }
    count
}

fn main() {
    let limit = 200000_usize;
    let runs = 20;
    let mut total = 0_i64;
    for _ in 0..runs {
        total += sieve_count(limit);
    }
    if total != 359680 {
        panic!("{}", total);
    }
}
