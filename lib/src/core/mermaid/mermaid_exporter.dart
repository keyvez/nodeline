import 'package:flow_draw/src/models/drawing_entities.dart';

/// Converts flow_draw canvas drawing objects into a Mermaid flowchart string.
class MermaidExporter {
  /// Exports drawing objects to a Mermaid flowchart string.
  ///
  /// If [selectedIds] is non-empty, only those objects and their connecting
  /// arrows/lines are exported. Otherwise all objects are exported.
  static String export(
    Map<String, DrawingObject> drawingObjects, {
    Set<String>? selectedIds,
  }) {
    final objects = drawingObjects.values.toList();

    // Collect shape objects (rectangles, circles)
    final shapes = <DrawingObject>[];
    final arrows = <ArrowObject>[];
    final lines = <LineObject>[];
    final texts = <TextObject>[];

    for (final obj in objects) {
      if (obj is RectangleObject) {
        shapes.add(obj);
      } else if (obj is CircleObject) {
        shapes.add(obj);
      } else if (obj is ArrowObject) {
        arrows.add(obj);
      } else if (obj is LineObject) {
        lines.add(obj);
      } else if (obj is TextObject) {
        texts.add(obj);
      }
    }

    // If selectedIds is provided, filter to only selected shapes + their edges
    Set<String>? filterIds;
    if (selectedIds != null && selectedIds.isNotEmpty) {
      filterIds = Set<String>.from(selectedIds);

      // Include arrows/lines that connect selected shapes
      for (final arrow in arrows) {
        final startId = arrow.startAttachment?.objectId;
        final endId = arrow.endAttachment?.objectId;
        if (startId != null && endId != null) {
          if (filterIds.contains(startId) || filterIds.contains(endId)) {
            filterIds.add(arrow.id);
            filterIds.add(startId);
            filterIds.add(endId);
          }
        }
      }
      for (final line in lines) {
        final startId = line.startAttachment?.objectId;
        final endId = line.endAttachment?.objectId;
        if (startId != null && endId != null) {
          if (filterIds.contains(startId) || filterIds.contains(endId)) {
            filterIds.add(line.id);
            filterIds.add(startId);
            filterIds.add(endId);
          }
        }
      }
    }

    // Build UUID → short ID mapping
    final idMap = <String, String>{};
    int idCounter = 0;
    for (final shape in shapes) {
      if (filterIds != null && !filterIds.contains(shape.id)) continue;
      idMap[shape.id] = _shortId(idCounter++);
    }

    // Find text objects that overlap with shapes (labels)
    final shapeLabels = <String, String>{};
    for (final shape in shapes) {
      if (!idMap.containsKey(shape.id)) continue;

      // Check for inline text property first
      if (shape is RectangleObject && shape.text != null && shape.text!.isNotEmpty) {
        shapeLabels[shape.id] = shape.text!;
        continue;
      }
      if (shape is CircleObject && shape.text != null && shape.text!.isNotEmpty) {
        shapeLabels[shape.id] = shape.text!;
        continue;
      }

      // Check for overlapping TextObject
      final shapeRect = shape.rect;
      for (final text in texts) {
        if (shapeRect.overlaps(text.rect)) {
          shapeLabels[shape.id] = text.text;
          break;
        }
      }
    }

    final buffer = StringBuffer();
    buffer.writeln('flowchart TD');

    // Track which shapes appear in edges
    final shapesInEdges = <String>{};

    // Emit edges
    for (final arrow in arrows) {
      if (filterIds != null && !filterIds.contains(arrow.id)) continue;
      final startId = arrow.startAttachment?.objectId;
      final endId = arrow.endAttachment?.objectId;
      if (startId == null || endId == null) continue;
      final from = idMap[startId];
      final to = idMap[endId];
      if (from == null || to == null) continue;
      shapesInEdges.add(startId);
      shapesInEdges.add(endId);
      buffer.writeln('    $from --> $to');
    }

    for (final line in lines) {
      if (filterIds != null && !filterIds.contains(line.id)) continue;
      final startId = line.startAttachment?.objectId;
      final endId = line.endAttachment?.objectId;
      if (startId == null || endId == null) continue;
      final from = idMap[startId];
      final to = idMap[endId];
      if (from == null || to == null) continue;
      shapesInEdges.add(startId);
      shapesInEdges.add(endId);
      buffer.writeln('    $from --- $to');
    }

    // Emit node declarations (for shapes with labels or standalone shapes)
    for (final shape in shapes) {
      if (!idMap.containsKey(shape.id)) continue;
      final shortId = idMap[shape.id]!;
      final label = shapeLabels[shape.id];

      if (label != null) {
        // Emit with label
        buffer.writeln('    ${_nodeDeclaration(shortId, label, shape)}');
      } else if (!shapesInEdges.contains(shape.id)) {
        // Standalone shape without label — still declare it
        buffer.writeln('    ${_nodeDeclaration(shortId, shortId, shape)}');
      }
    }

    // Emit standalone text objects as comments
    for (final text in texts) {
      if (filterIds != null && !filterIds.contains(text.id)) continue;
      // Skip texts that are labels for shapes
      bool isLabel = false;
      for (final shape in shapes) {
        if (idMap.containsKey(shape.id) && shape.rect.overlaps(text.rect)) {
          isLabel = true;
          break;
        }
      }
      if (!isLabel) {
        buffer.writeln('    %% text: ${text.text}');
      }
    }

    return buffer.toString().trimRight();
  }

  /// Generates a short alphabetical ID: A, B, ... Z, AA, AB, ...
  static String _shortId(int index) {
    final buffer = StringBuffer();
    int n = index;
    do {
      buffer.write(String.fromCharCode(65 + (n % 26)));
      n = (n ~/ 26) - 1;
    } while (n >= 0);
    // Reverse since we built it backwards
    return buffer.toString().split('').reversed.join();
  }

  /// Returns Mermaid node declaration syntax based on shape type.
  static String _nodeDeclaration(String id, String label, DrawingObject shape) {
    final escaped = _escapeLabel(label);
    if (shape is CircleObject) {
      return '$id(("$escaped"))';
    }
    // Default: rectangle
    return '$id["$escaped"]';
  }

  /// Escapes special Mermaid characters in labels.
  static String _escapeLabel(String label) {
    return label.replaceAll('"', '#quot;');
  }
}
