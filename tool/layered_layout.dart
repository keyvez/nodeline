// Standalone prototype: layered (Sugiyama) auto-layout + crossing count.
//
// Goal: validate that a layered layout dramatically reduces edge crossings on
// the dense "consciousness" diagram before wiring it into the app.
//
// Run: dart tool/layered_layout.dart
//
// Phases:
//   1. Break cycles (DFS) so we have a DAG for ranking.
//   2. Assign layers (longest-path from sources).
//   3. Insert virtual nodes so every edge spans exactly one layer.
//   4. Reduce crossings within layers (median heuristic, up/down sweeps).
//   5. Assign x/y coordinates.
//   6. Count straight-line edge crossings before (a naive grid) vs after.

import 'dart:math';

/// Directed edges of the consciousness diagram (from test_diagrams.dart).
const List<List<String>> kEdges = [
  ['A', 'B'], ['B', 'C'], ['C', 'D'], ['D', 'E'], ['E', 'F'], ['F', 'D'],
  ['D', 'G'], ['G', 'H'], ['H', 'I'], ['H', 'J'], ['J', 'K'], ['J', 'L'],
  ['J', 'M'], ['K', 'N'], ['K', 'O'], ['N', 'P'], ['O', 'P'], ['I', 'Q'],
  ['I', 'R'], ['Q', 'S'], ['R', 'S'], ['C', 'T'], ['T', 'U'], ['U', 'V'],
  ['U', 'S'], ['C', 'W'], ['C', 'X'], ['C', 'Y'], ['W', 'T'], ['X', 'T'],
  ['Y', 'Z'], ['H', 'AA'], ['F', 'AB'], ['AB', 'AC'], ['AC', 'AD'],
  ['AD', 'E'], ['D', 'AE'], ['A', 'AF'], ['T', 'AG'], ['AG', 'C'],
  ['A', 'AH'], ['AH', 'AI'], ['AJ', 'AB'], ['AB', 'AI'], ['AI', 'A'],
];

