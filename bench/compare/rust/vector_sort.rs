fn sift_down(items: &mut [i64], start: usize, end: usize) {
    let mut root = start;
    loop {
        let child = root * 2 + 1;
        if child >= end {
            return;
        }
        let mut candidate = root;
        if items[candidate] < items[child] {
            candidate = child;
        }
        let right = child + 1;
        if right < end && items[candidate] < items[right] {
            candidate = right;
        }
        if candidate == root {
            return;
        }
        items.swap(root, candidate);
        root = candidate;
    }
}

fn heap_sort(items: &mut [i64]) {
    let mut start = items.len() / 2;
    while start > 0 {
        start -= 1;
        sift_down(items, start, items.len());
    }
    let mut end = items.len();
    while end > 1 {
        end -= 1;
        items.swap(0, end);
        sift_down(items, 0, end);
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
    heap_sort(&mut items);
    checksum(&items)
        + binary_search(&items, 0)
        + binary_search(&items, n / 2)
        + binary_search(&items, n - 1)
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
