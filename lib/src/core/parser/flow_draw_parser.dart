import 'dart:convert';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:nodeline/nodeline.dart';
import 'package:nodeline/src/models/drawing_entities.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class _ParsedObject {
  final String id;
  String type; // 'node', 'rect', 'circle', 'text', 'figure', 'group'
  final Map<String, String> attributes;
  final List<_ParsedObject> children;
  Rect rect; // This will be calculated during layout

  _ParsedObject(
    this.id,
    this.type,
    this.attributes, {
    this.children = const [],
    this.rect = Rect.zero,
  });
}

class _ParsedRelationship {
  final String sourceId;
  final String targetId;
  final String type; // 'arrow' or 'line'

  _ParsedRelationship(this.sourceId, this.targetId, this.type);
}

class FlowDrawParser {
  // Layout constants
  final double hSpacing = 80.0;
  final double vSpacing = 100.0;
  final double groupPadding = 30.0;
  final double nodePaddingHorizontal = 24.0;
  final double nodePaddingVertical = 16.0;
  final double minNodeWidth = 180.0;
  final double minNodeHeight = 80.0;

  final double baseCurveAmount = 20.0;
  final double proportionalCurveFactor =
      0.4; // A smaller factor for long arrows

  String parse(String sourceCode) {
    final cleanCode = sourceCode.replaceAll(
      RegExp(r'//.*$', multiLine: true),
      '',
    );

    final objects = <String, _ParsedObject>{};
    final relationships = <_ParsedRelationship>[];

    _parseDefinitions(cleanCode, objects);

    final relationshipLines = cleanCode
        .split('\n')
        .where((line) => line.contains('->') || line.contains('--'));
    for (final line in relationshipLines) {
      final rel = _parseRelationship(line.trim());
      if (rel != null) {
        final sourceExists =
            _findObjectInTree(objects.values.toList(), rel.sourceId) != null;
        final targetExists =
            _findObjectInTree(objects.values.toList(), rel.targetId) != null;
        if (!sourceExists || !targetExists) {
          throw FormatException("Relationship uses undefined ID: $line");
        }
        relationships.add(rel);
      }
    }

    _autoLayout(objects, relationships);

    return _buildJson(objects, relationships);
  }

  void _parseDefinitions(
    String sourceCode,
    Map<String, _ParsedObject> objects,
  ) {
    final lines = sourceCode.split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty || line.contains('->') || line.contains('--')) {
        i++;
        continue;
      }

      final match = RegExp(
        r'^(\w+)\s*(?:\[((?:[^\]"]|"[^"]*")*)\])?\s*({)?',
      ).firstMatch(line);
      if (match == null) {
        throw FormatException('Invalid syntax on line ${i + 1}: $line');
      }

      final id = match.group(1)!;
      final attributes = _parseAttributes(match.group(2));
      final isBlock = match.group(3) == '{';

