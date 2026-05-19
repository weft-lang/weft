fn insertion_sort(items: &mut [i64]) {
    for i in 1..items.len() {
        let key = items[i];
        let mut j = i;
        while j > 0 && items[j - 1] > key {
            items[j] = items[j - 1];
            j -= 1;
        }
        items[j] = key;
    }
}

fn binary_search(items: &[i64], needle: i64) -> i64 {
    let mut lo = 0_usize;
    let mut hi = items.len();
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        let value = items[mid];
        if value == needle {
            return mid as i64;
        }
        if value < needle {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    -1
}

fn build_reverse(n: i64) -> Vec<i64> {
    let mut items = Vec::with_capacity(n as usize);
    let mut i = n - 1;
    loop {
        items.push(i);
        if i == 0 {
            break;
        }
        i -= 1;
    }
    items
}

fn checksum(items: &[i64]) -> i64 {
    items.iter().copied().sum()
}

fn run_once(n: i64) -> i64 {
    let mut items = build_reverse(n);
    insertion_sort(&mut items);
    checksum(&items) + binary_search(&items, 0) + binary_search(&items, n / 2) + binary_search(&items, n - 1)
}

fn main() {
    let n = 600_i64;
    let runs = 5;
    let mut total = 0_i64;
    for _ in 0..runs {
        total += run_once(n);
    }
    if total != 902995 {
        panic!("{}", total);
    }
}
