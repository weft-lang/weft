package main

func insertionSort(items []int64) {
	for i := 1; i < len(items); i++ {
		key := items[i]
		j := i - 1
		for j >= 0 && items[j] > key {
			items[j+1] = items[j]
			j--
		}
		items[j+1] = key
	}
}

func binarySearch(items []int64, needle int64) int64 {
	lo := 0
	hi := len(items)
	for lo < hi {
		mid := lo + (hi-lo)/2
		value := items[mid]
		if value == needle {
			return int64(mid)
		}
		if value < needle {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return -1
}

func buildReverse(n int64) []int64 {
	items := make([]int64, 0, n)
	for i := n - 1; i >= 0; i-- {
		items = append(items, i)
	}
	return items
}

func checksum(items []int64) int64 {
	var sum int64
	for _, value := range items {
		sum += value
	}
	return sum
}

func runOnce(n int64) int64 {
	items := buildReverse(n)
	insertionSort(items)
	return checksum(items) + binarySearch(items, 0) + binarySearch(items, n/2) + binarySearch(items, n-1)
}

func main() {
	n := int64(600)
	runs := 5
	var total int64
	for i := 0; i < runs; i++ {
		total += runOnce(n)
	}
	if total != 902995 {
		panic(total)
	}
}
