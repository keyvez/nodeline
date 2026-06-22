import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flow_draw/src/core/utils/json_extensions.dart';
import 'package:flow_draw/src/models/styles.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Font families offered by the editor. Limited to families that are
/// guaranteed to render (the platform's built-in generic families plus the
/// historical default), so a picked font never silently falls back.
const List<String> kEditorFontFamilies = <String>[
  'Courier',
  'sans-serif',
  'serif',
  'monospace',
];

/// The font family applied to shape text when nothing else has been chosen.
const String kEditorDefaultFontFamily = 'Courier';

/// The font size applied to shape text when nothing else has been chosen.
const double kEditorDefaultFontSize = 16.0;

/// A named text-style preset (à la Google Docs' Title / Heading 1 / …).
///
/// Presets are defined relative to the *global* font so they all share the
/// current global family and scale off the global size: a "Body" preset is the
/// global size (scale 1.0), a "Title" is larger, a "Leaf node" smaller. This
/// keeps the whole type hierarchy tied to the global style — change the global
/// font to Courier 36 and Title/Heading/etc. all become Courier, scaled from 36.
class TextStylePreset {
  final String label;

  /// Multiplier applied to the global default font size. Body == 1.0.
  final double scale;

  const TextStylePreset(this.label, this.scale);

  /// The concrete font size for this preset given the [globalSize].
  double sizeFor(double globalSize) => globalSize * scale;
}

/// Built-in text-style presets, ordered largest → smallest. Scales are relative
/// to the global font size (Body == global size), so the hierarchy descends as
/// tree depth increases (root = Title, then Heading 1/2, … leaf = Leaf node).
const List<TextStylePreset> kTextStylePresets = <TextStylePreset>[
  TextStylePreset('Title', 2.0),
  TextStylePreset('Heading 1', 1.5),
  TextStylePreset('Heading 2', 1.25),
  TextStylePreset('Subtitle', 1.125),
  TextStylePreset('Body', 1.0),
  TextStylePreset('Leaf node', 0.85),
  TextStylePreset('Caption', 0.7),
];

/// Sane bounds for a font size. Guards against corrupt persisted values — an
/// earlier resize bug could blow a font size up to ~1e31, which poisons text
/// layout. Out-of-range or non-finite sizes are clamped on deserialization.
const double kMinFontSize = 1.0;
const double kMaxFontSize = 2000.0;

/// Clamps a deserialized font size into [kMinFontSize, kMaxFontSize], returning
/// null when no usable value was stored (so callers can fall back to a default).
double? _sanitizeFontSize(num? raw) {
  if (raw == null) return null;
  final v = raw.toDouble();
  if (!v.isFinite) return null;
  return v.clamp(kMinFontSize, kMaxFontSize);
}

/// The color used for shape text. Font customization controls family/size only;
/// color continues to come from the existing color pickers.
const Color kDefaultTextColor = Colors.white;

/// Default extra breathing room (world px, per side) the "Fit to content"
/// action leaves around a shape's text, on top of the per-shape base padding.
const double kDefaultFitMargin = 20.0;

/// Resolves the [TextStyle] a shape should paint with.
///
/// When the shape has been individually customized ([customized] true and a
/// [style] present), that style wins. Otherwise the global default
/// ([defaultFamily]/[defaultSize]) is used, so changing the global font
/// updates every shape that has not been touched.
TextStyle effectiveShapeTextStyle({
  required TextStyle? style,
  required bool customized,
  required String defaultFamily,
  required double defaultSize,
}) {
  if (customized && style != null) {
    return TextStyle(
      fontFamily: style.fontFamily ?? defaultFamily,
      fontSize: style.fontSize ?? defaultSize,
      color: style.color ?? kDefaultTextColor,
    );
  }
  return TextStyle(
    fontFamily: defaultFamily,
    fontSize: defaultSize,
    // Preserve any explicitly-set text color even on non-customized shapes.
    color: style?.color ?? kDefaultTextColor,
  );
}

/// Rebuilds a shape's [TextStyle] from its serialized `textStyle` map.
/// Returns null when no style was stored. Tolerates older payloads that omit
/// `fontFamily`.
TextStyle? _textStyleFromJson(Object? raw) {
  if (raw == null) return null;
  final ts = raw as Map<String, dynamic>;
  return TextStyle(
    fontFamily: ts['fontFamily'] as String?,
    fontSize: _sanitizeFontSize(ts['fontSize'] as num?),
    color: ts['color'] != null ? Color(ts['color'] as int) : null,
  );
}

