import 'dart:convert';
import 'package:flow_draw/src/core/utils/renderbox.dart';
import 'package:flow_draw/src/core/utils/snackbar.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/entities.dart';
import 'package:flutter/services.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
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

  /// Marker key identifying clipboard payloads produced by [copyDrawingObjects].
  static const String _drawingClipboardKind = 'flow_draw/drawing-objects';

  /// Copies the given drawing objects to the system clipboard. Positions are
  /// stored relative to the selection's top-left so [prepareDrawingObjectsPaste]
  /// can re-anchor them at an arbitrary paste position. Returns the encoded
  /// payload, or null if [objects] is empty.
  static Future<String?> copyDrawingObjects(
      Iterable<DrawingObject> objects) async {
    final list = objects.toList();
    if (list.isEmpty) return null;

    // Anchor: top-left of the combined bounds, so paste is position-relative.
    Rect? bounds;
    for (final o in list) {
      bounds = bounds == null ? o.rect : bounds.expandToInclude(o.rect);
    }
    final anchor = (bounds ?? Rect.zero).topLeft;

    try {
      final payload = {
        'kind': _drawingClipboardKind,
        'anchor': [anchor.dx, anchor.dy],
        'objects': list.map((o) => o.toJson()).toList(),
      };
      final base64Data = base64Encode(utf8.encode(jsonEncode(payload)));
      await Clipboard.setData(ClipboardData(text: base64Data));
      showNodeEditorSnackbar('Copied.', SnackbarType.success);
      return base64Data;
    } catch (e) {
      showNodeEditorSnackbar('Failed to copy: $e', SnackbarType.error);
      return null;
    }
  }

  /// Decodes a [copyDrawingObjects] payload and returns fresh drawing objects
  /// with new IDs, positioned at [pastePosition] (the anchor maps to that
  /// point). Returns null if [clipboardContent] isn't a drawing-objects payload
  /// (e.g. plain text or node-clipboard data), so callers can fall back.
  static List<DrawingObject>? prepareDrawingObjectsPaste(
      String clipboardContent, Offset pastePosition) {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(base64Decode(clipboardContent)))
          as Map<String, dynamic>;
    } catch (_) {
      return null; // not our base64/JSON payload
    }
    if (payload['kind'] != _drawingClipboardKind) return null;

    final anchorList = (payload['anchor'] as List).cast<num>();
    final anchor = Offset(anchorList[0].toDouble(), anchorList[1].toDouble());
    final shift = pastePosition - anchor;

    final result = <DrawingObject>[];
    for (final json in (payload['objects'] as List)) {
      final obj = drawingObjectFromJson(json as Map<String, dynamic>);
      if (obj == null) continue;
      result.add(_reanchor(obj, shift));
    }
    return result.isEmpty ? null : result;
  }

  /// Returns a copy of [obj] with a new id, shifted by [shift]. Connectors have
  /// their attachments cleared (the originals' targets aren't part of the paste,
  /// so the pasted connector floats free at its shifted coordinates).
  static DrawingObject _reanchor(DrawingObject obj, Offset shift) {
    final newId = const Uuid().v4();
    if (obj is ArrowObject) {
      return ArrowObject(
        id: newId,
        start: obj.start + shift,
        end: obj.end + shift,
        midPoint: obj.midPoint == null ? null : obj.midPoint! + shift,
        pathType: obj.pathType,
        waypoints: obj.waypoints?.map((w) => w + shift).toList(),
        lineStyle: obj.lineStyle,
        angle: obj.angle,
        arrowLabel: obj.arrowLabel,
      );
    }
    if (obj is LineObject) {
      return LineObject(
        id: newId,
        start: obj.start + shift,
        end: obj.end + shift,
        midPoint: obj.midPoint == null ? null : obj.midPoint! + shift,
        lineStyle: obj.lineStyle,
        angle: obj.angle,
      );
    }
    if (obj is PencilStrokeObject) {
      return PencilStrokeObject(
        id: newId,
        points: obj.points
            .map((p) => PointVector(p.x + shift.dx, p.y + shift.dy, p.pressure))
            .toList(),
        angle: obj.angle,
      );
    }
    // Rect-based objects: round-trip through JSON (preserves all fields), re-id,
    // and shift the rect in the JSON (the base DrawingObject has no rect setter,
    // and the rect serializes as {left, top, width, height}).
    final json = Map<String, dynamic>.from(obj.toJson());
    json['id'] = newId;
    final rectJson = Map<String, dynamic>.from(json['rect'] as Map);
    rectJson['left'] = (rectJson['left'] as num).toDouble() + shift.dx;
    rectJson['top'] = (rectJson['top'] as num).toDouble() + shift.dy;
    json['rect'] = rectJson;
    return drawingObjectFromJson(json)!;
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