void main() {
  final nodes = <String>{};
  for (final e in kEdges) {
    nodes.add(e[0]);
    nodes.add(e[1]);
  }
  print('Graph: ${nodes.length} nodes, ${kEdges.length} edges');

  // ── 1. Break cycles via DFS: edges that point to an ancestor get reversed
  //       for ranking purposes (we remember them to restore direction later).
  final adj = <String, List<String>>{for (final n in nodes) n: []};
  for (final e in kEdges) {
    adj[e[0]]!.add(e[1]);
  }
  final reversed = <List<String>>{}.cast<List<String>>();
  final state = <String, int>{}; // 0=unvisited,1=in-stack,2=done
  final acyclicEdges = <List<String>>[];

  void dfs(String u) {
    state[u] = 1;
    for (final v in adj[u]!) {
      if (state[v] == 1) {
        // back-edge → reverse for ranking
        acyclicEdges.add([v, u]);
      } else {
        acyclicEdges.add([u, v]);
        if (state[v] == null || state[v] == 0) dfs(v);
      }
    }
    state[u] = 2;
  }

  for (final n in nodes) {
    if (state[n] != 2) dfs(n);
  }

  // ── 2. Layer assignment: longest path. layer = max(layer(pred)+1).
  final layer = <String, int>{for (final n in nodes) n: 0};
  // Build pred list from acyclic edges, then relax in topological-ish order.
  final outAcyc = <String, List<String>>{for (final n in nodes) n: []};
  final indeg = <String, int>{for (final n in nodes) n: 0};
  for (final e in acyclicEdges) {
    outAcyc[e[0]]!.add(e[1]);
    indeg[e[1]] = indeg[e[1]]! + 1;
  }
  final queue = <String>[...nodes.where((n) => indeg[n] == 0)];
  final topo = <String>[];
  final indegWork = Map<String, int>.from(indeg);
  while (queue.isNotEmpty) {
    final u = queue.removeLast();
    topo.add(u);
    for (final v in outAcyc[u]!) {
      indegWork[v] = indegWork[v]! - 1;
      if (indegWork[v] == 0) queue.add(v);
    }
  }
  for (final u in topo) {
    for (final v in outAcyc[u]!) {
      if (layer[v]! < layer[u]! + 1) layer[v] = layer[u]! + 1;
    }
  }

  final maxLayer = layer.values.reduce(max);
  // Group nodes by layer.
  final layers = <int, List<String>>{for (var i = 0; i <= maxLayer; i++) i: []};
  for (final n in nodes) {
    layers[layer[n]!]!.add(n);
  }

  // ── 3. Virtual nodes so each acyclic edge spans one layer. Each long edge
  //       (layerSpan>1) becomes a chain through virtual nodes per intermediate
  //       layer. Track edges as ordered node-id lists for crossing math.
  int virtualCounter = 0;
  final routedEdges = <List<String>>[]; // each is a chain of node ids
  for (final e in acyclicEdges) {
    final a = e[0], b = e[1];
    final la = layer[a]!, lb = layer[b]!;
    if (lb <= la) {
      routedEdges.add([a, b]);
      continue;
    }
    if (lb - la == 1) {
      routedEdges.add([a, b]);
    } else {
      final chain = <String>[a];
      for (var l = la + 1; l < lb; l++) {
        final vname = '__v${virtualCounter++}';
        layer[vname] = l;
        layers[l]!.add(vname);
        chain.add(vname);
      }
      chain.add(b);
      routedEdges.add(chain);
    }
  }

  // ── 4. Crossing reduction: median heuristic with up/down sweeps.
  // order[layer] = list of node ids in left→right order.
  final order = <int, List<String>>{
    for (var i = 0; i <= maxLayer; i++) i: List<String>.from(layers[i]!)
  };

  // adjacency between consecutive layers, built from routed edge chains.
  // For node x in layer l, neighborsDown[x] = nodes in l+1 it connects to.
  final neighborsDown = <String, List<String>>{};
  final neighborsUp = <String, List<String>>{};
  for (final chain in routedEdges) {
    for (var i = 0; i < chain.length - 1; i++) {
      final u = chain[i], v = chain[i + 1];
      (neighborsDown[u] ??= []).add(v);
      (neighborsUp[v] ??= []).add(u);
    }
  }

  double medianOf(List<String> neighbors, List<String> fixedOrder) {
    if (neighbors.isEmpty) return -1;
    final positions = neighbors
        .map((n) => fixedOrder.indexOf(n))
        .where((p) => p >= 0)
        .toList()
      ..sort();
    if (positions.isEmpty) return -1;
    final m = positions.length;
    return positions[m ~/ 2].toDouble();
  }

  int countCrossingsLayered() {
    int total = 0;
    for (var l = 0; l < maxLayer; l++) {
      final upper = order[l]!;
      final lower = order[l + 1]!;
      final pos = <String, int>{};
      for (var i = 0; i < lower.length; i++) {
        pos[lower[i]] = i;
      }
      // Collect edges (upperIndex, lowerIndex).
      final edgePairs = <List<int>>[];
      for (var ui = 0; ui < upper.length; ui++) {
        final u = upper[ui];
        for (final v in neighborsDown[u] ?? const []) {
          if (pos.containsKey(v)) edgePairs.add([ui, pos[v]!]);
        }
      }
      // Count inversions in lower index when sorted by upper index.
      for (var i = 0; i < edgePairs.length; i++) {
        for (var j = i + 1; j < edgePairs.length; j++) {
          final a = edgePairs[i], b = edgePairs[j];
          if ((a[0] < b[0] && a[1] > b[1]) ||
              (a[0] > b[0] && a[1] < b[1])) {
            total++;
          }
        }
      }
    }
    return total;
  }

  final before = countCrossingsLayered();

  // Sweep: reorder each layer by median of neighbors in the adjacent fixed layer.
  for (var iter = 0; iter < 8; iter++) {
    // Downward: order layer l by medians from l-1.
    for (var l = 1; l <= maxLayer; l++) {
      final fixed = order[l - 1]!;
      final cur = order[l]!;
      final med = {
        for (final n in cur) n: medianOf(neighborsUp[n] ?? const [], fixed)
      };
      cur.sort((a, b) {
        final ma = med[a]!, mb = med[b]!;
        if (ma == -1 || mb == -1) return 0;
        return ma.compareTo(mb);
      });
    }
    // Upward: order layer l by medians from l+1.
    for (var l = maxLayer - 1; l >= 0; l--) {
      final fixed = order[l + 1]!;
      final cur = order[l]!;
      final med = {
        for (final n in cur) n: medianOf(neighborsDown[n] ?? const [], fixed)
      };
      cur.sort((a, b) {
        final ma = med[a]!, mb = med[b]!;
        if (ma == -1 || mb == -1) return 0;
        return ma.compareTo(mb);
      });
    }
  }

  final after = countCrossingsLayered();

  print('\nLayer-pair crossings (between adjacent ranks):');
  print('  before sweeps: $before');
  print('  after  sweeps: $after');
  if (before > 0) {
    final pct = (100 * (before - after) / before).toStringAsFixed(1);
    print('  reduction: $pct%');
  }

  print('\nLayer assignment (real nodes only):');
  for (var l = 0; l <= maxLayer; l++) {
    final real = order[l]!.where((n) => !n.startsWith('__v')).toList();
    print('  L$l: ${real.join(', ')}');
  }
}