/// A contiguous span of a shape's text that shares one set of style overrides.
///
/// Rich text inside a node is modeled as an ordered list of [TextRun]s whose
/// [text] concatenated yields the node's plain text. Each style attribute is
/// nullable: null means "inherit from the shape's base style" (which itself
/// resolves against the global default via [effectiveShapeTextStyle]). This
/// keeps a single-run node behaving exactly like the legacy single-`TextStyle`
/// node while allowing per-character family/size/bold/italic/color.
@immutable
class TextRun extends Equatable {
  final String text;
  final String? fontFamily;
  final double? fontSize;
  final bool? bold;
  final bool? italic;

  /// ARGB color value (as from [Color.value]); null inherits the base color.
  final int? color;

  const TextRun(
    this.text, {
    this.fontFamily,
    this.fontSize,
    this.bold,
    this.italic,
    this.color,
  });

  /// Whether this run carries any style override at all. A run with no
  /// overrides is purely inherited and can be merged with neighbours.
  bool get hasOverrides =>
      fontFamily != null ||
      fontSize != null ||
      bold != null ||
      italic != null ||
      color != null;

  /// Whether [other] would render identically (ignoring [text]), so adjacent
  /// runs can be coalesced.
  bool sameStyle(TextRun other) =>
      fontFamily == other.fontFamily &&
      fontSize == other.fontSize &&
      bold == other.bold &&
      italic == other.italic &&
      color == other.color;

  /// Resolves this run against [base] (the shape's effective base style) into a
  /// concrete [TextStyle] for painting/editing.
  TextStyle resolve(TextStyle base) {
    return base.copyWith(
      fontFamily: fontFamily ?? base.fontFamily,
      fontSize: fontSize ?? base.fontSize,
      fontWeight: bold == null
          ? base.fontWeight
          : (bold! ? FontWeight.bold : FontWeight.normal),
      fontStyle: italic == null
          ? base.fontStyle
          : (italic! ? FontStyle.italic : FontStyle.normal),
      color: color != null ? Color(color!) : base.color,
    );
  }

  TextRun copyWith({
    String? text,
    Object? fontFamily = _sentinel,
    Object? fontSize = _sentinel,
    Object? bold = _sentinel,
    Object? italic = _sentinel,
    Object? color = _sentinel,
  }) {
    return TextRun(
      text ?? this.text,
      fontFamily: fontFamily == _sentinel ? this.fontFamily : fontFamily as String?,
      fontSize: fontSize == _sentinel ? this.fontSize : fontSize as double?,
      bold: bold == _sentinel ? this.bold : bold as bool?,
      italic: italic == _sentinel ? this.italic : italic as bool?,
      color: color == _sentinel ? this.color : color as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        if (fontFamily != null) 'fontFamily': fontFamily,
        if (fontSize != null) 'fontSize': fontSize,
        if (bold != null) 'bold': bold,
        if (italic != null) 'italic': italic,
        if (color != null) 'color': color,
      };

  factory TextRun.fromJson(Map<String, dynamic> json) => TextRun(
        json['text'] as String? ?? '',
        fontFamily: json['fontFamily'] as String?,
        fontSize: _sanitizeFontSize(json['fontSize'] as num?),
        bold: json['bold'] as bool?,
        italic: json['italic'] as bool?,
        color: json['color'] as int?,
      );

  @override
  List<Object?> get props => [text, fontFamily, fontSize, bold, italic, color];
}

/// Sentinel for [TextRun.copyWith] so callers can explicitly clear a style
/// override (pass null) versus leave it unchanged (omit the argument).
const Object _sentinel = Object();

/// Serializes a list of runs (or null) to JSON.
List<Map<String, dynamic>>? richTextToJson(List<TextRun>? runs) =>
    runs == null ? null : runs.map((r) => r.toJson()).toList();

/// Rebuilds a run list from JSON, returning null when absent.
List<TextRun>? richTextFromJson(Object? raw) {
  if (raw == null) return null;
  final list = (raw as List)
      .map((e) => TextRun.fromJson(e as Map<String, dynamic>))
      .where((r) => r.text.isNotEmpty)
      .toList();
  return list.isEmpty ? null : list;
}

/// Coalesces adjacent runs with identical styling and drops empties, so the
/// stored representation stays minimal.
List<TextRun> normalizeRuns(List<TextRun> runs) {
  final out = <TextRun>[];
  for (final r in runs) {
    if (r.text.isEmpty) continue;
    if (out.isNotEmpty && out.last.sameStyle(r)) {
      out[out.length - 1] = out.last.copyWith(text: out.last.text + r.text);
    } else {
      out.add(r);
    }
  }
  return out;
}

/// Builds the [InlineSpan] for a shape's text. When [runs] holds more than one
/// run (or a single run with overrides) a multi-child span is produced;
/// otherwise a plain single span identical to the legacy path is returned.
/// [base] must be the already-resolved effective style for the shape.
TextSpan buildShapeTextSpan({
  required String? text,
  required List<TextRun>? runs,
  required TextStyle base,
}) {
  if (runs == null || runs.isEmpty) {
    return TextSpan(text: text ?? '', style: base);
  }
  if (runs.length == 1 && !runs.first.hasOverrides) {
    return TextSpan(text: runs.first.text, style: base);
  }
  return TextSpan(
    style: base,
    children: [
      for (final r in runs) TextSpan(text: r.text, style: r.resolve(base)),
    ],
  );
}

/// Direction of a connection port on a shape's boundary.
enum PortDirection { top, right, bottom, left }

/// A connection port (anchor point) on a shape where arrows can attach.
///
/// Each shape exposes four cardinal ports. Ports are shown as small visual
/// indicators when a shape is hovered or selected.
class ConnectionPort {
  /// The absolute position of this port in world coordinates.
  final Offset portPosition;

