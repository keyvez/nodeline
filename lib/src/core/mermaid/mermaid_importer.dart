import 'dart:math';

import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/styles.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Parses a Mermaid flowchart string into flow_draw project JSON.
class MermaidImporter {
  // Layout constants
  static const double _hSpacing = 120.0;
  static const double _vSpacing = 140.0;
  static const double _nodePaddingH = 24.0;
  static const double _nodePaddingV = 16.0;
  static const double _minNodeWidth = 160.0;
  static const double _minNodeHeight = 60.0;
  // Padding around a subgraph container box, and headroom for its title.
  static const double _subgraphPad = 28.0;
  static const double _subgraphTitleH = 28.0;

  /// Parses a Mermaid flowchart string and returns project JSON
  /// consumable by `controller.loadProject()`.
  static Map<String, dynamic> import(String mermaid) {
    final lines = mermaid.split('\n').map((l) => l.trim()).toList();

    // Parse direction from header. Accept both `flowchart` and `graph`,
    // with an optional direction (TD/TB/LR/BT/RL). Default to TD.
    String direction = 'TD';
    int startLine = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final headerMatch =
          RegExp(r'^(?:flowchart|graph)\s+(TD|TB|LR|BT|RL)\s*$').firstMatch(line);
      if (headerMatch != null) {
        direction = headerMatch.group(1)!;
        if (direction == 'TB') direction = 'TD';
        startLine = i + 1;
        break;
      }
      // Also accept just "flowchart"/"graph" without direction.
      if (RegExp(r'^(?:flowchart|graph)\s*$').hasMatch(line)) {
        startLine = i + 1;
        break;
      }
    }

    // Parse nodes, edges, and subgraphs.
    final nodes = <String, _MermaidNode>{};
    final edges = <_MermaidEdge>[];
    final subgraphs = <_MermaidSubgraph>[];

    // Stack of currently-open subgraphs (Mermaid allows nesting; we track the
    // innermost for membership but render every level).
    final openSubgraphs = <_MermaidSubgraph>[];

    for (int i = startLine; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty || line.startsWith('%%')) continue;

      // subgraph "Title" / subgraph Title / subgraph id["Title"]
      final subMatch = RegExp(
        r'^subgraph\s+(?:"([^"]*)"|(\w+)\s*\[\s*"?([^"\]]*)"?\s*\]|([^\[]+?))\s*$',
      ).firstMatch(line);
      if (subMatch != null) {
        final title = (subMatch.group(1) ??
                subMatch.group(3) ??
                subMatch.group(4) ??
                subMatch.group(2) ??
                '')
            .trim();
        final sg = _MermaidSubgraph(title);
        subgraphs.add(sg);
        openSubgraphs.add(sg);
        continue;
      }

      // end (closes the innermost subgraph)
      if (line == 'end') {
        if (openSubgraphs.isNotEmpty) openSubgraphs.removeLast();
        continue;
      }

      // Styling/class/click directives we don't model — skip quietly.
      if (RegExp(r'^(style|classDef|class|click|linkStyle|direction)\b')
          .hasMatch(line)) {
        continue;
      }

      // Try to parse as edge first.
      final edge = _parseEdge(line, nodes, openSubgraphs);
      if (edge != null) {
        edges.add(edge);
        continue;
      }

