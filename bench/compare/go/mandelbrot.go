package main

func mandelbrotCount(size int, maxIter int) int {
	invSize := 1.0 / float64(size)
	total := 0
	for y := 0; y < size; y++ {
		ci := float64(y)*2.0*invSize - 1.0
		for x := 0; x < size; x++ {
			cr := float64(x)*3.0*invSize - 2.0
			zr := 0.0
			zi := 0.0
			mag2 := 0.0
			iter := 0
			for iter < maxIter && mag2 <= 4.0 {
				zr2 := zr * zr
				zi2 := zi * zi
				nextZi := 2.0 * zr * zi
				nextZr := zr2 - zi2
				zi = nextZi + ci
				zr = nextZr + cr
				magZr := zr * zr
				magZi := zi * zi
				mag2 = magZr + magZi
				iter++
			}
			if iter == maxIter {
				total++
			}
		}
	}
	return total
}

func main() {
	size := 256
	maxIter := 80
	runs := 3
	total := 0
	for i := 0; i < runs; i++ {
		total += mandelbrotCount(size, maxIter)
	}
	if total != 51201 {
		panic(total)
	}
}