  /// Which side of the shape this port sits on.
  final PortDirection direction;

  /// The id of the [DrawingObject] that owns this port.
  final String objectId;

  const ConnectionPort({
    required this.portPosition,
    required this.direction,
    required this.objectId,
  });

  /// Computes the four cardinal [ConnectionPort]s for any shape based on its
  /// bounding [rect] and [objectId].
  static List<ConnectionPort> portsForRect(Rect rect, String objectId) {
    return [
      ConnectionPort(
        portPosition: Offset(rect.center.dx, rect.top),
        direction: PortDirection.top,
        objectId: objectId,
      ),
      ConnectionPort(
        portPosition: Offset(rect.right, rect.center.dy),
        direction: PortDirection.right,
        objectId: objectId,
      ),
      ConnectionPort(
        portPosition: Offset(rect.center.dx, rect.bottom),
        direction: PortDirection.bottom,
        objectId: objectId,
      ),
      ConnectionPort(
        portPosition: Offset(rect.left, rect.center.dy),
        direction: PortDirection.left,
        objectId: objectId,
      ),
    ];
  }
}

enum EditorTool {
  arrow,
  square,
  circle,
  diamond,
  parallelogram,
  forkJoin,
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

/// Arrowhead style for arrow objects.
enum ArrowHeadType { none, triangle, diamond, dot, bar }

/// Predefined tool sets for restricted modes.
///
/// Workflow mode limits the palette to boxes, connections, forks, and
/// decision diamonds — perfect for building flowcharts and workflows.
const Set<EditorTool> workflowTools = {
  EditorTool.arrow,
  EditorTool.square,
  EditorTool.diamond,
  EditorTool.parallelogram,
  EditorTool.forkJoin,
  EditorTool.arrowTopRight,
  EditorTool.text,
};

abstract class DrawingObject {
  final String id;
  bool isSelected;
  final double angle;
  final double creationZoom;

  DrawingObject({required this.id, this.isSelected = false, this.angle = 0.0, this.creationZoom = 1.0});

  Rect get rect;

  Map<String, dynamic> toJson();

  /// Returns the four cardinal connection ports for this shape.
  /// Only meaningful for shape objects (Rectangle, Circle, Diamond).
  List<ConnectionPort> getConnectionPorts() {
    return ConnectionPort.portsForRect(rect, id);
  }

  DrawingObject copyWith({bool? isSelected, double? angle});
}

class RectangleObject extends DrawingObject {
  Rect _rect;
  String? text;
  TextStyle? textStyle;

  /// Per-run rich text. When non-null, [text] is the plain-text mirror of these
  /// runs (kept in sync for search/export); rendering uses the runs so a node
  /// can mix font families, sizes, weights, slants, and colors.
  List<TextRun>? richText;

  /// Whether this shape's font (family/size) has been individually customized.
  /// When false, the shape follows the global default font and is updated by
  /// global font changes; when true, it keeps its own [textStyle].
  bool fontCustomized;
  bool isEditing;
  final LineStyle lineStyle;

  /// Corner radius for rounded rectangle variant.
  /// When > 0, the rectangle renders with rounded corners.
  final double borderRadius;

  /// Custom fill color. When null, the default canvas fill is used.
  final Color? fillColor;

  /// Custom stroke/border color. When null, the default stroke is used.
  final Color? strokeColor;

  RectangleObject({required super.id, required Rect rect, super.isSelected, super.angle, super.creationZoom, this.text, this.textStyle, this.richText, this.fontCustomized = false, this.isEditing = false, this.lineStyle = LineStyle.solid, this.borderRadius = 0.0, this.fillColor, this.strokeColor})
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
    'creationZoom': creationZoom,
    if (text != null) 'text': text,
    if (textStyle != null) 'textStyle': {
      'fontFamily': textStyle!.fontFamily,
      'fontSize': textStyle!.fontSize,
      'color': textStyle!.color?.value,
    },
    if (richText != null) 'richText': richTextToJson(richText),
    if (fontCustomized) 'fontCustomized': true,
    'lineStyle': lineStyle.name,
    if (borderRadius > 0) 'borderRadius': borderRadius,
    if (fillColor != null) 'fillColor': fillColor!.toARGB32(),
    if (strokeColor != null) 'strokeColor': strokeColor!.toARGB32(),
  };

