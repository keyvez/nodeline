import 'dart:collection';

import 'package:flow_draw/src/models/drawing_entities.dart';

/// Result of a workflow validation pass.
class WorkflowValidationResult {
  /// Whether every path from a start node reaches an end node and the graph
  /// is fully connected.
  final bool isValid;

  /// IDs of shape nodes that are not reachable from any start node, or that
  /// cannot reach any end node.
  final List<String> disconnectedNodes;

  /// IDs of shapes with no incoming arrows (entry points).
  final List<String> startNodes;

  /// IDs of shapes with no outgoing arrows (terminal points).
  final List<String> endNodes;

  const WorkflowValidationResult({
    required this.isValid,
    required this.disconnectedNodes,
    required this.startNodes,
    required this.endNodes,
  });
}

/// Validates a workflow graph built from [DrawingObject] instances.
///
/// A valid workflow satisfies:
/// 1. At least one start node (shape with no incoming arrows) exists.
/// 2. At least one end node (shape with no outgoing arrows) exists.
/// 3. Every shape node is reachable from at least one start node.
/// 4. Every shape node can reach at least one end node.
class WorkflowValidator {
  /// Validates the workflow represented by the given drawing objects.
  ///
  /// [objects] is the full map of drawing object IDs to objects, typically
  /// obtained from `CanvasBloc.state.drawingObjects`.
  static WorkflowValidationResult validateWorkflow(
    Map<String, DrawingObject> objects,
  ) {
    // Collect shape IDs (non-arrow, non-line objects).
    final shapeIds = <String>{};
    for (final obj in objects.values) {
      if (obj is! ArrowObject && obj is! LineObject && obj is! PencilStrokeObject) {
        shapeIds.add(obj.id);
      }
    }

    if (shapeIds.isEmpty) {
      return const WorkflowValidationResult(
        isValid: true,
        disconnectedNodes: [],
        startNodes: [],
        endNodes: [],
      );
    }

    // Build adjacency information from arrows.
    // outgoing[shapeId] = set of shape IDs this shape points to.
    // incoming[shapeId] = set of shape IDs that point to this shape.
    final outgoing = <String, Set<String>>{
      for (final id in shapeIds) id: <String>{},
    };
    final incoming = <String, Set<String>>{
      for (final id in shapeIds) id: <String>{},
    };

    for (final obj in objects.values) {
      if (obj is ArrowObject) {
        final fromId = obj.startAttachment?.objectId;
        final toId = obj.endAttachment?.objectId;

        if (fromId != null &&
            toId != null &&
            shapeIds.contains(fromId) &&
            shapeIds.contains(toId)) {
          outgoing[fromId]!.add(toId);
          incoming[toId]!.add(fromId);
        }
      }
    }

    // Identify start nodes (no incoming arrows) and end nodes (no outgoing arrows).
    final startNodes = <String>[
      for (final id in shapeIds)
        if (incoming[id]!.isEmpty) id,
    ];

    final endNodes = <String>[
      for (final id in shapeIds)
        if (outgoing[id]!.isEmpty) id,
    ];

    // BFS forward from all start nodes to find reachable shapes.
    final reachableFromStart = _bfs(startNodes, outgoing);

    // BFS backward from all end nodes to find shapes that can reach an end.
    final canReachEnd = _bfs(endNodes, incoming);

    // A shape is disconnected if it is not reachable from any start node OR
    // it cannot reach any end node.
    final disconnected = <String>[
      for (final id in shapeIds)
        if (!reachableFromStart.contains(id) || !canReachEnd.contains(id)) id,
    ];

    final isValid = disconnected.isEmpty &&
        startNodes.isNotEmpty &&
        endNodes.isNotEmpty;

    return WorkflowValidationResult(
      isValid: isValid,
      disconnectedNodes: disconnected,
      startNodes: startNodes,
      endNodes: endNodes,
    );
  }

  /// Breadth-first search starting from [seeds] following edges in [adj].
  static Set<String> _bfs(
    List<String> seeds,
    Map<String, Set<String>> adj,
  ) {
    final visited = <String>{};
    final queue = Queue<String>();
    for (final seed in seeds) {
      if (adj.containsKey(seed)) {
        visited.add(seed);
        queue.add(seed);
      }
    }
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final neighbor in adj[current] ?? <String>{}) {
        if (visited.add(neighbor)) {
          queue.add(neighbor);
        }
      }
    }
    return visited;
  }
}
