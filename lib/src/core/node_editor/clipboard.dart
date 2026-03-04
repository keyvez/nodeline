import 'dart:convert';
import 'package:flow_draw/src/core/utils/renderbox.dart';
import 'package:flow_draw/src/core/utils/snackbar.dart';
import 'package:flow_draw/src/models/entities.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// Calculates the encompassing rectangle of a set of nodes.
Rect calculateEncompassingRect(
    Set<String> ids,
    Map<String, NodeInstance> nodes, {
      double margin = 100.0,
    }) {
  if (ids.isEmpty) return Rect.zero;

  Rect? encompassingRect;
  for (final id in ids) {
    final node = nodes[id];
    if (node == null) continue;
    final nodeBounds = getNodeBoundsInWorld(node);
    if (nodeBounds == null) continue;

    if (encompassingRect == null) {
      encompassingRect = nodeBounds;
    } else {
      encompassingRect = encompassingRect.expandToInclude(nodeBounds);
    }
  }

  return (encompassingRect ?? Rect.zero).inflate(margin);
}

/// A service for handling clipboard operations.
/// It contains pure functions that operate on the provided state.
class ClipboardService {
  /// Copies the selected nodes and their internal links to the clipboard.
  static Future<String?> copySelection({
    required Map<String, NodeInstance> allNodes,
    required Set<String> selectedNodeIds,
    // Add other object types as needed
  }) async {
    if (selectedNodeIds.isEmpty) return null;

    final encompassingRect = calculateEncompassingRect(selectedNodeIds, allNodes);

    final List<Map<String, dynamic>> nodesToCopy = [];

    for (final id in selectedNodeIds) {
      final node = allNodes[id];
      if (node == null) continue;

      // Create a copy with a relative offset for pasting
      final relativeOffset = node.offset - encompassingRect.topLeft;
      final nodeCopy = node.copyWith(
        offset: relativeOffset,
        state: NodeState(isSelected: false, isCollapsed: node.state.isCollapsed),
      );
      nodesToCopy.add(nodeCopy.toJson());
    }

    try {
      final jsonData = {
        'nodes': nodesToCopy,
        // We could add drawing objects here in the future
      };
      final jsonString = jsonEncode(jsonData);
      final base64Data = base64Encode(utf8.encode(jsonString));
      await Clipboard.setData(ClipboardData(text: base64Data));
      showNodeEditorSnackbar('Selection copied.', SnackbarType.success);
      return base64Data;
    } catch (e) {
      showNodeEditorSnackbar('Failed to copy selection: $e', SnackbarType.error);
      return null;
    }
  }

  /// Deserializes clipboard data and prepares new node instances for pasting.
  static List<NodeInstance>? preparePaste(String clipboardContent, Offset pastePosition) {
    try {
      final jsonDataString = utf8.decode(base64Decode(clipboardContent));
      final jsonData = jsonDecode(jsonDataString) as Map<String, dynamic>;

      final nodesJson = jsonData['nodes'] as List<dynamic>;

      final idMap = <String, String>{};
      final List<NodeInstance> originalNodes = [];

      // First pass: create new instances and map old IDs to new UUIDs
      for (var nodeJson in nodesJson) {
        final originalNode = NodeInstance.fromJson(nodeJson);
        final newId = const Uuid().v4();
        idMap[originalNode.id] = newId;
        originalNodes.add(originalNode);
      }

      final List<NodeInstance> pastedNodes = [];
      for (final originalNode in originalNodes) {
        pastedNodes.add(
          originalNode.copyWith(
            id: idMap[originalNode.id], // Assign the new UUID
            offset: originalNode.offset + pastePosition,
          ),
        );
      }

      return pastedNodes;
    } catch (e) {
      showNodeEditorSnackbar('Failed to paste: Invalid clipboard data.', SnackbarType.error);
      return null;
    }
  }
}