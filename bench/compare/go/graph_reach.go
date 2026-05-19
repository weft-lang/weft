package main

func graphIndex(nodes, from, to int) int {
	return from*nodes + to
}

func graphAddEdge(graph []int64, nodes, from, to int) {
	graph[graphIndex(nodes, from, to)] = 1
}

func graphHasEdge(graph []int64, nodes, from, to int) int64 {
	return graph[graphIndex(nodes, from, to)]
}

func buildGraph(nodes int) []int64 {
	graph := make([]int64, nodes*nodes)
	for i := 0; i < nodes-1; i++ {
		graphAddEdge(graph, nodes, i, i+1)
		if i+7 < nodes {
			graphAddEdge(graph, nodes, i, i+7)
		}
	}
	return graph
}

func graphReachableCount(graph []int64, nodes, start int) int64 {
	seen := make([]int64, nodes)
	queue := make([]int, 0, nodes)
	seen[start] = 1
	queue = append(queue, start)
	head := 0
	for head < len(queue) {
		node := queue[head]
		head++
		for next := 0; next < nodes; next++ {
			if graphHasEdge(graph, nodes, node, next) == 1 && seen[next] == 0 {
				seen[next] = 1
				queue = append(queue, next)
			}
		}
	}
	var total int64
	for _, mark := range seen {
		total += mark
	}
	return total
}

func main() {
	nodes := 160
	graph := buildGraph(nodes)
	var total int64
	for start := 0; start < nodes; start++ {
		total += graphReachableCount(graph, nodes, start)
	}
	if total != 12880 {
		panic(total)
	}
}