      // Try to parse as node declaration.
      final declared = _parseNodeDeclaration(line, nodes);
      if (declared != null && openSubgraphs.isNotEmpty) {
        openSubgraphs.last.memberIds.add(declared);
      }
    }

    // Auto-layout (direction- and subgraph-aware).
    _autoLayout(nodes, edges, direction, subgraphs);

    // Build project JSON.
    return _buildProjectJson(nodes, edges, subgraphs);
  }

  /// Classifies an edge connector string into a logical edge type.
  /// Returns one of 'arrow', 'dotted-arrow', 'thick-arrow', 'line',
  /// 'dotted-line', 'thick-line', or null if not a connector.
  static String? _connectorType(String c) {
    // Order matters: check dotted/thick before plain.
    if (RegExp(r'^-\.+->$').hasMatch(c)) return 'dotted-arrow';
    if (RegExp(r'^-\.+-$').hasMatch(c)) return 'dotted-line';
    if (RegExp(r'^=+>$').hasMatch(c)) return 'thick-arrow';
    if (RegExp(r'^=+$').hasMatch(c)) return 'thick-line';
    if (RegExp(r'^-+>$').hasMatch(c)) return 'arrow';
    if (RegExp(r'^-+$').hasMatch(c)) return 'line';
    return null;
  }

  /// Parses an edge line like `A --> B`, `A -->|label| B`, `A -.->|x| B`,
  /// `A ==> B`, or `A --- B`. Also captures inline node declarations.
  static _MermaidEdge? _parseEdge(
    String line,
    Map<String, _MermaidNode> nodes,
    List<_MermaidSubgraph> openSubgraphs,
  ) {
    // Shape suffix that may follow a node id inline.
    const shape = r'(?:\[/[^\]]*/\]|\[\[[^\]]*\]\]|\[[^\]]*\]|'
        r'\(\([^)]*\)\)|\(\[[^\]]*\]\)|\([^)]*\)|\{[^}]*\}|>[^\]]*\])';
    // Connector: dashes/dots/equals, optional arrowhead.
    const connector = r'(-\.+->|-\.+-|=+>|=+|-+>|-+)';

    final edgePattern = RegExp(
      '^(\\w+)$shape?\\s*'
      '$connector'
      r'(?:\|([^|]*)\|)?\s*'
      '(\\w+)$shape?\\s*\$',
    );

    final match = edgePattern.firstMatch(line);
    if (match == null) return null;

    final fromId = match.group(1)!;
    final connStr = match.group(2)!;
    final edgeLabel = match.group(3);
    final toId = match.group(4)!;

    final kind = _connectorType(connStr);
    if (kind == null) return null;

    // Parse inline node declarations from the full line.
    _parseInlineNode(line, fromId, nodes, openSubgraphs);
    _parseInlineNode(line, toId, nodes, openSubgraphs);

    // Ensure nodes exist.
    nodes.putIfAbsent(fromId, () => _MermaidNode(fromId, fromId, 'rect'));
    nodes.putIfAbsent(toId, () => _MermaidNode(toId, toId, 'rect'));
    if (openSubgraphs.isNotEmpty) {
      openSubgraphs.last.memberIds.add(fromId);
      openSubgraphs.last.memberIds.add(toId);
    }

    final isLine = kind.endsWith('line');
    return _MermaidEdge(
      from: fromId,
      to: toId,
      type: isLine ? 'line' : 'arrow',
      label: edgeLabel,
      dashed: kind.startsWith('dotted'),
      thick: kind.startsWith('thick'),
    );
  }

  /// Tries to extract an inline node declaration from an edge line.
  static void _parseInlineNode(
    String line,
    String nodeId,
    Map<String, _MermaidNode> nodes,
    List<_MermaidSubgraph> openSubgraphs,
  ) {
    if (nodes.containsKey(nodeId)) return;

    final esc = RegExp.escape(nodeId);
    // (shapeRegex, type) — quotes around the label are optional.
    final candidates = <(RegExp, String)>[
      (RegExp('$esc\\(\\(\\s*"?([^")]*?)"?\\s*\\)\\)'), 'circle'),
      (RegExp('$esc\\(\\[\\s*"?([^"\\]]*?)"?\\s*\\]\\)'), 'rect'), // stadium
      (RegExp('$esc\\[/\\s*"?([^"/]*?)"?\\s*/\\]'), 'parallelogram'),
      (RegExp('$esc\\{\\s*"?([^"}]*?)"?\\s*\\}'), 'diamond'),
      (RegExp('$esc\\[\\s*"?([^"\\]]*?)"?\\s*\\]'), 'rect'),
      (RegExp('$esc\\(\\s*"?([^")]*?)"?\\s*\\)'), 'rect'), // rounded
    ];

    for (final (re, type) in candidates) {
      final match = re.firstMatch(line);
      if (match != null) {
        final label = (match.group(1) ?? '').trim();
        nodes[nodeId] = _MermaidNode(nodeId, label.isEmpty ? nodeId : label, type);
        if (openSubgraphs.isNotEmpty) openSubgraphs.last.memberIds.add(nodeId);
        return;
      }
    }
  }

  /// Parses a standalone node declaration line. Returns the node id if one
  /// was declared (or referenced), else null. Quotes are optional.
  static String? _parseNodeDeclaration(
    String line,
    Map<String, _MermaidNode> nodes,
  ) {
    // (shapeRegex, type) — same shapes as inline, anchored to whole line.
    final candidates = <(RegExp, String)>[
      (RegExp(r'^(\w+)\(\(\s*"?([^")]*?)"?\s*\)\)$'), 'circle'),
      (RegExp(r'^(\w+)\(\[\s*"?([^"\]]*?)"?\s*\]\)$'), 'rect'), // stadium
      (RegExp(r'^(\w+)\[/\s*"?([^"/]*?)"?\s*/\]$'), 'parallelogram'),
      (RegExp(r'^(\w+)\{\s*"?([^"}]*?)"?\s*\}$'), 'diamond'),
      (RegExp(r'^(\w+)\[\s*"?([^"\]]*?)"?\s*\]$'), 'rect'),
      (RegExp(r'^(\w+)\(\s*"?([^")]*?)"?\s*\)$'), 'rect'), // rounded
    ];

    for (final (re, type) in candidates) {
      final match = re.firstMatch(line);
      if (match != null) {
        final id = match.group(1)!;
        final label = (match.group(2) ?? '').trim();
        nodes[id] = _MermaidNode(id, label.isEmpty ? id : label, type);
        return id;
      }
    }

    // Bare node id on its own line.
    final bare = RegExp(r'^(\w+)$').firstMatch(line);
    if (bare != null) {
      final id = bare.group(1)!;
      nodes.putIfAbsent(id, () => _MermaidNode(id, id, 'rect'));
      return id;
    }

    return null;
  }

  /// DAG layering auto-layout. [direction] is one of TD/LR/BT/RL and controls
  /// the primary flow axis. Subgraph members are kept contiguous within their
  /// layers so the container boxes stay tight.
  static void _autoLayout(
    Map<String, _MermaidNode> nodes,
    List<_MermaidEdge> edges,
    String direction,
    List<_MermaidSubgraph> subgraphs,
  ) {
    // Calculate node sizes.
    for (final node in nodes.values) {
      _calculateNodeSize(node);
    }

    final nodeIds = nodes.keys.toList();
    final adj = {for (var id in nodeIds) id: <String>[]};
    final parents = {for (var id in nodeIds) id: <String>[]};

    for (final edge in edges) {
      if (nodeIds.contains(edge.from) && nodeIds.contains(edge.to)) {
        adj[edge.from]!.add(edge.to);
        parents[edge.to]!.add(edge.from);
      }
    }

    // Detect and remove cycles.
    final reversedEdges = <(String, String)>[];
    _detectAndRemoveCycles(nodeIds, adj, reversedEdges);

    // Assign layers.
    final layers = _assignLayers(nodeIds, adj);

    // Order layers to minimize crossings.
    _orderLayers(layers, adj, parents);

    // Keep subgraph members grouped within each layer.
    _groupSubgraphsWithinLayers(layers, nodes, subgraphs);

    // Assign coordinates directly in the requested orientation. Layers stack
    // along the flow axis; nodes within a layer spread along the cross axis,
    // packed by each box's true extent so nothing overlaps after re-orienting.
    _assignCoordinates(layers, nodes, direction);

    // DAG layering and subgraph grouping can disagree: two subgraphs whose
    // members all sit in the same layer would land in the same column/row and
    // their container boxes would overlap. Separate overlapping subgraphs along
    // the cross axis, shifting their member nodes with them.
    _separateOverlappingSubgraphs(nodes, subgraphs, direction);

    // Restore reversed edges.
    for (final edge in reversedEdges) {
      adj[edge.$1]!.add(edge.$2);
      adj[edge.$2]!.remove(edge.$1);
    }
  }

  /// Container bounds (with padding/title) of a subgraph's members.
  static Rect? _subgraphBounds(
    _MermaidSubgraph sg,
    Map<String, _MermaidNode> nodes,
  ) {
    Rect? b;
    for (final id in sg.memberIds) {
      final n = nodes[id];
      if (n == null) continue;
      b = b == null ? n.rect : b.expandToInclude(n.rect);
    }
    if (b == null) return null;
    return Rect.fromLTWH(
      b.left - _subgraphPad,
      b.top - _subgraphPad - _subgraphTitleH,
      b.width + _subgraphPad * 2,
      b.height + _subgraphPad * 2 + _subgraphTitleH,
    );
  }

  /// Pushes overlapping subgraph containers apart along the cross axis (the
  /// axis perpendicular to the flow), translating member nodes so the visual
  /// grouping is preserved. Greedy: processes subgraphs in declaration order
  /// and slides each one past any already-placed sibling it collides with.
  static void _separateOverlappingSubgraphs(
    Map<String, _MermaidNode> nodes,
    List<_MermaidSubgraph> subgraphs,
    String direction,
  ) {
    if (subgraphs.length < 2) return;
    final horizontalFlow = direction == 'LR' || direction == 'RL';
    const gap = 48.0;

    // Only consider subgraphs that have laid-out members.
    final placed = <_MermaidSubgraph>[];
    for (final sg in subgraphs) {
      var bounds = _subgraphBounds(sg, nodes);
      if (bounds == null) continue;

      // Resolve collisions against already-placed subgraphs by sliding along
      // the cross axis (y for LR/RL, x for TD/BT).
      bool moved = true;
      int guard = 0;
      while (moved && guard++ < 64) {
        moved = false;
        for (final other in placed) {
          final ob = _subgraphBounds(other, nodes);
          if (ob == null) continue;
          if (!bounds!.overlaps(ob)) continue;
          // Shift this subgraph just past `other` on the cross axis.
          double delta;
          if (horizontalFlow) {
            delta = ob.bottom + gap - bounds.top;
          } else {
            delta = ob.right + gap - bounds.left;
          }
          if (delta <= 0) continue;
          for (final id in sg.memberIds) {
            final n = nodes[id];
            if (n == null) continue;
            final r = n.rect;
            n.rect = horizontalFlow
                ? r.translate(0, delta)
                : r.translate(delta, 0);
          }
          bounds = _subgraphBounds(sg, nodes);
          moved = true;
        }
      }
      placed.add(sg);
    }
  }

  static void _calculateNodeSize(_MermaidNode node) {
    final painter = TextPainter(
      text: TextSpan(
        text: node.label,
        style: const TextStyle(fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: _minNodeWidth * 1.5);

    final width = max(_minNodeWidth, painter.width + _nodePaddingH * 2);
    final height = max(_minNodeHeight, painter.height + _nodePaddingV * 2);
    node.rect = Rect.fromLTWH(0, 0, width, height);
  }

  static void _detectAndRemoveCycles(
    List<String> nodeIds,
    Map<String, List<String>> adj,
    List<(String, String)> reversedEdges,
  ) {
    final visiting = <String>{};
    final visited = <String>{};
    for (final node in nodeIds) {
      if (!visited.contains(node)) {
        _dfsCycleCheck(node, adj, visiting, visited, reversedEdges);
      }
    }
  }

  static void _dfsCycleCheck(
    String u,
    Map<String, List<String>> adj,
    Set<String> visiting,
    Set<String> visited,
    List<(String, String)> reversedEdges,
  ) {
    visiting.add(u);
    visited.add(u);
    final neighbors = List<String>.from(adj[u]!);
    for (final v in neighbors) {
      if (visiting.contains(v)) {
        adj[u]!.remove(v);
        adj.putIfAbsent(v, () => []).add(u);
        reversedEdges.add((v, u));
      } else if (!visited.contains(v)) {
        _dfsCycleCheck(v, adj, visiting, visited, reversedEdges);
      }
    }
    visiting.remove(u);
  }

  static Map<int, List<String>> _assignLayers(
    List<String> nodeIds,
    Map<String, List<String>> adj,
  ) {
    final layers = <int, List<String>>{};
    final nodeLayer = <String, int>{};

    for (final node in nodeIds) {
      nodeLayer[node] = 0;
    }

    bool changed = true;
    while (changed) {
      changed = false;
      for (final u in nodeIds) {
        for (final v in adj[u]!) {
          if (nodeLayer[v]! < nodeLayer[u]! + 1) {
            nodeLayer[v] = nodeLayer[u]! + 1;
            changed = true;
          }
        }
      }
    }

    for (final node in nodeIds) {
      layers.putIfAbsent(nodeLayer[node]!, () => []).add(node);
    }
    return layers;
  }

  static void _orderLayers(
    Map<int, List<String>> layers,
    Map<String, List<String>> adj,
    Map<String, List<String>> parents,
  ) {
    final nodePositions = <String, int>{};
    for (int i = 0; i < layers.length; i++) {
      for (int j = 0; j < layers[i]!.length; j++) {
        nodePositions[layers[i]![j]] = j;
      }
    }

    for (int iter = 0; iter < 8; iter++) {
      for (int i = 1; i < layers.length; i++) {
        final barycenters = <String, double>{};
        for (final u in layers[i]!) {
          final parentNodes = parents[u]!;
          if (parentNodes.isEmpty) {
            barycenters[u] = -1.0;
          } else {
            barycenters[u] =
                parentNodes.map((p) => nodePositions[p]!).fold<int>(0, (a, b) => a + b) / parentNodes.length;
          }
        }
        layers[i]!.sort((a, b) => barycenters[a]!.compareTo(barycenters[b]!));
        for (int j = 0; j < layers[i]!.length; j++) { nodePositions[layers[i]![j]] = j; }
      }
      for (int i = layers.length - 2; i >= 0; i--) {
        final barycenters = <String, double>{};
        for (final u in layers[i]!) {
          final childrenNodes = adj[u]!;
          if (childrenNodes.isEmpty) {
            barycenters[u] = -1.0;
          } else {
            barycenters[u] =
                childrenNodes.map((c) => nodePositions[c]!).fold<int>(0, (a, b) => a + b) / childrenNodes.length;
          }
        }
        layers[i]!.sort((a, b) => barycenters[a]!.compareTo(barycenters[b]!));
        for (int j = 0; j < layers[i]!.length; j++) { nodePositions[layers[i]![j]] = j; }
      }
    }
  }

  /// Reorders each layer so that members of the same subgraph are contiguous,
  /// preserving the crossing-minimised relative order as much as possible.
  static void _groupSubgraphsWithinLayers(
    Map<int, List<String>> layers,
    Map<String, _MermaidNode> nodes,
    List<_MermaidSubgraph> subgraphs,
  ) {
    if (subgraphs.isEmpty) return;

    // Map each node to the index of its (first) owning subgraph, or -1.
    final group = <String, int>{};
    for (int s = 0; s < subgraphs.length; s++) {
      for (final id in subgraphs[s].memberIds) {
        group.putIfAbsent(id, () => s);
      }
    }

    for (final entry in layers.entries) {
      final layer = entry.value;
      // Stable-sort by group index; ungrouped (-1) float to the front.
      final order = {for (int i = 0; i < layer.length; i++) layer[i]: i};
      layer.sort((a, b) {
        final ga = group[a] ?? -1;
        final gb = group[b] ?? -1;
        if (ga != gb) return ga.compareTo(gb);
        return order[a]!.compareTo(order[b]!);
      });
    }
  }

  /// Lays out [layers] in the orientation given by [direction].
  ///
  /// Conceptually we always stack layers along a "flow" axis and spread each
  /// layer's nodes along the perpendicular "cross" axis. For TD/BT the flow
  /// axis is vertical; for LR/RL it is horizontal. Cross-axis packing uses each
  /// box's extent *on that axis* so wide multi-line labels never overlap.
  static void _assignCoordinates(
    Map<int, List<String>> layers,
    Map<String, _MermaidNode> nodes,
    String direction,
  ) {
    final horizontalFlow = direction == 'LR' || direction == 'RL';

    // Extent of a node along the flow axis and the cross axis.
    double flowExtent(_MermaidNode n) =>
        horizontalFlow ? n.rect.width : n.rect.height;
    double crossExtent(_MermaidNode n) =>
        horizontalFlow ? n.rect.height : n.rect.width;

    // Spacing between layers (flow axis) and between siblings (cross axis).
    final flowSpacing = horizontalFlow ? _hSpacing : _vSpacing;
    final crossSpacing = _hSpacing;

    // Total cross-axis size of each layer, for centering.
    final layerCross = <int, double>{};
    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i]!;
      double total = (layer.length - 1) * crossSpacing;
      for (final id in layer) {
        total += crossExtent(nodes[id]!);
      }
      layerCross[i] = total;
    }

    double flowPos = 0;
    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i]!;
      double maxFlow = 0;
      double crossPos = -(layerCross[i]! / 2);

      for (final id in layer) {
        final node = nodes[id]!;
        maxFlow = max(maxFlow, flowExtent(node));
        if (horizontalFlow) {
          node.rect = Rect.fromLTWH(
            flowPos, crossPos, node.rect.width, node.rect.height);
          crossPos += node.rect.height + crossSpacing;
        } else {
          node.rect = Rect.fromLTWH(
            crossPos, flowPos, node.rect.width, node.rect.height);
          crossPos += node.rect.width + crossSpacing;
        }
      }
      flowPos += maxFlow + flowSpacing;
    }

    // Reverse the flow axis for BT/RL.
    if (direction == 'BT' || direction == 'RL') {
      final maxFlow = horizontalFlow
          ? nodes.values.map((n) => n.rect.right).reduce(max)
          : nodes.values.map((n) => n.rect.bottom).reduce(max);
      for (final n in nodes.values) {
        final r = n.rect;
        n.rect = horizontalFlow
            ? Rect.fromLTWH(maxFlow - r.right, r.top, r.width, r.height)
            : Rect.fromLTWH(r.left, maxFlow - r.bottom, r.width, r.height);
      }
    }
  }

  /// Determines which side of [sourceRect] faces [targetRect].
  /// Returns 0=left, 1=right, 2=top, 3=bottom.
  static int _exitSide(Rect sourceRect, Rect targetRect) {
    final dx = targetRect.center.dx - sourceRect.center.dx;
    final dy = targetRect.center.dy - sourceRect.center.dy;
    final angle = atan2(dy, dx);
    const piOver4 = pi / 4;
    if (angle > -piOver4 && angle <= piOver4) return 1; // right
    if (angle > piOver4 && angle <= 3 * piOver4) return 3; // bottom
    if (angle > 3 * piOver4 || angle <= -3 * piOver4) return 0; // left
    return 2; // top
  }

  /// Converts a side index + fractional position along that side to a
  /// normalised [Offset] in [0,1]×[0,1] rect space.
  /// [t] is 0.0–1.0 from the "start" of that edge (left→right / top→bottom).
  static Offset _sideToRelative(int side, double t) {
    // Keep ports away from corners: clamp t to [0.15, 0.85].
    final s = 0.15 + t * 0.70;
    switch (side) {
      case 0: return Offset(0.0, s);  // left edge, varying y
      case 1: return Offset(1.0, s);  // right edge, varying y
      case 2: return Offset(s, 0.0);  // top edge, varying x
      case 3: return Offset(s, 1.0);  // bottom edge, varying x
      default: return Offset(0.5, 0.5);
    }
  }

  /// Builds the final project JSON from parsed nodes, edges, and subgraphs.
  static Map<String, dynamic> _buildProjectJson(
    Map<String, _MermaidNode> nodes,
    List<_MermaidEdge> edges,
    List<_MermaidSubgraph> subgraphs,
  ) {
    final drawingObjects = <Map<String, dynamic>>[];
    const uuid = Uuid();

    // ── Subgraph container boxes ────────────────────────────────────────────
    // Emit these FIRST so they paint behind their member nodes. Each box is a
    // pale, rounded rectangle bounding its members, titled at the top.
    for (final sg in subgraphs) {
      final container = _subgraphBounds(sg, nodes);
      if (container == null) continue;

      drawingObjects.add(RectangleObject(
        id: uuid.v4(),
        rect: container,
        text: sg.title,
        borderRadius: 12.0,
        fillColor: const Color(0x110A84FF),
        strokeColor: const Color(0xFF8AB4F8),
        lineStyle: LineStyle.dashed,
      ).toJson());
    }

    // Generate UUIDs for each mermaid node.
    final uuidMap = <String, String>{};
    for (final id in nodes.keys) {
      uuidMap[id] = uuid.v4();
    }

    // ── Port assignment ─────────────────────────────────────────────────────
    // Strategy: assign 1 port per side first (spread across sides), then add
    // more only if the side has enough room. Minimum pixel gap between ports.
    const double minPortGap = 50.0;

    // How many ports fit on a side of a node (at least 1).
    int capacity(String nodeId, int side) {
      final node = nodes[nodeId]!;
      final edgeLen = (side == 0 || side == 1) ? node.rect.height : node.rect.width;
      // usable 70% of edge (matching [0.15, 0.85] range)
      return max(1, (edgeLen * 0.70 / minPortGap).floor());
    }

    // Desired side per edge endpoint: key='nodeId:edgeIdx', value=preferred side
    // We first assign each endpoint to its natural side, then overflow.
    final startSide = List<int>.filled(edges.length, 0);
    final endSide   = List<int>.filled(edges.length, 0);

    for (int i = 0; i < edges.length; i++) {
      final fromNode = nodes[edges[i].from]!;
      final toNode   = nodes[edges[i].to]!;
      startSide[i] = _exitSide(fromNode.rect, toNode.rect);
      endSide[i]   = _exitSide(toNode.rect, fromNode.rect);
    }

    // Count usage per (nodeId, side).
    // If a side overflows capacity, reassign excess edges to the side with the
    // most remaining capacity (avoids blindly piling onto the adjacent side).
    void assignWithCapacity(
      List<int> sideList, // per-edge side assignment (mutated in place)
      List<String> nodeIds, // nodeId per edge slot
    ) {
      // Build current counts
      final counts = <String, int>{}; // 'nodeId:side' -> count
      for (int i = 0; i < sideList.length; i++) {
        final k = '${nodeIds[i]}:${sideList[i]}';
        counts[k] = (counts[k] ?? 0) + 1;
      }
      // Detect overflows and reassign
      for (int i = 0; i < sideList.length; i++) {
        final nodeId = nodeIds[i];
        int side = sideList[i];
        final k = '$nodeId:$side';
        if ((counts[k] ?? 0) <= capacity(nodeId, side)) continue;
        // Overflow — pick the side with the most remaining capacity
        counts[k] = (counts[k]! - 1);
        int bestSide = side;
        int bestRoom = -1;
        for (int s = 0; s < 4; s++) {
          if (s == side) continue;
          final room = capacity(nodeId, s) - (counts['$nodeId:$s'] ?? 0);
          if (room > bestRoom) {
            bestRoom = room;
            bestSide = s;
          }
        }
        final k2 = '$nodeId:$bestSide';
        counts[k2] = (counts[k2] ?? 0) + 1;
        sideList[i] = bestSide;
      }
    }

    final startNodeIds = edges.map((e) => e.from).toList();
    final endNodeIds   = edges.map((e) => e.to).toList();
    assignWithCapacity(startSide, startNodeIds);
    assignWithCapacity(endSide,   endNodeIds);

    // Group by (nodeId, side) and assign evenly-spaced t values
    final startRel = List<Offset?>.filled(edges.length, null);
    final endRel   = List<Offset?>.filled(edges.length, null);

    // Build slot groups
    final startGroups = <String, List<int>>{}; // 'nodeId:side' -> [edgeIdx]
    final endGroups   = <String, List<int>>{};
    for (int i = 0; i < edges.length; i++) {
      startGroups.putIfAbsent('${edges[i].from}:${startSide[i]}', () => []).add(i);
      endGroups.putIfAbsent('${edges[i].to}:${endSide[i]}', () => []).add(i);
    }

    void distributeGroup(Map<String, List<int>> groups, List<Offset?> relList) {
      groups.forEach((key, indices) {
        final side = int.parse(key.split(':').last);
        final n = indices.length;
        for (int j = 0; j < n; j++) {
          final t = n == 1 ? 0.5 : j / (n - 1).toDouble();
          relList[indices[j]] = _sideToRelative(side, t);
        }
      });
    }

    distributeGroup(startGroups, startRel);
    distributeGroup(endGroups,   endRel);

    // Create shape objects
    for (final node in nodes.values) {
      final objectId = uuidMap[node.id]!;
      final rect = node.rect;

      if (node.type == 'circle') {
        drawingObjects.add(CircleObject(id: objectId, rect: rect, text: node.label).toJson());
      } else if (node.type == 'diamond') {
        drawingObjects.add(DiamondObject(id: objectId, rect: rect, text: node.label).toJson());
      } else if (node.type == 'parallelogram') {
        drawingObjects.add(ParallelogramObject(id: objectId, rect: rect, text: node.label).toJson());
      } else {
        drawingObjects.add(RectangleObject(id: objectId, rect: rect, text: node.label).toJson());
      }
    }

    // Create edges with distributed port positions
    for (int i = 0; i < edges.length; i++) {
      final edge = edges[i];
      final fromUuid = uuidMap[edge.from]!;
      final toUuid   = uuidMap[edge.to]!;
      final fromNode = nodes[edge.from]!;
      final toNode   = nodes[edge.to]!;

      final sRel = startRel[i] ?? const Offset(0.5, 1.0);
      final eRel = endRel[i]   ?? const Offset(0.5, 0.0);

      // Convert relative position to world position for start/end coords
      final start = fromNode.rect.topLeft + Offset(
        fromNode.rect.width  * sRel.dx,
        fromNode.rect.height * sRel.dy,
      );
      final end = toNode.rect.topLeft + Offset(
        toNode.rect.width  * eRel.dx,
        toNode.rect.height * eRel.dy,
      );

      final startAttachment = ObjectAttachment(objectId: fromUuid, relativePosition: sRel);
      final endAttachment   = ObjectAttachment(objectId: toUuid,   relativePosition: eRel);

      final lineStyle = edge.dashed ? LineStyle.dashed : LineStyle.solid;

      final edgeId = uuid.v4();
      if (edge.type == 'arrow') {
        drawingObjects.add(ArrowObject(
          id: edgeId,
          start: start,
          end: end,
          startAttachment: startAttachment,
          endAttachment: endAttachment,
          arrowLabel: edge.label,
          pathType: LinkPathType.orthogonal,
          lineStyle: lineStyle,
        ).toJson());
      } else {
        drawingObjects.add(LineObject(
          id: edgeId,
          start: start,
          end: end,
          startAttachment: startAttachment,
          endAttachment: endAttachment,
          lineStyle: lineStyle,
        ).toJson());
      }
    }

    return {
      'viewport': {'offset': [0.0, 0.0], 'zoom': 1.0},
      'nodes': <Map<String, dynamic>>[],
      'drawingObjects': drawingObjects,
    };
  }
}

/// Internal representation of a parsed Mermaid node.
class _MermaidNode {
  final String id;
  final String label;
  final String type; // 'rect', 'circle', 'diamond', or 'parallelogram'
  Rect rect;

  _MermaidNode(this.id, this.label, this.type) : rect = Rect.zero;
}

/// Internal representation of a parsed Mermaid edge.
class _MermaidEdge {
  final String from;
  final String to;
  final String type; // 'arrow' or 'line'
  final String? label;
  final bool dashed; // dotted connector (-.->)
  final bool thick; // thick connector (==>)

  _MermaidEdge({
    required this.from,
    required this.to,
    required this.type,
    this.label,
    this.dashed = false,
    this.thick = false,
  });
}

/// Internal representation of a parsed Mermaid subgraph (cluster).
class _MermaidSubgraph {
  final String title;
  final List<String> memberIds = <String>[];

  _MermaidSubgraph(this.title);
}
