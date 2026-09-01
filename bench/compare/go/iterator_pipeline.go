package main

import "os"

type nextInt func() (int64, bool)

func rangeIter(start, end int64) nextInt {
	current := start
	return func() (int64, bool) {
		if current >= end {
			return 0, false
		}
		value := current
		current++
		return value, true
	}
}

func mapIter(source nextInt, transform func(int64) int64) nextInt {
	return func() (int64, bool) {
		value, ok := source()
		if !ok {
			return 0, false
		}
		return transform(value), true
	}
}

func filterIter(source nextInt, predicate func(int64) bool) nextInt {
	return func() (int64, bool) {
		for {
			value, ok := source()
			if !ok {
				return 0, false
			}
			if predicate(value) {
				return value, true
			}
		}
	}
}

func takeIter(source nextInt, limit int64) nextInt {
	remaining := limit
	return func() (int64, bool) {
		if remaining <= 0 {
			return 0, false
		}
		value, ok := source()
		if !ok {
			return 0, false
		}
		remaining--
		return value, true
	}
}

func iteratorSum(n int64) int64 {
	source := rangeIter(0, n)
	mapped := mapIter(source, func(value int64) int64 { return value*3 + 1 })
	filtered := filterIter(mapped, func(value int64) bool { return value%2 == 0 })
	limited := takeIter(filtered, n/3)
	var total int64
	for {
		value, ok := limited()
		if !ok {
			return total
		}
		total += value
	}
}

func main() {
	var total int64
	for repetition := 0; repetition < 10; repetition++ {
		total += iteratorSum(10000)
	}
	if total != 333300000 {
		os.Exit(1)
	}
}
