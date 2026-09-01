package main

import "os"

func directSum(n int64) int64 {
	var total int64
	remaining := n / 3
	for value := int64(0); value < n; value++ {
		mapped := value*3 + 1
		if remaining > 0 && mapped%2 == 0 {
			total += mapped
			remaining--
		}
	}
	return total
}

func main() {
	var total int64
	for repetition := 0; repetition < 10; repetition++ {
		total += directSum(10000)
	}
	if total != 333300000 {
		os.Exit(1)
	}
}
