import 'package:flutter/material.dart';

import 'package:flow_draw/src/models/entities.dart';

enum FlLineDrawMode { solid, dashed, dotted }

enum LineStyle { solid, dashed, dotted, rough }

class FlGridStyle {
  final double gridSpacingX;
  final double gridSpacingY;
  final double lineWidth;
  final Color lineColor;
  final Color intersectionColor;
  final double intersectionRadius;
  final bool showGrid;

  const FlGridStyle({
    this.gridSpacingX = 16.0,
    this.gridSpacingY = 16.0,
    this.lineWidth = 0,
    this.lineColor = const Color.fromARGB(64, 100, 100, 100),
    this.intersectionColor = const Color.fromARGB(32, 150, 150, 150),
    this.intersectionRadius = 1.2,
    this.showGrid = true,
  });

  FlGridStyle copyWith({
    double? gridSpacingX,
    double? gridSpacingY,
    double? lineWidth,
    Color? lineColor,
    Color? intersectionColor,
    double? intersectionRadius,
    bool? showGrid,
  }) {
    return FlGridStyle(
      gridSpacingX: gridSpacingX ?? this.gridSpacingX,
      gridSpacingY: gridSpacingY ?? this.gridSpacingY,
      lineWidth: lineWidth ?? this.lineWidth,
      lineColor: lineColor ?? this.lineColor,
      intersectionColor: intersectionColor ?? this.intersectionColor,
      intersectionRadius: intersectionRadius ?? this.intersectionRadius,
      showGrid: showGrid ?? this.showGrid,
    );
  }
}

class FlSelectionAreaStyle {
  final Color color;
  final double borderWidth;
  final Color borderColor;
  final FlLineDrawMode borderDrawMode;

  const FlSelectionAreaStyle({
    this.color = const Color.fromARGB(25, 33, 150, 243),
    this.borderWidth = 1.0,
    this.borderColor = const Color.fromARGB(255, 33, 150, 243),
    this.borderDrawMode = FlLineDrawMode.solid,
  });

  FlSelectionAreaStyle copyWith({
    Color? color,
    double? borderWidth,
    Color? borderColor,
    FlLineDrawMode? borderDrawMode,
  }) {
    return FlSelectionAreaStyle(
      color: color ?? this.color,
      borderWidth: borderWidth ?? this.borderWidth,
      borderColor: borderColor ?? this.borderColor,
      borderDrawMode: borderDrawMode ?? this.borderDrawMode,
    );
  }
}

enum FlLinkCurveType { straight, bezier, ninetyDegree }

class FlLinkStyle {
  final Color? color;
  final bool useGradient;
  final LinearGradient? gradient;
  final double lineWidth;
  final FlLineDrawMode drawMode;
  final FlLinkCurveType curveType;

  const FlLinkStyle({
    this.color,
    this.useGradient = false,
    this.gradient,
    required this.lineWidth,
    required this.drawMode,
    required this.curveType,
  }) : assert(
         useGradient == false || gradient != null,
         'Gradient must be provided if useGradient is true',
       );

  FlLinkStyle copyWith({
    LinearGradient? gradient,
    double? lineWidth,
    FlLineDrawMode? drawMode,
    FlLinkCurveType? curveType,
  }) {
    return FlLinkStyle(
      gradient: gradient ?? this.gradient,
      lineWidth: lineWidth ?? this.lineWidth,
      drawMode: drawMode ?? this.drawMode,
      curveType: curveType ?? this.curveType,
    );
  }
}

class FlNodeHeaderStyle {
  final EdgeInsets padding;
  final BoxDecoration decoration;
  final TextStyle textStyle;
  final IconData? icon;

  const FlNodeHeaderStyle({
    required this.padding,
    required this.decoration,
    required this.textStyle,
    required this.icon,
  });

  FlNodeHeaderStyle copyWith({
    EdgeInsets? padding,
    BoxDecoration? decoration,
    TextStyle? textStyle,
    IconData? icon,
  }) {
    return FlNodeHeaderStyle(
      padding: padding ?? this.padding,
      decoration: decoration ?? this.decoration,
      textStyle: textStyle ?? this.textStyle,
      icon: icon ?? this.icon,
    );
  }
}

typedef FlNodeHeaderStyleBuilder = FlNodeHeaderStyle Function(NodeState style, {double devicePixelRatio});

FlNodeHeaderStyle defaultNodeHeaderStyle(NodeState state, {double devicePixelRatio = 1.0}) {
  final r = 7.0 * devicePixelRatio;
  return FlNodeHeaderStyle(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    textStyle: TextStyle(fontSize: 16),
    decoration: BoxDecoration(
      color: Color(0xFF27272A),
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(r),
        topRight: Radius.circular(r),
        bottomLeft: Radius.circular(state.isCollapsed ? r : 0),
        bottomRight: Radius.circular(state.isCollapsed ? r : 0),
      ),
    ),
    icon: state.isCollapsed ? Icons.expand_more : Icons.expand_less,
  );
}

class FlNodeStyle {
  final BoxDecoration decoration;

  const FlNodeStyle({required this.decoration});

  FlNodeStyle copyWith({BoxDecoration? decoration}) {
    return FlNodeStyle(decoration: decoration ?? this.decoration);
  }
}

typedef FlNodeStyleBuilder = FlNodeStyle Function(NodeState style, {double devicePixelRatio});

FlNodeStyle defaultNodeStyle(NodeState state, {double devicePixelRatio = 1.0}) {
  final r = 10.0 * devicePixelRatio;
  return FlNodeStyle(
    decoration: BoxDecoration(
      color: Color(0xFF27272A),
      borderRadius: BorderRadius.all(Radius.circular(r)),
    ),
  );
}

class FlowDrawEditorStyle {
  final BoxDecoration decoration;
  final EdgeInsetsGeometry padding;
  final FlGridStyle gridStyle;
  final FlSelectionAreaStyle selectionAreaStyle;

  const FlowDrawEditorStyle({
    this.decoration = const BoxDecoration(color: Color(0xFF1C1C1E)),
    this.padding = const EdgeInsets.all(8.0),
    this.gridStyle = const FlGridStyle(),
    this.selectionAreaStyle = const FlSelectionAreaStyle(),
  });

  FlowDrawEditorStyle copyWith({
    BoxDecoration? decoration,
    EdgeInsetsGeometry? padding,
    FlGridStyle? gridStyle,
    FlSelectionAreaStyle? selectionAreaStyle,
  }) {
    return FlowDrawEditorStyle(
      decoration: decoration ?? this.decoration,
      padding: padding ?? this.padding,
      gridStyle: gridStyle ?? this.gridStyle,
      selectionAreaStyle: selectionAreaStyle ?? this.selectionAreaStyle,
    );
  }
}
