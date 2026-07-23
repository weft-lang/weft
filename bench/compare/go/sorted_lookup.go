package main

type entry struct{ key, value int64 }

func cmpI64(a, b int64) int64 {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

func buildMap(n int64) []entry {
	m := make([]entry, 0, n)
	for i := int64(0); i < n; i++ {
		m = append(m, entry{i * 2, i})
	}
	return m
}

func find(m []entry, key int64, cmp func(int64, int64) int64) (int64, bool) {
	lo, hi := int64(0), int64(len(m))
	for lo < hi {
		mid := lo + (hi-lo)/2
		c := cmp(key, m[mid].key)
		if c == 0 {
			return mid, true
		}
		if c < 0 {
			hi = mid
		} else {
			lo = mid + 1
		}
	}
	return lo, false
}

func lookupSweep(m []entry, span int64, cmp func(int64, int64) int64) int64 {
	var sum int64
	for k := int64(0); k < span; k++ {
		if idx, ok := find(m, k, cmp); ok {
			sum += m[idx].value
		} else {
			sum++
		}
	}
	return sum
}

func main() {
	n := int64(20000)
	reps := 10
	m := buildMap(n)
	var total int64
	for r := 0; r < reps; r++ {
		total += lookupSweep(m, n*2, cmpI64)
	}
	if total != 2000100000 {
		panic(total)
	}
}
