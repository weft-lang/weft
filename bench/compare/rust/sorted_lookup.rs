struct Entry {
    key: i64,
    value: i64,
}

fn cmp_i64(a: i64, b: i64) -> i64 {
    if a < b {
        -1
    } else if a > b {
        1
    } else {
        0
    }
}

fn build_map(n: i64) -> Vec<Entry> {
    let mut m = Vec::with_capacity(n as usize);
    for i in 0..n {
        m.push(Entry { key: i * 2, value: i });
    }
    m
}

fn find(m: &[Entry], key: i64, cmp: impl Fn(i64, i64) -> i64) -> (i64, bool) {
    let mut lo: i64 = 0;
    let mut hi: i64 = m.len() as i64;
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        let c = cmp(key, m[mid as usize].key);
        if c == 0 {
            return (mid, true);
        }
        if c < 0 {
            hi = mid;
        } else {
            lo = mid + 1;
        }
    }
    (lo, false)
}

fn lookup_sweep(m: &[Entry], span: i64) -> i64 {
    let mut sum: i64 = 0;
    for k in 0..span {
        let (idx, ok) = find(m, k, cmp_i64);
        if ok {
            sum += m[idx as usize].value;
        } else {
            sum += 1;
        }
    }
    sum
}

fn main() {
    let n: i64 = 20000;
    let reps = 10;
    let m = build_map(n);
    let mut total: i64 = 0;
    for _ in 0..reps {
        total += lookup_sweep(&m, n * 2);
    }
    if total != 2000100000 {
        panic!("{}", total);
    }
}
