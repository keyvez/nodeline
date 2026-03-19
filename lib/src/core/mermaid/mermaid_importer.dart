import 'dart:math';

import 'package:flow_draw/src/models/drawing_entities.dart';
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

  /// Parses a Mermaid flowchart string and returns project JSON
  /// consumable by `controller.loadProject()`.
  static Map<String, dynamic> import(String mermaid) {
    final lines = mermaid.split('\n').map((l) => l.trim()).toList();

    // Parse direction from header
    // Unused for now but parsed for completeness
    // String direction = 'TD';
    int startLine = 0;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final headerMatch = RegExp(r'^flowchart\s+(TD|TB|LR|BT|RL)\s*$').firstMatch(line);
      if (headerMatch != null) {
        // direction = headerMatch.group(1)!;
        startLine = i + 1;
        break;
      }
      // Also accept just "flowchart" without direction
      if (RegExp(r'^flowchart\s*$').hasMatch(line)) {
        startLine = i + 1;
        break;
      }
    }

    // Parse nodes and edges
    final nodes = <String, _MermaidNode>{};
    final edges = <_MermaidEdge>[];

    for (int i = startLine; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty || line.startsWith('%%')) continue;

      // Try to parse as edge first
      final edge = _parseEdge(line, nodes);
      if (edge != null) {
        edges.add(edge);
        continue;
      }

      // Try to parse as node declaration
      _parseNodeDeclaration(line, nodes);
    }

    // Auto-layout
    _autoLayout(nodes, edges);

    // Build project JSON
    return _buildProjectJson(nodes, edges);
  }

  /// Parses an edge line like `A --> B` or `A -->|label| B` or `A --- B`.
  static _MermaidEdge? _parseEdge(String line, Map<String, _MermaidNode> nodes) {
    // Match: ID --> ID, ID --- ID, ID -->|label| ID
    // Also handle node declarations inline: A["text"] --> B(("text"))
    final edgePattern = RegExp(
      r'^(\S+?)(?:\[/.*?/\]|\[.*?\]|\(\(.*?\)\)|\{.*?\}|\(\[.*?\]\))?\s*'
      r'(-->|---)'
      r'(?:\|([^|]*)\|)?\s*'
      r'(\S+?)(?:\[/.*?/\]|\[.*?\]|\(\(.*?\)\)|\{.*?\}|\(\[.*?\]\))?$',
    );

    final match = edgePattern.firstMatch(line);
    if (match == null) return null;

    final fromId = match.group(1)!;
    final edgeType = match.group(2)!;
    final edgeLabel = match.group(3);
    final toId = match.group(4)!;

    // Parse inline node declarations from the full line
    _parseInlineNode(line, fromId, nodes);
    _parseInlineNode(line, toId, nodes);

    // Ensure nodes exist
    nodes.putIfAbsent(fromId, () => _MermaidNode(fromId, fromId, 'rect'));
    nodes.putIfAbsent(toId, () => _MermaidNode(toId, toId, 'rect'));

    return _MermaidEdge(
      from: fromId,
      to: toId,
      type: edgeType == '-->' ? 'arrow' : 'line',
      label: edgeLabel,
    );
  }

  /// Tries to extract an inline node declaration from an edge line.
  static void _parseInlineNode(String line, String nodeId, Map<String, _MermaidNode> nodes) {
    if (nodes.containsKey(nodeId)) return;

    // Look for nodeId followed by shape syntax
    final patterns = [
      // Circle: A(("text"))
      RegExp(RegExp.escape(nodeId) + r'\(\("([^"]*)"\)\)'),
      // Rectangle: A["text"]
      RegExp(RegExp.escape(nodeId) + r'\["([^"]*)"\]'),
      // Diamond: A{"text"}
      RegExp(RegExp.escape(nodeId) + r'\{"([^"]*)"\}'),
      // Stadium: A(["text"])
      RegExp(RegExp.escape(nodeId) + r'\(\["([^"]*)"\]\)'),
      // Parallelogram: A[/"text"/]
      RegExp(RegExp.escape(nodeId) + r'\[/"([^"]*)"/\]'),
    ];
    final types = ['circle', 'rect', 'diamond', 'rect', 'parallelogram'];

    for (int i = 0; i < patterns.length; i++) {
      final match = patterns[i].firstMatch(line);
      if (match != null) {
        final label = match.group(1) ?? nodeId;
        nodes[nodeId] = _MermaidNode(nodeId, label, types[i]);
        return;
      }
    }
  }

  /// Parses a standalone node declaration line.
  static void _parseNodeDeclaration(String line, Map<String, _MermaidNode> nodes) {
    // Circle: A(("text"))
    final circleMatch = RegExp(r'^(\w+)\(\("([^"]*)"\)\)$').firstMatch(line);
    if (circleMatch != null) {
      final id = circleMatch.group(1)!;
      final label = circleMatch.group(2)!;
      nodes[id] = _MermaidNode(id, label, 'circle');
      return;
    }

    // Rectangle: A["text"]
    final rectMatch = RegExp(r'^(\w+)\["([^"]*)"\]$').firstMatch(line);
    if (rectMatch != null) {
      final id = rectMatch.group(1)!;
      final label = rectMatch.group(2)!;
      nodes[id] = _MermaidNode(id, label, 'rect');
      return;
    }

    // Diamond: A{"text"}
    final diamondMatch = RegExp(r'^(\w+)\{"([^"]*)"\}$').firstMatch(line);
    if (diamondMatch != null) {
      final id = diamondMatch.group(1)!;
      final label = diamondMatch.group(2)!;
      nodes[id] = _MermaidNode(id, label, 'diamond');
      return;
    }

    // Stadium: A(["text"])
    final stadiumMatch = RegExp(r'^(\w+)\(\["([^"]*)"\]\)$').firstMatch(line);
    if (stadiumMatch != null) {
      final id = stadiumMatch.group(1)!;
      final label = stadiumMatch.group(2)!;
      nodes[id] = _MermaidNode(id, label, 'rect');
      return;
    }

    // Parallelogram: A[/"text"/]
    final paraMatch = RegExp(r'^(\w+)\[/"([^"]*)"/\]$').firstMatch(line);
    if (paraMatch != null) {
      final id = paraMatch.group(1)!;
      final label = paraMatch.group(2)!;
      nodes[id] = _MermaidNode(id, label, 'parallelogram');
      return;
    }

    // Plain node: A or A["text"] already handled above
  }

  /// DAG layering auto-layout (replicates FlowDrawParser._autoLayout pattern).
  static void _autoLayout(Map<String, _MermaidNode> nodes, List<_MermaidEdge> edges) {
    // Calculate node sizes
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

    // Detect and remove cycles
    final reversedEdges = <(String, String)>[];
    _detectAndRemoveCycles(nodeIds, adj, reversedEdges);

    // Assign layers
    final layers = _assignLayers(nodeIds, adj);

    // Order layers to minimize crossings
    _orderLayers(layers, adj, parents);

    // Assign coordinates
    _assignCoordinates(layers, nodes);

    // Restore reversed edges
    for (final edge in reversedEdges) {
      adj[edge.$1]!.add(edge.$2);
      adj[edge.$2]!.remove(edge.$1);
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

  static void _assignCoordinates(
    Map<int, List<String>> layers,
    Map<String, _MermaidNode> nodes,
  ) {
    double currentY = 0;
    final layerWidths = <int, double>{};
    double maxGraphWidth = 0;

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i]!;
      double totalLayerWidth = (layer.length - 1) * _hSpacing;
      for (final id in layer) {
        totalLayerWidth += nodes[id]!.rect.width;
      }
      layerWidths[i] = totalLayerWidth;
      maxGraphWidth = max(maxGraphWidth, totalLayerWidth);
    }

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i]!;
      double maxLayerHeight = 0;
      double currentX = -(layerWidths[i]! / 2);

      for (final id in layer) {
        final node = nodes[id]!;
        maxLayerHeight = max(maxLayerHeight, node.rect.height);
        node.rect = Rect.fromLTWH(
          currentX,
          currentY,
          node.rect.width,
          node.rect.height,
        );
        currentX += node.rect.width + _hSpacing;
      }
      currentY += maxLayerHeight + _vSpacing;
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

  /// Builds the final project JSON from parsed nodes and edges.
  static Map<String, dynamic> _buildProjectJson(
    Map<String, _MermaidNode> nodes,
    List<_MermaidEdge> edges,
  ) {
    final drawingObjects = <Map<String, dynamic>>[];
    const uuid = Uuid();

    // Generate UUIDs for each mermaid node
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
        ).toJson());
      } else {
        drawingObjects.add(LineObject(
          id: edgeId,
          start: start,
          end: end,
          startAttachment: startAttachment,
          endAttachment: endAttachment,
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

  _MermaidEdge({required this.from, required this.to, required this.type, this.label});
}
