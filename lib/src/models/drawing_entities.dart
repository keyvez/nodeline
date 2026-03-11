import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flow_draw/src/core/utils/json_extensions.dart';
import 'package:flow_draw/src/models/styles.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

enum EditorTool {
  arrow,
  square,
  circle,
  diamond,
  arrowTopRight,
  line,
  pencil,
  text,
  figure,
  comment,
  add,
}

enum Handle {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  // For Arrow-based objects
  arrowStart,
  arrowEnd,
  midPoint,
  rotate,
  // For no handle
  none,
}

enum LinkPathType { straight, orthogonal }

abstract class DrawingObject {
  final String id;
  bool isSelected;
  final double angle;

  DrawingObject({required this.id, this.isSelected = false, this.angle = 0.0});

  Rect get rect;

  Map<String, dynamic> toJson();

  DrawingObject copyWith({bool? isSelected, double? angle});
}

class RectangleObject extends DrawingObject {
  Rect _rect;
  String? text;
  TextStyle? textStyle;
  bool isEditing;
  final LineStyle lineStyle;

  RectangleObject({required super.id, required Rect rect, super.isSelected, super.angle, this.text, this.textStyle, this.isEditing = false, this.lineStyle = LineStyle.solid})
    : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'rectangle',
    'rect': _rect.toJson(),
    'isSelected': isSelected,
    'angle': angle,
    if (text != null) 'text': text,
    if (textStyle != null) 'textStyle': {
      'fontSize': textStyle!.fontSize,
      'color': textStyle!.color?.value,
    },
    'lineStyle': lineStyle.name,
  };

  factory RectangleObject.fromJson(Map<String, dynamic> json) {
    TextStyle? style;
    if (json['textStyle'] != null) {
      final ts = json['textStyle'] as Map<String, dynamic>;
      style = TextStyle(
        fontSize: (ts['fontSize'] as num?)?.toDouble(),
        color: ts['color'] != null ? Color(ts['color'] as int) : null,
      );
    }
    return RectangleObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      text: json['text'] as String?,
      textStyle: style,
      lineStyle: json['lineStyle'] != null ? LineStyle.values.byName(json['lineStyle']) : LineStyle.solid,
    );
  }

  @override
  DrawingObject copyWith({Rect? rect, bool? isSelected, double? angle, LineStyle? lineStyle, bool? isEditing}) {
    return RectangleObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      text: text,
      textStyle: textStyle,
      lineStyle: lineStyle ?? this.lineStyle,
      isEditing: isEditing ?? this.isEditing,
    );
  }
}

class CircleObject extends DrawingObject {
  Rect _rect;
  String? text;
  TextStyle? textStyle;
  bool isEditing;
  final LineStyle lineStyle;

  CircleObject({required super.id, required Rect rect, super.isSelected, super.angle, this.text, this.textStyle, this.isEditing = false, this.lineStyle = LineStyle.solid})
    : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'circle',
    'rect': _rect.toJson(),
    'isSelected': isSelected,
    'angle': angle,
    if (text != null) 'text': text,
    if (textStyle != null) 'textStyle': {
      'fontSize': textStyle!.fontSize,
      'color': textStyle!.color?.value,
    },
    'lineStyle': lineStyle.name,
  };

  factory CircleObject.fromJson(Map<String, dynamic> json) {
    TextStyle? style;
    if (json['textStyle'] != null) {
      final ts = json['textStyle'] as Map<String, dynamic>;
      style = TextStyle(
        fontSize: (ts['fontSize'] as num?)?.toDouble(),
        color: ts['color'] != null ? Color(ts['color'] as int) : null,
      );
    }
    return CircleObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      text: json['text'] as String?,
      textStyle: style,
      lineStyle: json['lineStyle'] != null ? LineStyle.values.byName(json['lineStyle']) : LineStyle.solid,
    );
  }

  @override
  DrawingObject copyWith({Rect? rect, bool? isSelected, double? angle, LineStyle? lineStyle, bool? isEditing}) {
    return CircleObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      text: text,
      textStyle: textStyle,
      lineStyle: lineStyle ?? this.lineStyle,
      isEditing: isEditing ?? this.isEditing,
    );
  }
}

class DiamondObject extends DrawingObject {
  Rect _rect;
  String? text;
  TextStyle? textStyle;
  bool isEditing;
  final LineStyle lineStyle;

