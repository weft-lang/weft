package main

func sieveCount(limit int) int {
	arr := make([]int64, limit)
	for i := 0; i < limit; i++ {
		if i >= 2 {
			arr[i] = 1
		}
	}
	for p := 2; p*p < limit; p++ {
		if arr[p] == 1 {
			for j := p * p; j < limit; j += p {
				arr[j] = 0
			}
		}
	}
	count := 0
	for i := 0; i < limit; i++ {
		if arr[i] == 1 {
			count++
		}
	}
	return count
}

func main() {
	limit := 200000
	runs := 20
	total := 0
	for i := 0; i < runs; i++ {
		total += sieveCount(limit)
	}
	if total != 359680 {
		panic(total)
	}
}
