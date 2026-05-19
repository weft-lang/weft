fn graph_index(nodes: usize, from: usize, to: usize) -> usize {
    from * nodes + to
}

fn graph_add_edge(graph: &mut [i64], nodes: usize, from: usize, to: usize) {
    graph[graph_index(nodes, from, to)] = 1;
}

fn graph_has_edge(graph: &[i64], nodes: usize, from: usize, to: usize) -> i64 {
    graph[graph_index(nodes, from, to)]
}

fn build_graph(nodes: usize) -> Vec<i64> {
    let mut graph = vec![0_i64; nodes * nodes];
    for i in 0..nodes - 1 {
        graph_add_edge(&mut graph, nodes, i, i + 1);
        if i + 7 < nodes {
            graph_add_edge(&mut graph, nodes, i, i + 7);
        }
    }
    graph
}

fn graph_reachable_count(graph: &[i64], nodes: usize, start: usize) -> i64 {
    let mut seen = vec![0_i64; nodes];
    let mut queue = Vec::with_capacity(nodes);
    seen[start] = 1;
    queue.push(start);
    let mut head = 0;
    while head < queue.len() {
        let node = queue[head];
        head += 1;
        for next in 0..nodes {
            if graph_has_edge(graph, nodes, node, next) == 1 && seen[next] == 0 {
                seen[next] = 1;
                queue.push(next);
            }
        }
    }
    seen.iter().copied().sum()
}

fn main() {
    let nodes = 160_usize;
    let graph = build_graph(nodes);
    let mut total = 0_i64;
    for start in 0..nodes {
        total += graph_reachable_count(&graph, nodes, start);
    }
    if total != 12880 {
        panic!("{}", total);
    }
}