  DiamondObject({
    required super.id,
    required Rect rect,
    super.isSelected,
    super.angle,
    this.text,
    this.textStyle,
    this.isEditing = false,
    this.lineStyle = LineStyle.solid,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'diamond',
    'rect': _rect.toJson(),
    'isSelected': isSelected,
    'angle': angle,
    if (text != null) 'text': text,
    if (textStyle != null) 'textStyle': {
      'fontSize': textStyle!.fontSize,
      'color': textStyle!.color?.value,
    },
    'lineStyle': lineStyle.name,
  };

  static DiamondObject fromJson(Map<String, dynamic> json) {
    TextStyle? style;
    if (json['textStyle'] != null) {
      final ts = json['textStyle'] as Map<String, dynamic>;
      style = TextStyle(
        fontSize: (ts['fontSize'] as num?)?.toDouble(),
        color: ts['color'] != null ? Color(ts['color'] as int) : null,
      );
    }
    return DiamondObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      text: json['text'] as String?,
      textStyle: style,
      lineStyle: json['lineStyle'] != null
          ? LineStyle.values.byName(json['lineStyle'])
          : LineStyle.solid,
    );
  }

  Path get path {
    final c = _rect.center;
    final hw = _rect.width / 2;
    final hh = _rect.height / 2;
    return Path()
      ..moveTo(c.dx, c.dy - hh) // top
      ..lineTo(c.dx + hw, c.dy) // right
      ..lineTo(c.dx, c.dy + hh) // bottom
      ..lineTo(c.dx - hw, c.dy) // left
      ..close();
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    bool? isSelected,
    double? angle,
    LineStyle? lineStyle,
    bool? isEditing,
  }) {
    return DiamondObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      text: text,
      textStyle: textStyle,
      lineStyle: lineStyle ?? this.lineStyle,
      isEditing: isEditing ?? this.isEditing,
    );
  }
}

class ArrowObject extends DrawingObject {
  Offset start;
  Offset end;
  Offset? midPoint;
  final LinkPathType pathType;
  final ObjectAttachment? startAttachment;
  final ObjectAttachment? endAttachment;
  List<Offset>? waypoints;
  final LineStyle lineStyle;

  ArrowObject({
    required super.id,
    required this.start,
    required this.end,
    super.isSelected,
    super.angle,
    this.midPoint,
    this.pathType = LinkPathType.straight,
    this.startAttachment,
    this.endAttachment,
    this.waypoints,
    this.lineStyle = LineStyle.solid,
  });