  factory RectangleObject.fromJson(Map<String, dynamic> json) {
    final style = _textStyleFromJson(json['textStyle']);
    return RectangleObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String?,
      textStyle: style,
      richText: richTextFromJson(json['richText']),
      fontCustomized: json['fontCustomized'] as bool? ?? false,
      lineStyle: json['lineStyle'] != null ? LineStyle.values.byName(json['lineStyle']) : LineStyle.solid,
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 0.0,
      fillColor: json['fillColor'] != null ? Color(json['fillColor'] as int) : null,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
    );
  }

  @override
  DrawingObject copyWith({Rect? rect, bool? isSelected, double? angle, double? creationZoom, LineStyle? lineStyle, bool? isEditing, double? borderRadius, Color? fillColor, Color? strokeColor, TextStyle? textStyle, List<TextRun>? richText, bool? fontCustomized, bool clearFill = false, bool clearStroke = false}) {
    return RectangleObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
      text: text,
      textStyle: textStyle ?? this.textStyle,
      richText: richText ?? this.richText,
      fontCustomized: fontCustomized ?? this.fontCustomized,
      lineStyle: lineStyle ?? this.lineStyle,
      borderRadius: borderRadius ?? this.borderRadius,
      isEditing: isEditing ?? this.isEditing,
      fillColor: clearFill ? null : (fillColor ?? this.fillColor),
      strokeColor: clearStroke ? null : (strokeColor ?? this.strokeColor),
    );
  }
}

class CircleObject extends DrawingObject {
  Rect _rect;
  String? text;
  TextStyle? textStyle;
  List<TextRun>? richText;
  bool fontCustomized;
  bool isEditing;
  final LineStyle lineStyle;
  final Color? fillColor;
  final Color? strokeColor;

  CircleObject({required super.id, required Rect rect, super.isSelected, super.angle, super.creationZoom, this.text, this.textStyle, this.richText, this.fontCustomized = false, this.isEditing = false, this.lineStyle = LineStyle.solid, this.fillColor, this.strokeColor})
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
    'creationZoom': creationZoom,
    if (text != null) 'text': text,
    if (textStyle != null) 'textStyle': {
      'fontFamily': textStyle!.fontFamily,
      'fontSize': textStyle!.fontSize,
      'color': textStyle!.color?.value,
    },
    if (richText != null) 'richText': richTextToJson(richText),
    if (fontCustomized) 'fontCustomized': true,
    'lineStyle': lineStyle.name,
    if (fillColor != null) 'fillColor': fillColor!.toARGB32(),
    if (strokeColor != null) 'strokeColor': strokeColor!.toARGB32(),
  };

  factory CircleObject.fromJson(Map<String, dynamic> json) {
    final style = _textStyleFromJson(json['textStyle']);
    return CircleObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String?,
      textStyle: style,
      richText: richTextFromJson(json['richText']),
      fontCustomized: json['fontCustomized'] as bool? ?? false,
      lineStyle: json['lineStyle'] != null ? LineStyle.values.byName(json['lineStyle']) : LineStyle.solid,
      fillColor: json['fillColor'] != null ? Color(json['fillColor'] as int) : null,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
    );
  }

  @override
  DrawingObject copyWith({Rect? rect, bool? isSelected, double? angle, double? creationZoom, LineStyle? lineStyle, bool? isEditing, Color? fillColor, Color? strokeColor, TextStyle? textStyle, List<TextRun>? richText, bool? fontCustomized, bool clearFill = false, bool clearStroke = false}) {
    return CircleObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
      text: text,
      textStyle: textStyle ?? this.textStyle,
      richText: richText ?? this.richText,
      fontCustomized: fontCustomized ?? this.fontCustomized,
      lineStyle: lineStyle ?? this.lineStyle,
      isEditing: isEditing ?? this.isEditing,
      fillColor: clearFill ? null : (fillColor ?? this.fillColor),
      strokeColor: clearStroke ? null : (strokeColor ?? this.strokeColor),
    );
  }
}

class DiamondObject extends DrawingObject {
  Rect _rect;
  String? text;
  TextStyle? textStyle;
  List<TextRun>? richText;
  bool fontCustomized;
  bool isEditing;
  final LineStyle lineStyle;
  final Color? fillColor;
  final Color? strokeColor;