      if (isBlock) {
        final block = _extractBlock(lines, i);
        final childrenMap = <String, _ParsedObject>{};
        _parseDefinitions(block.content, childrenMap);

        final isFigure = attributes['figure'] == 'true';
        final type = isFigure ? 'figure' : 'group';

        objects[id] = _ParsedObject(
          id,
          type,
          Map.from(attributes),
          children: childrenMap.values.toList(),
        );
        i += block.lineCount;
      } else {
        final type = attributes['shape'];
        if (type == null) {
          throw FormatException('Missing "shape" attribute for object "$id".');
        }
        objects[id] = _ParsedObject(id, type, Map.from(attributes));
        i++;
      }
    }
  }

  Map<String, String> _parseAttributes(String? attrString) {
    if (attrString == null || attrString.isEmpty) return {};
    final attributes = <String, String>{};
    final RegExp attrRegex = RegExp(r'(\w+)\s*:\s*("([^"]*)"|([\w.-]+))');
    attrRegex.allMatches(attrString).forEach((match) {
      final key = match.group(1)!;
      final value = match.group(3) ?? match.group(4)!.trim();
      attributes[key] = value;
    });
    return attributes;
  }

  ({String content, int lineCount}) _extractBlock(
    List<String> lines,
    int start,
  ) {
    final content = StringBuffer();
    int balance = 0;
    int lineCount = 0;
    for (int i = start; i < lines.length; i++) {
      lineCount++;
      final line = lines[i];
      balance += '{'.allMatches(line).length;
      balance -= '}'.allMatches(line).length;

      if (i == start) {
        final braceIndex = line.indexOf('{');
        if (braceIndex != -1) {
          content.writeln(line.substring(braceIndex + 1));
        }
      } else if (balance > 0 || (balance == 0 && line.contains('}'))) {
        final closingBraceIndex = line.lastIndexOf('}');
        if (balance == 0 && closingBraceIndex != -1) {
          content.writeln(line.substring(0, closingBraceIndex));
        } else {
          content.writeln(line);
        }
      }
      if (balance == 0) break;
    }
    return (content: content.toString(), lineCount: lineCount);
  }

  _ParsedRelationship? _parseRelationship(String line) {
    final match = RegExp(r'^(\w+)\s*(--|->)\s*(\w+)').firstMatch(line);
    if (match == null) return null;
    final type = match.group(2) == '->' ? 'arrow' : 'line';
    return _ParsedRelationship(match.group(1)!, match.group(3)!, type);
  }

  void _autoLayout(
    Map<String, _ParsedObject> objects,
    List<_ParsedRelationship> relationships,
  ) {
    for (final obj in objects.values) {
      _calculateObjectSizeRecursive(obj);
    }

    final topLevelIds = objects.keys.toList();
    var adj = {for (var id in topLevelIds) id: <String>[]};
    var parents = {for (var id in topLevelIds) id: <String>[]};

    for (final rel in relationships) {
      if (topLevelIds.contains(rel.sourceId) &&
          topLevelIds.contains(rel.targetId)) {
        adj[rel.sourceId]!.add(rel.targetId);
        parents[rel.targetId]!.add(rel.sourceId);
      }
    }

    final reversedEdges = <(String, String)>[];
    _detectAndRemoveCycles(topLevelIds, adj, reversedEdges);

    final layers = _assignLayers(topLevelIds, adj);

    _orderLayers(layers, adj, parents);

    _assignCoordinates(layers, objects);

    for (final edge in reversedEdges) {
      adj[edge.$1]!.add(edge.$2);
      adj[edge.$2]!.remove(edge.$1);
    }
  }

  void _detectAndRemoveCycles(
    List<String> nodes,
    Map<String, List<String>> adj,
    List<(String, String)> reversedEdges,
  ) {
    final visiting = <String>{};
    final visited = <String>{};
    for (final node in nodes) {
      if (!visited.contains(node)) {
        _dfsCycleCheck(node, adj, visiting, visited, reversedEdges);
      }
    }
  }

  void _dfsCycleCheck(
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

  Map<int, List<String>> _assignLayers(
    List<String> nodes,
    Map<String, List<String>> adj,
  ) {
    final layers = <int, List<String>>{};
    final nodeLayer = <String, int>{};

    for (final node in nodes) {
      nodeLayer[node] = 0;
    }

    bool changed = true;
    while (changed) {
      changed = false;
      for (final u in nodes) {
        for (final v in adj[u]!) {
          if (nodeLayer[v]! < nodeLayer[u]! + 1) {
            nodeLayer[v] = nodeLayer[u]! + 1;
            changed = true;
          }
        }
      }
    }

    for (final node in nodes) {
      layers.putIfAbsent(nodeLayer[node]!, () => []).add(node);
    }
    return layers;
  }

  void _orderLayers(
    Map<int, List<String>> layers,
    Map<String, List<String>> adj,
    Map<String, List<String>> parents,
  ) {
    final nodePositions = <String, int>{};
    for (int i = 0; i < layers.length; i++) {
      layers[i]!.forEachIndexed((index, node) {
        nodePositions[node] = index;
      });
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
                parentNodes.map((p) => nodePositions[p]!).sum /
                parentNodes.length;
          }
        }
        layers[i]!.sort((a, b) => barycenters[a]!.compareTo(barycenters[b]!));
        layers[i]!.forEachIndexed((index, node) => nodePositions[node] = index);
      }
      for (int i = layers.length - 2; i >= 0; i--) {
        final barycenters = <String, double>{};
        for (final u in layers[i]!) {
          final childrenNodes = adj[u]!;
          if (childrenNodes.isEmpty) {
            barycenters[u] = -1.0;
          } else {
            barycenters[u] =
                childrenNodes.map((c) => nodePositions[c]!).sum /
                childrenNodes.length;
          }
        }
        layers[i]!.sort((a, b) => barycenters[a]!.compareTo(barycenters[b]!));
        layers[i]!.forEachIndexed((index, node) => nodePositions[node] = index);
      }
    }
  }

  void _assignCoordinates(
    Map<int, List<String>> layers,
    Map<String, _ParsedObject> objects,
  ) {
    double currentY = 0;
    final layerWidths = <int, double>{};
    double maxGraphWidth = 0;

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i]!;
      double totalLayerWidth = (layer.length - 1) * hSpacing;
      for (final id in layer) {
        totalLayerWidth += objects[id]!.rect.width;
      }
      layerWidths[i] = totalLayerWidth;
      maxGraphWidth = max(maxGraphWidth, totalLayerWidth);
    }

    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i]!;
      double maxLayerHeight = 0;
      double currentX = -(layerWidths[i]! / 2);

      for (final id in layer) {
        final obj = objects[id]!;
        maxLayerHeight = max(maxLayerHeight, obj.rect.height);
        obj.rect = Rect.fromLTWH(
          currentX,
          currentY,
          obj.rect.width,
          obj.rect.height,
        );
        currentX += obj.rect.width + hSpacing;
      }
      currentY += maxLayerHeight + vSpacing;
    }
  }

  void _calculateObjectSizeRecursive(_ParsedObject obj) {
    if (obj.type == 'group' || obj.type == 'figure') {
      double childrenMaxWidth = 0;
      double childrenTotalHeight = 0;

      if (obj.children.isNotEmpty) {
        for (final child in obj.children) {
          _calculateObjectSizeRecursive(child);
          childrenMaxWidth = max(childrenMaxWidth, child.rect.width);
        }

        double currentInternalY = groupPadding;
        for (final child in obj.children) {
          final childX =
              (childrenMaxWidth - child.rect.width) / 2 + groupPadding;
          child.rect = Rect.fromLTWH(
            childX,
            currentInternalY,
            child.rect.width,
            child.rect.height,
          );
          currentInternalY += child.rect.height + vSpacing / 2;
        }
        childrenTotalHeight = currentInternalY - vSpacing / 2;
      }

      final width = max(minNodeWidth, childrenMaxWidth + 2 * groupPadding);
      final height = max(minNodeHeight, childrenTotalHeight + groupPadding);
      obj.rect = Rect.fromLTWH(0, 0, width, height);
    } else {
      final heading = obj.attributes['heading'];
      final text = obj.attributes['text'] ?? obj.attributes['value'];

      double calculatedWidth = 0;
      double calculatedHeight = 0;

      if (heading != null) {
        final painter = TextPainter(
          text: TextSpan(
            text: heading,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        calculatedWidth = max(calculatedWidth, painter.width);
        calculatedHeight += painter.height;
      }

      if (text != null) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: const TextStyle(fontSize: 14)),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout(maxWidth: minNodeWidth * 1.5);
        calculatedWidth = max(calculatedWidth, painter.width);
        calculatedHeight += (heading != null ? 8 : 0) + painter.height;
      }

      final finalWidth = max(
        minNodeWidth,
        calculatedWidth + nodePaddingHorizontal * 2,
      );
      final finalHeight = max(
        minNodeHeight,
        calculatedHeight + nodePaddingVertical * 2,
      );
      obj.rect = Rect.fromLTWH(0, 0, finalWidth, finalHeight);
    }
  }

  String _buildJson(
    Map<String, _ParsedObject> objects,
    List<_ParsedRelationship> relationships,
  ) {
    final List<Map<String, dynamic>> finalNodes = [];
    final List<Map<String, dynamic>> finalDrawingObjects = [];

    for (final obj in objects.values) {
      _convertObjectToJson(obj, finalNodes, finalDrawingObjects, Offset.zero);
    }

    bool bendToggle = true;
    for (final rel in relationships) {
      final id = const Uuid().v4();
      final sourceObj = _findObjectInTree(
        objects.values.toList(),
        rel.sourceId,
      );
      final targetObj = _findObjectInTree(
        objects.values.toList(),
        rel.targetId,
      );

      if (sourceObj == null || targetObj == null) continue;

      final sourceAbsRect = _getAbsoluteRect(
        objects.values.toList(),
        sourceObj.id,
      );
      final targetAbsRect = _getAbsoluteRect(
        objects.values.toList(),
        targetObj.id,
      );

      final startAttachment = ObjectAttachment(
        objectId: sourceObj.id,
        relativePosition: _getAttachmentPoint(sourceAbsRect, targetAbsRect),
      );
      final endAttachment = ObjectAttachment(
        objectId: targetObj.id,
        relativePosition: _getAttachmentPoint(targetAbsRect, sourceAbsRect),
      );

      final start = sourceAbsRect.center;
      final end = targetAbsRect.center;

      if (rel.type == 'arrow') {
        final geometricMidpoint = (start + end) / 2;
        final distance = (end - start).distance;
        final direction = bendToggle ? 1 : -1;

        final curveAmount = max(
          baseCurveAmount,
          distance *
              (distance > 500
                  ? proportionalCurveFactor
                  : proportionalCurveFactor * 0.5),
        );

        Offset controlPointOffset;
        final dy = (end.dy - start.dy).abs();
        final dx = (end.dx - start.dx).abs();

        if (dy > dx) {
          controlPointOffset = Offset(curveAmount * direction, 0);
        } else {
          controlPointOffset = Offset(0, curveAmount * direction);
        }

        final controlPoint = geometricMidpoint + controlPointOffset;
        bendToggle = !bendToggle;

        final arrow = ArrowObject(
          id: id,
          start: start,
          end: end,
          startAttachment: startAttachment,
          endAttachment: endAttachment,
          midPoint: controlPoint,
        );
        finalDrawingObjects.add(arrow.toJson());
      } else {
        final line = LineObject(
          id: id,
          start: start,
          end: end,
          startAttachment: startAttachment,
          endAttachment: endAttachment,
        );
        finalDrawingObjects.add(line.toJson());
      }
    }

    final project = {
      'viewport': {
        'offset': [0.0, 0.0],
        'zoom': 1.0,
      },
      'nodes': finalNodes,
      'drawingObjects': finalDrawingObjects,
    };
    return jsonEncode(project);
  }

  void _convertObjectToJson(
    _ParsedObject obj,
    List<Map<String, dynamic>> finalNodes,
    List<Map<String, dynamic>> finalDrawingObjects,
    Offset parentOffset,
  ) {
    final currentOffset = obj.rect.topLeft + parentOffset;
    final currentRect = currentOffset & obj.rect.size;

    switch (obj.type) {
      case 'node':
        final node = NodeInstance(
          id: obj.id,
          state: NodeState(),
          offset: currentOffset,
          heading: obj.attributes['heading'],
          value: obj.attributes['text'] ?? obj.attributes['value'],
        );
        finalNodes.add(node.toJson());
        break;

      case 'group':
        final groupObject = RectangleObject(id: obj.id, rect: currentRect);
        finalDrawingObjects.add(groupObject.toJson());
        if (obj.attributes.containsKey('label')) {
          _addLabelForGroup(obj, currentRect, finalDrawingObjects);
        }
        for (final child in obj.children) {
          _convertObjectToJson(
            child,
            finalNodes,
            finalDrawingObjects,
            currentOffset,
          );
        }
        break;

      case 'figure':
        final childrenIds = obj.children.map((c) => c.id).toSet();
        final figure = FigureObject(
          id: obj.id,
          rect: currentRect,
          label: obj.attributes['label'] ?? obj.id,
          childrenIds: childrenIds,
        );
        finalDrawingObjects.add(figure.toJson());
        for (final child in obj.children) {
          _convertObjectToJson(
            child,
            finalNodes,
            finalDrawingObjects,
            currentOffset,
          );
        }
        break;

      default:
        final textContent = obj.attributes['text'];
        final dobj = _createDrawingObject(obj, obj.id, currentRect);
        finalDrawingObjects.add(dobj.toJson());

        if (textContent != null && obj.type != 'text') {
          final textPainter = TextPainter(
            text: TextSpan(
              text: textContent,
              style: const TextStyle(fontSize: 14),
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: currentRect.width - nodePaddingHorizontal);
          final textSize = textPainter.size;
          final textAreaWidth = min(
            currentRect.width - nodePaddingHorizontal,
            textSize.width,
          );
          final textAreaHeight = min(
            currentRect.height - nodePaddingVertical,
            textSize.height,
          );

          final textRect = Rect.fromCenter(
            center: currentRect.center,
            width: textAreaWidth,
            height: textAreaHeight,
          );
          final textObject = TextObject(
            id: const Uuid().v4(),
            rect: textRect,
            text: textContent,
            style: const TextStyle(fontSize: 14, color: Colors.white),
          );
          finalDrawingObjects.add(textObject.toJson());
        }
        break;
    }
  }

  void _addLabelForGroup(
    _ParsedObject group,
    Rect groupRect,
    List<Map<String, dynamic>> finalDrawingObjects,
  ) {
    final labelText = group.attributes['label']!;
    final alignmentStr = group.attributes['labelAlignment'] ?? 'topCenter';
    final alignment = _parseAlignment(alignmentStr);
    final double labelPadding = 10.0;

    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final textSize = textPainter.size;

    double labelY;
    double labelX =
        groupRect.left +
        alignment.alongSize(groupRect.size).dx -
        textSize.width / 2;

    if (alignmentStr.contains('top')) {
      labelY = groupRect.top + labelPadding;
    } else if (alignmentStr.contains('bottom')) {
      labelY = groupRect.bottom - textSize.height - labelPadding;
    } else {
      labelY = groupRect.center.dy - textSize.height / 2;
    }

    if (alignmentStr.contains('Left')) {
      labelX = groupRect.left + labelPadding;
    } else if (alignmentStr.contains('Right')) {
      labelX = groupRect.right - textSize.width - labelPadding;
    }

    final textRect = Rect.fromLTWH(
      labelX,
      labelY,
      textSize.width,
      textSize.height,
    );

    final textObject = TextObject(
      id: const Uuid().v4(),
      rect: textRect,
      text: labelText,
    );
    finalDrawingObjects.add(textObject.toJson());
  }

  Alignment _parseAlignment(String alignmentStr) {
    switch (alignmentStr) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'topCenter':
        return Alignment.topCenter;
      case 'topRight':
        return Alignment.topRight;
      case 'centerLeft':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'centerRight':
        return Alignment.centerRight;
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'bottomCenter':
        return Alignment.bottomCenter;
      case 'bottomRight':
        return Alignment.bottomRight;
      default:
        return Alignment.topCenter;
    }
  }

  _ParsedObject? _findObjectInTree(
    List<_ParsedObject> objects,
    String id, {
    Offset parentOffset = Offset.zero,
  }) {
    for (final obj in objects) {
      if (obj.id == id) {
        return _ParsedObject(
          obj.id,
          obj.type,
          obj.attributes,
          children: obj.children,
          rect: obj.rect.shift(parentOffset),
        );
      }
      if (obj.children.isNotEmpty) {
        final found = _findObjectInTree(
          obj.children,
          id,
          parentOffset: obj.rect.topLeft + parentOffset,
        );
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  Rect _getAbsoluteRect(List<_ParsedObject> topLevelObjects, String id) {
    final obj = _findObjectInTree(topLevelObjects, id);
    return obj?.rect ?? Rect.zero;
  }

  DrawingObject _createDrawingObject(_ParsedObject obj, String id, Rect rect) {
    switch (obj.type) {
      case 'rect':
        return RectangleObject(id: id, rect: rect);
      case 'circle':
        return CircleObject(id: id, rect: rect);
      case 'text':
        return TextObject(
          id: id,
          rect: rect,
          text: obj.attributes['text'] ?? 'Text',
        );
      default:
        throw 'Unsupported object type in _createDrawingObject: ${obj.type}';
    }
  }

  Offset _getAttachmentPoint(Rect sourceRect, Rect targetRect) {
    final dx = targetRect.center.dx - sourceRect.center.dx;
    final dy = targetRect.center.dy - sourceRect.center.dy;

    final angle = atan2(dy, dx);
    const piOver4 = pi / 4;

    if (angle > -piOver4 && angle <= piOver4) {
      return const Offset(1.0, 0.5); // Right
    } else if (angle > piOver4 && angle <= 3 * piOver4) {
      return const Offset(0.5, 1.0); // Bottom
    } else if (angle > 3 * piOver4 || angle <= -3 * piOver4) {
      return const Offset(0.0, 0.5); // Left
    } else {
      return const Offset(0.5, 0.0); // Top
    }
  }
}