  @override
  Rect get rect {
    if (pathType == LinkPathType.orthogonal) {
      if (waypoints != null && waypoints!.isNotEmpty) {
        double minX = start.dx, minY = start.dy;
        double maxX = start.dx, maxY = start.dy;
        for (final wp in waypoints!) {
          minX = min(minX, wp.dx);
          minY = min(minY, wp.dy);
          maxX = max(maxX, wp.dx);
          maxY = max(maxY, wp.dy);
        }
        minX = min(minX, end.dx);
        minY = min(minY, end.dy);
        maxX = max(maxX, end.dx);
        maxY = max(maxY, end.dy);
        return Rect.fromLTRB(minX, minY, maxX, maxY);
      }
      return Rect.fromPoints(start, end).normalize;
    }

    final points = [start, end];
    final p0 = start;
    final p1 = midPoint ?? (start + end) / 2;
    final p2 = end;

    final dX = p0.dx - 2 * p1.dx + p2.dx;
    if (dX.abs() > 1e-12) {
      final t = (p0.dx - p1.dx) / dX;
      if (t > 0 && t < 1) {
        points.add(_getPointOnCurve(t, p0, p1, p2));
      }
    }

    final dY = p0.dy - 2 * p1.dy + p2.dy;
    if (dY.abs() > 1e-12) {
      final t = (p0.dy - p1.dy) / dY;
      if (t > 0 && t < 1) {
        points.add(_getPointOnCurve(t, p0, p1, p2));
      }
    }

    double minX = points.first.dx;
    double minY = points.first.dy;
    double maxX = points.first.dx;
    double maxY = points.first.dy;
    for (var i = 1; i < points.length; i++) {
      minX = min(minX, points[i].dx);
      minY = min(minY, points[i].dy);
      maxX = max(maxX, points[i].dx);
      maxY = max(maxY, points[i].dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _getPointOnCurve(double t, Offset p0, Offset p1, Offset p2) {
    final s = 1 - t;
    final x = s * s * p0.dx + 2 * s * t * p1.dx + t * t * p2.dx;
    final y = s * s * p0.dy + 2 * s * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }


  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'arrow',
    'start': start.toJson(),
    'end': end.toJson(),
    'isSelected': isSelected,
    'pathType': pathType.name,
    'startAttachment': startAttachment?.toJson(),
    'endAttachment': endAttachment?.toJson(),
    'midPoint': midPoint?.toJson(),
    'angle': angle,
    'lineStyle': lineStyle.name,
  };

  factory ArrowObject.fromJson(Map<String, dynamic> json) {
    return ArrowObject(
      id: json['id'],
      start: JSONOffset.fromJson((json['start'] as List).cast<double>()),
      end: JSONOffset.fromJson((json['end'] as List).cast<double>()),
      isSelected: json['isSelected'] ?? false,
      pathType: LinkPathType.values.byName(json['pathType'] ?? 'straight'),
      startAttachment: json['startAttachment'] != null ? ObjectAttachment.fromJson(json['startAttachment']) : null,
      endAttachment: json['endAttachment'] != null ? ObjectAttachment.fromJson(json['endAttachment']) : null,
      angle: json['angle'] ?? 0.0,
      midPoint: json['midPoint'] != null ? JSONOffset.fromJson((json['midPoint'] as List).cast<double>()) : null,
      lineStyle: json['lineStyle'] != null ? LineStyle.values.byName(json['lineStyle']) : LineStyle.solid,
    );
  }

  @override
  DrawingObject copyWith({
    Offset? start,
    Offset? end,
    Offset? midPoint,
    bool? isSelected,
    LinkPathType? pathType,
    ObjectAttachment? startAttachment,
    ObjectAttachment? endAttachment,
    double? angle,
    List<Offset>? waypoints,
    LineStyle? lineStyle,
  }) {
    return ArrowObject(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      isSelected: isSelected ?? this.isSelected,
      midPoint: midPoint ?? this.midPoint,
      pathType: pathType ?? this.pathType,
      startAttachment: startAttachment ?? this.startAttachment,
      endAttachment: endAttachment ?? this.endAttachment,
      angle: angle ?? this.angle,
      waypoints: waypoints ?? this.waypoints,
      lineStyle: lineStyle ?? this.lineStyle,
    );
  }
}

class LineObject extends DrawingObject {
  Offset start;
  Offset end;
  Offset? midPoint;
  final ObjectAttachment? startAttachment;
  final ObjectAttachment? endAttachment;
  final LineStyle lineStyle;

  LineObject({
    required super.id,
    required this.start,
    required this.end,
    this.midPoint,
    super.isSelected,
    this.startAttachment,
    this.endAttachment,
    super.angle,
    this.lineStyle = LineStyle.solid,
  });

  @override
  Rect get rect {
    final points = [start, end];
    final p0 = start;
    final p1 = midPoint ?? (start + end) / 2;
    final p2 = end;

    final dX = p0.dx - 2 * p1.dx + p2.dx;
    if (dX.abs() > 1e-12) {
      final t = (p0.dx - p1.dx) / dX;
      if (t > 0 && t < 1) {
        points.add(_getPointOnCurve(t, p0, p1, p2));
      }
    }

    final dY = p0.dy - 2 * p1.dy + p2.dy;
    if (dY.abs() > 1e-12) {
      final t = (p0.dy - p1.dy) / dY;
      if (t > 0 && t < 1) {
        points.add(_getPointOnCurve(t, p0, p1, p2));
      }
    }

    double minX = points.first.dx;
    double minY = points.first.dy;
    double maxX = points.first.dx;
    double maxY = points.first.dy;
    for (var i = 1; i < points.length; i++) {
      minX = min(minX, points[i].dx);
      minY = min(minY, points[i].dy);
      maxX = max(maxX, points[i].dx);
      maxY = max(maxY, points[i].dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _getPointOnCurve(double t, Offset p0, Offset p1, Offset p2) {
    final s = 1 - t;
    final x = s * s * p0.dx + 2 * s * t * p1.dx + t * t * p2.dx;
    final y = s * s * p0.dy + 2 * s * t * p1.dy + t * t * p2.dy;
    return Offset(x, y);
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'line',
    'start': start.toJson(),
    'end': end.toJson(),
    'isSelected': isSelected,
    'startAttachment': startAttachment?.toJson(),
    'endAttachment': endAttachment?.toJson(),
    'angle': angle,
    'midPoint': midPoint?.toJson(),
    'lineStyle': lineStyle.name,
  };

  factory LineObject.fromJson(Map<String, dynamic> json) {
    return LineObject(
      id: json['id'],
      start: JSONOffset.fromJson((json['start'] as List).cast<double>()),
      end: JSONOffset.fromJson((json['end'] as List).cast<double>()),
      isSelected: json['isSelected'] ?? false,
      startAttachment: json['startAttachment'] != null
          ? ObjectAttachment.fromJson(json['startAttachment'])
          : null,
      endAttachment: json['endAttachment'] != null
          ? ObjectAttachment.fromJson(json['endAttachment'])
          : null,
      angle: json['angle'] ?? 0.0,
      midPoint: json['midPoint'] != null ? JSONOffset.fromJson((json['midPoint'] as List).cast<double>()) : null,
      lineStyle: json['lineStyle'] != null ? LineStyle.values.byName(json['lineStyle']) : LineStyle.solid,
    );
  }

  @override
  DrawingObject copyWith({
    Offset? start,
    Offset? end,
    Offset? midPoint,
    bool? isSelected,
    ObjectAttachment? startAttachment,
    ObjectAttachment? endAttachment,
    double? angle,
    LineStyle? lineStyle,
  }) {
    return LineObject(
      id: id,
      start: start ?? this.start,
      end: end ?? this.end,
      midPoint: midPoint ?? this.midPoint,
      isSelected: isSelected ?? this.isSelected,
      startAttachment: startAttachment ?? this.startAttachment,
      endAttachment: endAttachment ?? this.endAttachment,
      angle: angle ?? this.angle,
      lineStyle: lineStyle ?? this.lineStyle,
    );
  }
}

class PencilStrokeObject extends DrawingObject {
  List<PointVector> points;
  Path? cachedPath;

  PencilStrokeObject({
    required super.id,
    required this.points,
    super.isSelected,
    super.angle,
  });

  @override
  Rect get rect {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;

    for (final point in points) {
      minX = min(minX, point.x);
      maxX = max(maxX, point.x);
      minY = min(minY, point.y);
      maxY = max(maxY, point.y);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  set start(Offset _) {}

  set end(Offset _) {}

  set midPoint(Offset? _) {}

  Offset get start =>
      points.isNotEmpty ? Offset(points.first.x, points.first.y) : Offset.zero;

  Offset get end =>
      points.isNotEmpty ? Offset(points.last.x, points.last.y) : Offset.zero;

  Offset? get midPoint => null;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'pencil_stroke',
    'points': points.map((p) => [p.x, p.y, p.pressure]).toList(),
    'isSelected': isSelected,
    'angle': angle
  };

  factory PencilStrokeObject.fromJson(Map<String, dynamic> json) {
    return PencilStrokeObject(
      id: json['id'],
      points: (json['points'] as List)
          .map(
            (p) => PointVector(p[0], p[1], p.length > 2 ? p[2] : 0.5),
          ) // Default pressure if null
          .toList(),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
    );
  }

  @override
  DrawingObject copyWith({List<PointVector>? points, bool? isSelected, double? angle}) {
    return PencilStrokeObject(
      id: id,
      points: points ?? this.points,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
    );
  }
}

class FigureObject extends DrawingObject {
  Rect _rect;
  String label;
  Set<String> childrenIds;

  FigureObject({
    required super.id,
    required Rect rect,
    this.label = "Figure",
    this.childrenIds = const {},
    super.isSelected,
    super.angle,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'figure',
    'rect': _rect.toJson(),
    'label': label,
    'childrenIds': childrenIds.toList(),
    'isSelected': isSelected,
    'angle': angle
  };

  factory FigureObject.fromJson(Map<String, dynamic> json) {
    return FigureObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      label: json['label'] ?? "Figure",
      childrenIds: (json['childrenIds'] as List<dynamic>)
          .cast<String>()
          .toSet(),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
    );
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    String? label,
    Set<String>? childrenIds,
    bool? isSelected,
    double? angle,
  }) {
    return FigureObject(
      id: id,
      rect: rect ?? _rect,
      label: label ?? this.label,
      childrenIds: childrenIds ?? this.childrenIds,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FigureObject &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          _rect == other._rect &&
          label == other.label &&
          setEquals(childrenIds, other.childrenIds) &&
          isSelected == other.isSelected;

  @override
  int get hashCode =>
      id.hashCode ^
      _rect.hashCode ^
      label.hashCode ^
      childrenIds.hashCode ^
      isSelected.hashCode;
}

class TextObject extends DrawingObject {
  Rect _rect;
  String text;
  TextStyle style;
  bool isEditing;

  TextObject({
    required super.id,
    required Rect rect,
    this.text = 'Text',
    this.style = const TextStyle(fontSize: 16, color: Colors.white),
    this.isEditing = false,
    super.isSelected,
    super.angle,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'text',
    'rect': _rect.toJson(),
    'text': text,
    'style': {'fontSize': style.fontSize, 'color': style.color?.value},
    'isSelected': isSelected,
    'angle': angle
  };

  factory TextObject.fromJson(Map<String, dynamic> json) {
    final styleJson = json['style'] as Map<String, dynamic>?;
    return TextObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      text: json['text'] ?? 'Text',
      style: TextStyle(
        fontSize: styleJson?['fontSize'] as double? ?? 16,
        color: styleJson?['color'] != null
            ? Color(styleJson!['color'] as int)
            : Colors.white,
      ),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
    );
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    String? text,
    TextStyle? style,
    bool? isSelected,
    bool? isEditing,
    double? angle,
  }) {
    return TextObject(
      id: id,
      rect: rect ?? _rect,
      text: text ?? this.text,
      style: style ?? this.style,
      isSelected: isSelected ?? this.isSelected,
      isEditing: isEditing ?? this.isEditing,
      angle: angle ?? this.angle,
    );
  }
}

class SvgObject extends DrawingObject {
  Rect _rect;
  final String assetPath;
  final PictureInfo pictureInfo;

  SvgObject({
    required super.id,
    required Rect rect,
    required this.assetPath,
    required this.pictureInfo,
    super.isSelected,
    super.angle,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  @override
  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'svg',
    'rect': _rect.toJson(),
    'assetPath': assetPath,
    'isSelected': isSelected,
    'angle': angle
  };

  @override
  DrawingObject copyWith({Rect? rect, bool? isSelected, double? angle}) {
    return SvgObject(
      id: id,
      rect: rect ?? _rect,
      assetPath: assetPath,
      pictureInfo: pictureInfo,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
    );
  }
}

class TempDrawingObject {
  final EditorTool tool;
  final Offset start;
  final Offset end;
  final LinkPathType pathType;
  final List<PointVector> points;
  final List<Offset>? waypoints;

  TempDrawingObject({
    required this.tool,
    required this.start,
    required this.end,
    this.points = const [],
    this.pathType = LinkPathType.straight,
    this.waypoints,
  });

  TempDrawingObject copyWith({
    Offset? end,
    List<PointVector>? points,
    LinkPathType? pathType,
    List<Offset>? waypoints,
  }) {
    return TempDrawingObject(
      tool: tool,
      start: start,
      end: end ?? this.end,
      points: points ?? this.points,
      pathType: pathType ?? this.pathType,
      waypoints: waypoints ?? this.waypoints,
    );
  }
}

class ObjectAttachment extends Equatable {
  final String objectId;
  // An offset where (0,0) is topLeft and (1,1) is bottomRight of the target object's rect.
  final Offset relativePosition;

  const ObjectAttachment({required this.objectId, required this.relativePosition});

  @override
  List<Object> get props => [objectId, relativePosition];

  Map<String, dynamic> toJson() => {
    'objectId': objectId,
    'relativePosition': [relativePosition.dx, relativePosition.dy],
  };

  factory ObjectAttachment.fromJson(Map<String, dynamic> json) {
    return ObjectAttachment(
      objectId: json['objectId'],
      relativePosition: Offset(json['relativePosition'][0], json['relativePosition'][1]),
    );
  }

  ObjectAttachment copyWith({String? objectId, Offset? relativePosition}) {
    return ObjectAttachment(
      objectId: objectId ?? this.objectId,
      relativePosition: relativePosition ?? this.relativePosition,
    );
  }
}
