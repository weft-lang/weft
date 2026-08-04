package main

func siftDown(items []int64, start, end int) {
	root := start
	for {
		child := root*2 + 1
		if child >= end {
			return
		}
		candidate := root
		if items[candidate] < items[child] {
			candidate = child
		}
		right := child + 1
		if right < end && items[candidate] < items[right] {
			candidate = right
		}
		if candidate == root {
			return
		}
		items[root], items[candidate] = items[candidate], items[root]
		root = candidate
	}
}

func heapSort(items []int64) {
	for start := len(items) / 2; start > 0; {
		start--
		siftDown(items, start, len(items))
	}
	for end := len(items); end > 1; {
		end--
		items[0], items[end] = items[end], items[0]
		siftDown(items, 0, end)
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
	heapSort(items)
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