  DiamondObject({
    required super.id,
    required Rect rect,
    super.isSelected,
    super.angle,
    super.creationZoom,
    this.text,
    this.textStyle,
    this.richText,
    this.fontCustomized = false,
    this.isEditing = false,
    this.lineStyle = LineStyle.solid,
    this.fillColor,
    this.strokeColor,
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
    'creationZoom': creationZoom,
    if (text != null) 'text': text,
    if (textStyle != null) 'textStyle': {
      'fontFamily': textStyle!.fontFamily,
      'fontSize': textStyle!.fontSize,
      'color': textStyle!.color?.value,
    },
    if (richText != null) 'richText': richTextToJson(richText),
    if (fontCustomized) 'fontCustomized': true,
    'lineStyle': lineStyle.name,
    if (fillColor != null) 'fillColor': fillColor!.toARGB32(),
    if (strokeColor != null) 'strokeColor': strokeColor!.toARGB32(),
  };

  static DiamondObject fromJson(Map<String, dynamic> json) {
    final style = _textStyleFromJson(json['textStyle']);
    return DiamondObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String?,
      textStyle: style,
      richText: richTextFromJson(json['richText']),
      fontCustomized: json['fontCustomized'] as bool? ?? false,
      lineStyle: json['lineStyle'] != null
          ? LineStyle.values.byName(json['lineStyle'])
          : LineStyle.solid,
      fillColor: json['fillColor'] != null ? Color(json['fillColor'] as int) : null,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
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
    double? creationZoom,
    LineStyle? lineStyle,
    bool? isEditing,
    Color? fillColor,
    Color? strokeColor,
    TextStyle? textStyle,
    List<TextRun>? richText,
    bool? fontCustomized,
    bool clearFill = false,
    bool clearStroke = false,
  }) {
    return DiamondObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
      text: text,
      textStyle: textStyle ?? this.textStyle,
      richText: richText ?? this.richText,
      fontCustomized: fontCustomized ?? this.fontCustomized,
      lineStyle: lineStyle ?? this.lineStyle,
      isEditing: isEditing ?? this.isEditing,
      fillColor: clearFill ? null : (fillColor ?? this.fillColor),
      strokeColor: clearStroke ? null : (strokeColor ?? this.strokeColor),
    );
  }
}

/// A parallelogram shape for process/data flow diagrams.
class ParallelogramObject extends DrawingObject {
  Rect _rect;
  String? text;
  TextStyle? textStyle;
  List<TextRun>? richText;
  bool fontCustomized;
  bool isEditing;
  final LineStyle lineStyle;
  final double skewOffset;
  final Color? fillColor;
  final Color? strokeColor;

  ParallelogramObject({
    required super.id,
    required Rect rect,
    super.isSelected,
    super.angle,
    super.creationZoom,
    this.text,
    this.textStyle,
    this.richText,
    this.fontCustomized = false,
    this.isEditing = false,
    this.lineStyle = LineStyle.solid,
    this.skewOffset = 20.0,
    this.fillColor,
    this.strokeColor,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'parallelogram',
    'rect': _rect.toJson(),
    'isSelected': isSelected,
    'angle': angle,
    'creationZoom': creationZoom,
    if (text != null) 'text': text,
    if (textStyle != null) 'textStyle': {
      'fontFamily': textStyle!.fontFamily,
      'fontSize': textStyle!.fontSize,
      'color': textStyle!.color?.value,
    },
    if (richText != null) 'richText': richTextToJson(richText),
    if (fontCustomized) 'fontCustomized': true,
    'lineStyle': lineStyle.name,
    'skewOffset': skewOffset,
    if (fillColor != null) 'fillColor': fillColor!.toARGB32(),
    if (strokeColor != null) 'strokeColor': strokeColor!.toARGB32(),
  };

  static ParallelogramObject fromJson(Map<String, dynamic> json) {
    final style = _textStyleFromJson(json['textStyle']);
    return ParallelogramObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String?,
      textStyle: style,
      richText: richTextFromJson(json['richText']),
      fontCustomized: json['fontCustomized'] as bool? ?? false,
      lineStyle: json['lineStyle'] != null
          ? LineStyle.values.byName(json['lineStyle'])
          : LineStyle.solid,
      skewOffset: (json['skewOffset'] as num?)?.toDouble() ?? 20.0,
      fillColor: json['fillColor'] != null ? Color(json['fillColor'] as int) : null,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
    );
  }

  Path get path {
    final r = _rect;
    return Path()
      ..moveTo(r.left + skewOffset, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right - skewOffset, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..close();
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    bool? isSelected,
    double? angle,
    double? creationZoom,
    LineStyle? lineStyle,
    bool? isEditing,
    Color? fillColor,
    Color? strokeColor,
    TextStyle? textStyle,
    List<TextRun>? richText,
    bool? fontCustomized,
    bool clearFill = false,
    bool clearStroke = false,
  }) {
    return ParallelogramObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
      text: text,
      textStyle: textStyle ?? this.textStyle,
      richText: richText ?? this.richText,
      fontCustomized: fontCustomized ?? this.fontCustomized,
      lineStyle: lineStyle ?? this.lineStyle,
      isEditing: isEditing ?? this.isEditing,
      skewOffset: skewOffset,
      fillColor: clearFill ? null : (fillColor ?? this.fillColor),
      strokeColor: clearStroke ? null : (strokeColor ?? this.strokeColor),
    );
  }
}

/// A fork/join horizontal bar for activity/UML diagrams.
class ForkJoinObject extends DrawingObject {
  Rect _rect;
  final LineStyle lineStyle;
  final Color? fillColor;
  final Color? strokeColor;

  ForkJoinObject({
    required super.id,
    required Rect rect,
    super.isSelected,
    super.angle,
    super.creationZoom,
    this.lineStyle = LineStyle.solid,
    this.fillColor,
    this.strokeColor,
  }) : _rect = rect;

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) => _rect = newRect;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'fork_join',
    'rect': _rect.toJson(),
    'isSelected': isSelected,
    'angle': angle,
    'creationZoom': creationZoom,
    'lineStyle': lineStyle.name,
    if (fillColor != null) 'fillColor': fillColor!.toARGB32(),
    if (strokeColor != null) 'strokeColor': strokeColor!.toARGB32(),
  };

  static ForkJoinObject fromJson(Map<String, dynamic> json) {
    return ForkJoinObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
      lineStyle: json['lineStyle'] != null
          ? LineStyle.values.byName(json['lineStyle'])
          : LineStyle.solid,
      fillColor: json['fillColor'] != null ? Color(json['fillColor'] as int) : null,
      strokeColor: json['strokeColor'] != null ? Color(json['strokeColor'] as int) : null,
    );
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    bool? isSelected,
    double? angle,
    double? creationZoom,
    LineStyle? lineStyle,
    Color? fillColor,
    Color? strokeColor,
    bool clearFill = false,
    bool clearStroke = false,
  }) {
    return ForkJoinObject(
      id: id,
      rect: rect ?? _rect,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
      lineStyle: lineStyle ?? this.lineStyle,
      fillColor: clearFill ? null : (fillColor ?? this.fillColor),
      strokeColor: clearStroke ? null : (strokeColor ?? this.strokeColor),
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
  /// Optional text label displayed at the midpoint of this arrow.
  final String? arrowLabel;
  /// Optional simplified freehand stroke (world coords) that softly biases the
  /// orthogonal router toward this shape. Null = route freely. Only consulted
  /// for [LinkPathType.orthogonal].
  final List<Offset>? routeGuide;

  /// Transient cache of the polyline actually drawn on screen (edge-snapped
  /// start/end plus routed waypoints), written by the render object each paint.
  /// Hit-testing measures against this so taps match the visible line exactly.
  /// Not serialized and not part of copyWith — it is recomputed every frame.
  List<Offset>? renderedPath;

  ArrowObject({
    required super.id,
    required this.start,
    required this.end,
    super.isSelected,
    super.angle,
    super.creationZoom,
    this.midPoint,
    this.pathType = LinkPathType.straight,
    this.startAttachment,
    this.endAttachment,
    this.waypoints,
    this.lineStyle = LineStyle.solid,
    this.arrowLabel,
    this.routeGuide,
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
    'creationZoom': creationZoom,
    'lineStyle': lineStyle.name,
    if (arrowLabel != null) 'arrowLabel': arrowLabel,
    if (routeGuide != null)
      'routeGuide': routeGuide!.map((o) => o.toJson()).toList(),
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
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
      midPoint: json['midPoint'] != null ? JSONOffset.fromJson((json['midPoint'] as List).cast<double>()) : null,
      lineStyle: json['lineStyle'] != null ? LineStyle.values.byName(json['lineStyle']) : LineStyle.solid,
      arrowLabel: json['arrowLabel'] as String?,
      routeGuide: json['routeGuide'] != null
          ? (json['routeGuide'] as List)
              .map((o) => JSONOffset.fromJson((o as List).cast<double>()))
              .toList()
          : null,
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
    double? creationZoom,
    List<Offset>? waypoints,
    LineStyle? lineStyle,
    String? arrowLabel,
    bool clearArrowLabel = false,
    List<Offset>? routeGuide,
    bool clearRouteGuide = false,
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
      creationZoom: creationZoom ?? this.creationZoom,
      waypoints: waypoints ?? this.waypoints,
      lineStyle: lineStyle ?? this.lineStyle,
      arrowLabel: clearArrowLabel ? null : (arrowLabel ?? this.arrowLabel),
      routeGuide: clearRouteGuide ? null : (routeGuide ?? this.routeGuide),
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
    super.creationZoom,
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
    'creationZoom': creationZoom,
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
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
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
    double? creationZoom,
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
      creationZoom: creationZoom ?? this.creationZoom,
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
    super.creationZoom,
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
    'angle': angle,
    'creationZoom': creationZoom,
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
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  DrawingObject copyWith({List<PointVector>? points, bool? isSelected, double? angle, double? creationZoom}) {
    return PencilStrokeObject(
      id: id,
      points: points ?? this.points,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
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
    super.creationZoom,
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
    'angle': angle,
    'creationZoom': creationZoom,
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
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  DrawingObject copyWith({
    Rect? rect,
    String? label,
    Set<String>? childrenIds,
    bool? isSelected,
    double? angle,
    double? creationZoom,
  }) {
    return FigureObject(
      id: id,
      rect: rect ?? _rect,
      label: label ?? this.label,
      childrenIds: childrenIds ?? this.childrenIds,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
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
  String _text;
  TextStyle _style;
  bool isEditing;

  // Cached painter — rebuilt only when text, style, or width changes.
  TextPainter? _cachedPainter;
  String? _cachedText;
  TextStyle? _cachedStyle;
  double? _cachedWidth;

  TextObject({
    required super.id,
    required Rect rect,
    String text = 'Text',
    TextStyle style = const TextStyle(fontSize: 16, color: Colors.white),
    this.isEditing = false,
    super.isSelected,
    super.angle,
    super.creationZoom,
  })  : _rect = rect,
        _text = text,
        _style = style;

  String get text => _text;
  set text(String value) {
    if (_text != value) {
      _text = value;
      _cachedPainter = null;
    }
  }

  TextStyle get style => _style;
  set style(TextStyle value) {
    if (_style != value) {
      _style = value;
      _cachedPainter = null;
    }
  }

  @override
  Rect get rect => _rect;

  set rect(Rect newRect) {
    if (newRect.width != _rect.width) _cachedPainter = null;
    _rect = newRect;
  }

  /// Returns a laid-out TextPainter, re-layouting only when inputs changed.
  TextPainter layoutPainter() {
    final maxW = _rect.width.isFinite ? _rect.width : double.infinity;
    if (_cachedPainter != null &&
        _cachedText == _text &&
        _cachedStyle == _style &&
        _cachedWidth == maxW) {
      return _cachedPainter!;
    }
    _cachedPainter = TextPainter(
      text: TextSpan(text: _text, style: _style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);
    _cachedText = _text;
    _cachedStyle = _style;
    _cachedWidth = maxW;
    return _cachedPainter!;
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'text',
    'rect': _rect.toJson(),
    'text': text,
    'style': {
      'fontFamily': style.fontFamily,
      'fontSize': style.fontSize,
      'color': style.color?.value,
    },
    'isSelected': isSelected,
    'angle': angle,
    'creationZoom': creationZoom,
  };

  factory TextObject.fromJson(Map<String, dynamic> json) {
    final styleJson = json['style'] as Map<String, dynamic>?;
    return TextObject(
      id: json['id'],
      rect: JSONRect.fromJson(json['rect']),
      text: json['text'] ?? 'Text',
      style: TextStyle(
        fontFamily: styleJson?['fontFamily'] as String?,
        fontSize: _sanitizeFontSize(styleJson?['fontSize'] as num?) ??
            kEditorDefaultFontSize,
        color: styleJson?['color'] != null
            ? Color(styleJson!['color'] as int)
            : Colors.white,
      ),
      isSelected: json['isSelected'] ?? false,
      angle: json['angle'] ?? 0.0,
      creationZoom: (json['creationZoom'] as num?)?.toDouble() ?? 1.0,
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
    double? creationZoom,
  }) {
    return TextObject(
      id: id,
      rect: rect ?? _rect,
      text: text ?? this.text,
      style: style ?? this.style,
      isSelected: isSelected ?? this.isSelected,
      isEditing: isEditing ?? this.isEditing,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
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
    super.creationZoom,
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
    'angle': angle,
    'creationZoom': creationZoom,
  };

  @override
  DrawingObject copyWith({Rect? rect, bool? isSelected, double? angle, double? creationZoom}) {
    return SvgObject(
      id: id,
      rect: rect ?? _rect,
      assetPath: assetPath,
      pictureInfo: pictureInfo,
      isSelected: isSelected ?? this.isSelected,
      angle: angle ?? this.angle,
      creationZoom: creationZoom ?? this.creationZoom,
    );
  }
}

/// Reconstructs a [DrawingObject] from its serialized [json] using the `type`
/// discriminator written by each subclass's `toJson`. Returns null for unknown
/// or non-round-trippable types (e.g. `svg`, whose runtime PictureInfo isn't
/// serialized). Mirrors the type switch used when loading a project so copy/
/// paste and load stay in sync.
DrawingObject? drawingObjectFromJson(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'rectangle':
      return RectangleObject.fromJson(json);
    case 'circle':
      return CircleObject.fromJson(json);
    case 'diamond':
      return DiamondObject.fromJson(json);
    case 'parallelogram':
      return ParallelogramObject.fromJson(json);
    case 'fork_join':
      return ForkJoinObject.fromJson(json);
    case 'arrow':
      return ArrowObject.fromJson(json);
    case 'line':
      return LineObject.fromJson(json);
    case 'pencil_stroke':
      return PencilStrokeObject.fromJson(json);
    case 'figure':
      return FigureObject.fromJson(json);
    case 'text':
      return TextObject.fromJson(json);
    default:
      return null;
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

/// What kind of entity a [EntityComment] is attached to.
enum CommentTargetType { arrow, line, shape, node, canvas }

/// A review comment attached to a specific edge (arrow/line), node/shape, or a
/// bare point on the canvas.
///
/// Comments let a human point at a particular entity ("I can't drag this
/// connector") and have that feedback resolved to an unambiguous entity id and
/// type, so an agent can act on it without guessing which thing was meant. For
/// arrows we also capture the source/target connections and the polyline that
/// was actually drawn, which is exactly what drag/routing feedback needs.
class EntityComment extends Equatable {
  /// Stable id for this comment.
  final String id;

  /// The id of the entity this comment is attached to, or null for a comment
  /// dropped on empty canvas.
  final String? targetId;

  /// The kind of entity [targetId] refers to.
  final CommentTargetType targetType;

  /// The human-written comment text.
  final String text;

  /// World-space anchor where the comment pin sits (the click point).
  final Offset anchorWorld;

  /// When the comment was created.
  final DateTime createdAt;

  /// Whether the comment has been addressed/resolved.
  final bool resolved;

  /// For arrow targets: id of the object/node the arrow starts from, if any.
  final String? sourceObjectId;

  /// For arrow targets: id of the object/node the arrow ends at, if any.
  final String? targetObjectId;

  /// For arrow targets: the polyline actually drawn on screen at comment time.
  /// Captured so routing/drag feedback references the real geometry.
  final List<Offset>? renderedPath;

  const EntityComment({
    required this.id,
    required this.targetId,
    required this.targetType,
    required this.text,
    required this.anchorWorld,
    required this.createdAt,
    this.resolved = false,
    this.sourceObjectId,
    this.targetObjectId,
    this.renderedPath,
  });

  EntityComment copyWith({
    String? text,
    bool? resolved,
  }) {
    return EntityComment(
      id: id,
      targetId: targetId,
      targetType: targetType,
      text: text ?? this.text,
      anchorWorld: anchorWorld,
      createdAt: createdAt,
      resolved: resolved ?? this.resolved,
      sourceObjectId: sourceObjectId,
      targetObjectId: targetObjectId,
      renderedPath: renderedPath,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'targetId': targetId,
    'targetType': targetType.name,
    'text': text,
    'anchorWorld': [anchorWorld.dx, anchorWorld.dy],
    'createdAt': createdAt.toIso8601String(),
    'resolved': resolved,
    if (sourceObjectId != null) 'sourceObjectId': sourceObjectId,
    if (targetObjectId != null) 'targetObjectId': targetObjectId,
    if (renderedPath != null)
      'renderedPath': renderedPath!.map((p) => [p.dx, p.dy]).toList(),
  };

  factory EntityComment.fromJson(Map<String, dynamic> json) {
    return EntityComment(
      id: json['id'] as String,
      targetId: json['targetId'] as String?,
      targetType: CommentTargetType.values.firstWhere(
        (t) => t.name == json['targetType'],
        orElse: () => CommentTargetType.canvas,
      ),
      text: json['text'] as String,
      anchorWorld: Offset(
        (json['anchorWorld'][0] as num).toDouble(),
        (json['anchorWorld'][1] as num).toDouble(),
      ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      resolved: json['resolved'] as bool? ?? false,
      sourceObjectId: json['sourceObjectId'] as String?,
      targetObjectId: json['targetObjectId'] as String?,
      renderedPath: (json['renderedPath'] as List?)
          ?.map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
    id,
    targetId,
    targetType,
    text,
    anchorWorld,
    createdAt,
    resolved,
    sourceObjectId,
    targetObjectId,
    renderedPath,
  ];
}
