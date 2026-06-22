import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flow_draw/src/core/utils/orthogonal_router.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/styles.dart';

// Theme constants (dark background, colored strokes — matches app).
const _bg = '#1a1a1a';
const _stroke = '#e0e0e0';
const _arrowStroke = '#90caf9';
const _lineStroke = '#a5d6a7';
const _pencilStroke = '#ffcc80';
const _figureStroke = '#ce93d8';
const _textColor = '#e0e0e0';
const _defaultStrokeWidth = 2;
const _margin = 60.0;
const _cornerRadius = 6.0;
const _arrowHeadSize = 12.0;

class SvgExporter {
  SvgExporter._();

  /// The global default font used for non-customized shape text during the
  /// current [export] call. Set at the top of [export] so the per-shape
  /// renderers can resolve effective fonts without threading extra params.
  static String _exportDefaultFontFamily = kEditorDefaultFontFamily;
  static double _exportDefaultFontSize = kEditorDefaultFontSize;

  /// Maps a Flutter generic font family name to a CSS-friendly equivalent.
  /// 'Courier' renders as a monospace; the generic names pass through.
  static String _cssFontFamily(String family) {
    switch (family) {
      case 'Courier':
        return "'Courier New', Courier, monospace";
      default:
        return family;
    }
  }

  /// Emits the `font-size`/`font-family` SVG attributes for a shape's text,
  /// honoring its per-shape override or the global default.
  static String _shapeFontAttrs(TextStyle? style, bool fontCustomized) {
    final resolved = effectiveShapeTextStyle(
      style: style,
      customized: fontCustomized,
      defaultFamily: _exportDefaultFontFamily,
      defaultSize: _exportDefaultFontSize,
    );
    final family = _cssFontFamily(resolved.fontFamily ?? _exportDefaultFontFamily);
    final size = (resolved.fontSize ?? _exportDefaultFontSize).toStringAsFixed(1);
    return 'font-size="$size" font-family="$family"';
  }

  /// Builds the inner content of a shape's `<text>` element. For rich text
  /// ([runs] non-null) each run becomes a `<tspan>` carrying only the
  /// attributes it overrides; the outer `<text>` supplies the defaults via
  /// [_shapeFontAttrs]. For plain text the escaped string is returned directly.
  static String _shapeTextContent(String text, List<TextRun>? runs) {
    if (runs == null || runs.isEmpty) {
      return _escapeXml(text);
    }
    final buf = StringBuffer();
    for (final r in runs) {
      final attrs = <String>[];
      if (r.fontFamily != null) {
        attrs.add('font-family="${_cssFontFamily(r.fontFamily!)}"');
      }
      if (r.fontSize != null) {
        attrs.add('font-size="${r.fontSize!.toStringAsFixed(1)}"');
      }
      if (r.bold != null) {
        attrs.add('font-weight="${r.bold! ? 'bold' : 'normal'}"');
      }
      if (r.italic != null) {
        attrs.add('font-style="${r.italic! ? 'italic' : 'normal'}"');
      }
      if (r.color != null) {
        attrs.add('fill="${_hexColor(r.color!)}"');
      }
      final escaped = _escapeXml(r.text);
      if (attrs.isEmpty) {
        buf.write(escaped);
      } else {
        buf.write('<tspan ${attrs.join(' ')}>$escaped</tspan>');
      }
    }
    return buf.toString();
  }

  /// Formats an ARGB color int as an SVG `#rrggbb` hex string.
  static String _hexColor(int argb) {
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  /// Exports a map of drawing objects to an SVG string.
  ///
  /// [defaultFontFamily]/[defaultFontSize] supply the global default font for
  /// shapes whose font has not been individually customized.
  static String export(
    Map<String, DrawingObject> objects, {
    String defaultFontFamily = kEditorDefaultFontFamily,
    double defaultFontSize = kEditorDefaultFontSize,
  }) {
    _exportDefaultFontFamily = defaultFontFamily;
    _exportDefaultFontSize = defaultFontSize;
    // Build solid-object rects for arrow attachment resolution.
    final solidRects = <String, Rect>{};
    for (final entry in objects.entries) {
      final obj = entry.value;
      if (obj is RectangleObject ||
          obj is CircleObject ||
          obj is DiamondObject ||
          obj is ParallelogramObject ||
          obj is ForkJoinObject ||
          obj is FigureObject ||
          obj is TextObject ||
          obj is SvgObject) {
        solidRects[entry.key] = obj.rect;
      }
    }

    final svgElements = <String>[];
    final allBounds = <Rect>[];

    for (final obj in objects.values) {
      switch (obj) {
        case RectangleObject():
          _renderRectangle(obj, svgElements, allBounds);
        case CircleObject():
          _renderCircle(obj, svgElements, allBounds);
        case DiamondObject():
          _renderDiamond(obj, svgElements, allBounds);
        case ParallelogramObject():
          _renderParallelogram(obj, svgElements, allBounds);
        case ForkJoinObject():
          _renderForkJoin(obj, svgElements, allBounds);
        case ArrowObject():
          _renderArrow(obj, objects, solidRects, svgElements, allBounds);
        case LineObject():
          _renderLine(obj, svgElements, allBounds);
        case PencilStrokeObject():
          _renderPencilStroke(obj, svgElements, allBounds);
        case FigureObject():
          _renderFigure(obj, svgElements, allBounds);
        case TextObject():
          _renderText(obj, svgElements, allBounds);
        case SvgObject():
          break; // Skip — can't re-export without asset data.
      }
    }

    if (allBounds.isEmpty) return '';

    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final b in allBounds) {
      minX = math.min(minX, b.left);
      minY = math.min(minY, b.top);
      maxX = math.max(maxX, b.right);
      maxY = math.max(maxY, b.bottom);
    }
    minX -= _margin;
    minY -= _margin;
    maxX += _margin;
    maxY += _margin;
    final vw = maxX - minX;
    final vh = maxY - minY;

    final svg = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<svg xmlns="http://www.w3.org/2000/svg"')
      ..writeln('     viewBox="$minX $minY $vw $vh"')
      ..writeln('     width="${vw.round()}" height="${vh.round()}">')
      ..writeln(
          '  <rect x="$minX" y="$minY" width="$vw" height="$vh" fill="$_bg"/>')
      ..writeln()
      ..writeAll(svgElements, '\n')
      ..writeln()
      ..writeln('</svg>');

    return svg.toString();
  }

  // -- Renderers -------------------------------------------------------------

  static void _renderRectangle(
    RectangleObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final rect = obj.rect;
    final dashArray = _dashArray(obj.lineStyle);
    final rotOpen = _rotateOpen(obj.angle, rect.center);
    final rotClose = _rotateClose(obj.angle);

    if (rotOpen.isNotEmpty) svg.add(rotOpen);

    final fill = obj.fillColor != null ? _colorToHex(obj.fillColor!) : 'none';
    final stroke = obj.strokeColor != null ? _colorToHex(obj.strokeColor!) : _stroke;
    final radius = obj.borderRadius > 0 ? obj.borderRadius : _cornerRadius;
    svg.add('  <rect x="${rect.left}" y="${rect.top}" '
        'width="${rect.width}" height="${rect.height}" '
        'rx="$radius" ry="$radius" '
        'fill="$fill" stroke="$stroke" stroke-width="$_defaultStrokeWidth"'
        '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
        '/>');

    if (obj.text != null && obj.text!.isNotEmpty) {
      svg.add('  <text x="${rect.center.dx}" y="${rect.center.dy}" '
          'fill="$_textColor" ${_shapeFontAttrs(obj.textStyle, obj.fontCustomized)} '
          'text-anchor="middle" dominant-baseline="central">'
          '${_shapeTextContent(obj.text!, obj.richText)}</text>');
    }

    if (rotClose.isNotEmpty) svg.add(rotClose);

    bounds.add(rect);
  }

  static void _renderCircle(
    CircleObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final rect = obj.rect;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    final dashArray = _dashArray(obj.lineStyle);
    final rotOpen = _rotateOpen(obj.angle, rect.center);
    final rotClose = _rotateClose(obj.angle);

    if (rotOpen.isNotEmpty) svg.add(rotOpen);

    final fill = obj.fillColor != null ? _colorToHex(obj.fillColor!) : 'none';
    final stroke = obj.strokeColor != null ? _colorToHex(obj.strokeColor!) : _stroke;
    svg.add('  <ellipse cx="$cx" cy="$cy" rx="$rx" ry="$ry" '
        'fill="$fill" stroke="$stroke" stroke-width="$_defaultStrokeWidth"'
        '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
        '/>');

    if (obj.text != null && obj.text!.isNotEmpty) {
      svg.add('  <text x="$cx" y="$cy" '
          'fill="$_textColor" ${_shapeFontAttrs(obj.textStyle, obj.fontCustomized)} '
          'text-anchor="middle" dominant-baseline="central">'
          '${_shapeTextContent(obj.text!, obj.richText)}</text>');
    }

    if (rotClose.isNotEmpty) svg.add(rotClose);

    bounds.add(rect);
  }

  static void _renderDiamond(
    DiamondObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final r = obj.rect;
    final cx = r.center.dx;
    final cy = r.center.dy;
    final hw = r.width / 2;
    final hh = r.height / 2;
    final points = '${cx},${cy - hh} ${cx + hw},$cy ${cx},${cy + hh} ${cx - hw},$cy';
    final dashArray = _dashArray(obj.lineStyle);
    final rotOpen = _rotateOpen(obj.angle, r.center);
    final rotClose = _rotateClose(obj.angle);

    if (rotOpen.isNotEmpty) svg.add(rotOpen);

    final fill = obj.fillColor != null ? _colorToHex(obj.fillColor!) : 'none';
    final stroke = obj.strokeColor != null ? _colorToHex(obj.strokeColor!) : _stroke;
    svg.add('  <polygon points="$points" '
        'fill="$fill" stroke="$stroke" stroke-width="$_defaultStrokeWidth"'
        '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
        '/>');

    if (obj.text != null && obj.text!.isNotEmpty) {
      svg.add('  <text x="$cx" y="$cy" '
          'fill="$_textColor" ${_shapeFontAttrs(obj.textStyle, obj.fontCustomized)} '
          'text-anchor="middle" dominant-baseline="central">'
          '${_shapeTextContent(obj.text!, obj.richText)}</text>');
    }

    if (rotClose.isNotEmpty) svg.add(rotClose);

    bounds.add(r);
  }

  static void _renderParallelogram(
    ParallelogramObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final r = obj.rect;
    final s = obj.skewOffset;
    final points = '${r.left + s},${r.top} ${r.right},${r.top} ${r.right - s},${r.bottom} ${r.left},${r.bottom}';
    final dashArray = _dashArray(obj.lineStyle);
    final rotOpen = _rotateOpen(obj.angle, r.center);
    final rotClose = _rotateClose(obj.angle);

    if (rotOpen.isNotEmpty) svg.add(rotOpen);
    svg.add('  <polygon points="$points" '
        'fill="none" stroke="$_stroke" stroke-width="$_defaultStrokeWidth"'
        '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
        '/>');
    if (obj.text != null && obj.text!.isNotEmpty) {
      svg.add('  <text x="${r.center.dx}" y="${r.center.dy}" '
          'fill="$_textColor" ${_shapeFontAttrs(obj.textStyle, obj.fontCustomized)} '
          'text-anchor="middle" dominant-baseline="central">'
          '${_shapeTextContent(obj.text!, obj.richText)}</text>');
    }
    if (rotClose.isNotEmpty) svg.add(rotClose);
    bounds.add(r);
  }

  static void _renderForkJoin(
    ForkJoinObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final r = obj.rect;
    svg.add('  <rect x="${r.left}" y="${r.top}" width="${r.width}" height="${r.height}" '
        'rx="3" ry="3" fill="$_stroke" stroke="none"/>');
    bounds.add(r);
  }

  static void _renderArrow(
    ArrowObject obj,
    Map<String, DrawingObject> objects,
    Map<String, Rect> solidRects,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final dashArray = _dashArray(obj.lineStyle);
    // Undirected edges (arrowHead == none) export as a plain line, no head.
    final showHead = obj.arrowHead != ArrowHeadType.none;

    if (obj.pathType == LinkPathType.orthogonal) {
      var fullPath = _computeOrthogonalPath(obj, solidRects);
      if (fullPath.length < 2) fullPath = [obj.start, obj.end];

      final pathD = _buildRoundedOrthogonalPath(fullPath);
      svg.add('  <path d="$pathD" '
          'fill="none" stroke="$_arrowStroke" stroke-width="$_defaultStrokeWidth" '
          'stroke-linecap="round"'
          '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
          '/>');
      if (showHead) _renderArrowhead(fullPath, svg);
      _addPathBounds(fullPath, bounds);
    } else {
      // Straight or curved (quadratic bezier via midPoint).
      final cp = obj.midPoint ?? (obj.start + obj.end) / 2;
      final hasCurve = obj.midPoint != null;

      if (hasCurve) {
        svg.add('  <path d="M${obj.start.dx},${obj.start.dy} '
            'Q${cp.dx},${cp.dy} ${obj.end.dx},${obj.end.dy}" '
            'fill="none" stroke="$_arrowStroke" stroke-width="$_defaultStrokeWidth" '
            'stroke-linejoin="round" stroke-linecap="round"'
            '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
            '/>');
        // Arrowhead: use tangent at t=1 of the quadratic bezier.
        // Tangent direction at t=1: 2*(end - cp)
        final tangent = obj.end - cp;
        final len = math.sqrt(tangent.dx * tangent.dx + tangent.dy * tangent.dy);
        if (len > 0.1 && showHead) {
          _renderArrowhead([obj.end - tangent * (1.0 / len), obj.end], svg);
        }
      } else {
        final points = '${obj.start.dx},${obj.start.dy} ${obj.end.dx},${obj.end.dy}';
        svg.add('  <polyline points="$points" '
            'fill="none" stroke="$_arrowStroke" stroke-width="$_defaultStrokeWidth" '
            'stroke-linejoin="round" stroke-linecap="round"'
            '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
            '/>');
        if (showHead) _renderArrowhead([obj.start, obj.end], svg);
      }

      // Bounds: include control point for curves.
      _addPathBounds([obj.start, cp, obj.end], bounds);
    }

    // Render arrow label at the midpoint
    if (obj.arrowLabel != null && obj.arrowLabel!.isNotEmpty) {
      Offset labelCenter;
      if (obj.pathType == LinkPathType.orthogonal) {
        var fullPath = _computeOrthogonalPath(obj, solidRects);
        if (fullPath.length < 2) fullPath = [obj.start, obj.end];
        // Walk along segments to find the geometric midpoint
        double totalLen = 0;
        for (int i = 0; i < fullPath.length - 1; i++) {
          totalLen += (fullPath[i + 1] - fullPath[i]).distance;
        }
        double halfLen = totalLen / 2;
        labelCenter = fullPath.last;
        for (int i = 0; i < fullPath.length - 1; i++) {
          final segLen = (fullPath[i + 1] - fullPath[i]).distance;
          if (halfLen <= segLen) {
            final t = segLen > 0 ? halfLen / segLen : 0.0;
            labelCenter = Offset(
              fullPath[i].dx + (fullPath[i + 1].dx - fullPath[i].dx) * t,
              fullPath[i].dy + (fullPath[i + 1].dy - fullPath[i].dy) * t,
            );
            break;
          }
          halfLen -= segLen;
        }
      } else {
        final cp = obj.midPoint ?? (obj.start + obj.end) / 2;
        labelCenter = Offset(
          0.25 * obj.start.dx + 0.5 * cp.dx + 0.25 * obj.end.dx,
          0.25 * obj.start.dy + 0.5 * cp.dy + 0.25 * obj.end.dy,
        );
      }

      final escaped = _escapeXml(obj.arrowLabel!);
      // Background rect for readability — approximate text bounds
      final estWidth = escaped.length * 8.0 + 8;
      final estHeight = 20.0;
      svg.add('  <rect x="${labelCenter.dx - estWidth / 2}" '
          'y="${labelCenter.dy - estHeight / 2}" '
          'width="$estWidth" height="$estHeight" '
          'rx="3" ry="3" fill="$_bg" fill-opacity="0.88"/>');
      svg.add('  <text x="${labelCenter.dx}" y="${labelCenter.dy}" '
          'fill="$_textColor" font-size="12" font-family="sans-serif" '
          'text-anchor="middle" dominant-baseline="central">'
          '$escaped</text>');
    }
  }

  static void _renderLine(
    LineObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final dashArray = _dashArray(obj.lineStyle);
    final hasCurve = obj.midPoint != null;

    if (hasCurve) {
      final cp = obj.midPoint!;
      svg.add('  <path d="M${obj.start.dx},${obj.start.dy} '
          'Q${cp.dx},${cp.dy} ${obj.end.dx},${obj.end.dy}" '
          'fill="none" stroke="$_lineStroke" stroke-width="$_defaultStrokeWidth" '
          'stroke-linejoin="round" stroke-linecap="round"'
          '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
          '/>');
      _addPathBounds([obj.start, cp, obj.end], bounds);
    } else {
      final points =
          '${obj.start.dx},${obj.start.dy} ${obj.end.dx},${obj.end.dy}';
      svg.add('  <polyline points="$points" '
          'fill="none" stroke="$_lineStroke" stroke-width="$_defaultStrokeWidth" '
          'stroke-linejoin="round" stroke-linecap="round"'
          '${dashArray.isNotEmpty ? ' stroke-dasharray="$dashArray"' : ''}'
          '/>');
      bounds.add(Rect.fromPoints(obj.start, obj.end));
    }
  }

  static void _renderPencilStroke(
    PencilStrokeObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    if (obj.points.isEmpty) return;

    final pointsStr =
        obj.points.map((p) => '${p.x},${p.y}').join(' ');
    svg.add('  <polyline points="$pointsStr" '
        'fill="none" stroke="$_pencilStroke" stroke-width="1.5" '
        'stroke-linejoin="round" stroke-linecap="round"/>');

    bounds.add(obj.rect);
  }

  static void _renderFigure(
    FigureObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final rect = obj.rect;
    final rotOpen = _rotateOpen(obj.angle, rect.center);
    final rotClose = _rotateClose(obj.angle);

    if (rotOpen.isNotEmpty) svg.add(rotOpen);

    svg.add('  <rect x="${rect.left}" y="${rect.top}" '
        'width="${rect.width}" height="${rect.height}" '
        'fill="none" stroke="$_figureStroke" stroke-width="1" '
        'stroke-dasharray="6,3"/>');

    if (obj.label.isNotEmpty) {
      svg.add('  <text x="${rect.left + 6}" y="${rect.top + 14}" '
          'fill="$_figureStroke" font-size="12" font-family="sans-serif">'
          '${_escapeXml(obj.label)}</text>');
    }

    if (rotClose.isNotEmpty) svg.add(rotClose);

    bounds.add(rect);
  }

  static void _renderText(
    TextObject obj,
    List<String> svg,
    List<Rect> bounds,
  ) {
    final rect = obj.rect;
    final rotOpen = _rotateOpen(obj.angle, rect.center);
    final rotClose = _rotateClose(obj.angle);

    if (rotOpen.isNotEmpty) svg.add(rotOpen);

    if (obj.text.isNotEmpty) {
      final family = _cssFontFamily(obj.style.fontFamily ?? _exportDefaultFontFamily);
      final size = (obj.style.fontSize ?? _exportDefaultFontSize).toStringAsFixed(1);
      svg.add('  <text x="${rect.center.dx}" y="${rect.center.dy}" '
          'fill="$_textColor" font-size="$size" font-family="$family" '
          'text-anchor="middle" dominant-baseline="central">'
          '${_escapeXml(obj.text)}</text>');
    }

    if (rotClose.isNotEmpty) svg.add(rotClose);

    bounds.add(rect);
  }

  // -- Rounded orthogonal path -----------------------------------------------

  /// Builds an SVG path string with rounded corners at each bend,
  /// matching the app's `arcToPoint` rendering.
  static String _buildRoundedOrthogonalPath(List<Offset> allPoints) {
    const double cornerRadius = 30.0;
    final sb = StringBuffer();
    sb.write('M${allPoints[0].dx},${allPoints[0].dy}');

    for (int i = 1; i < allPoints.length - 1; i++) {
      final prev = allPoints[i - 1];
      final curr = allPoints[i];
      final next = allPoints[i + 1];
      final segPrev = (curr - prev).distance;
      final segNext = (next - curr).distance;
      final r = math.min(cornerRadius, math.min(segPrev / 2, segNext / 2));

      if (r < 1.0) {
        sb.write(' L${curr.dx},${curr.dy}');
        continue;
      }

      final dirIn = Offset(
          (curr.dx - prev.dx) / segPrev, (curr.dy - prev.dy) / segPrev);
      final dirOut = Offset(
          (next.dx - curr.dx) / segNext, (next.dy - curr.dy) / segNext);
      final cross = dirIn.dx * dirOut.dy - dirIn.dy * dirOut.dx;
      if (cross.abs() < 0.01) {
        sb.write(' L${curr.dx},${curr.dy}');
        continue;
      }

      final arcStart =
          Offset(curr.dx - dirIn.dx * r, curr.dy - dirIn.dy * r);
      final arcEnd =
          Offset(curr.dx + dirOut.dx * r, curr.dy + dirOut.dy * r);
      // SVG arc: A rx ry x-rotation large-arc-flag sweep-flag x y
      // sweep-flag: 1 = clockwise, 0 = counter-clockwise
      final sweep = cross > 0 ? 1 : 0;
      sb.write(' L${arcStart.dx},${arcStart.dy}');
      sb.write(' A$r,$r 0 0,$sweep ${arcEnd.dx},${arcEnd.dy}');
    }

    sb.write(' L${allPoints.last.dx},${allPoints.last.dy}');
    return sb.toString();
  }

  // -- Arrow routing ---------------------------------------------------------

  static List<Offset> _computeOrthogonalPath(
    ArrowObject arrow,
    Map<String, Rect> solidRects,
  ) {
    Rect? startObjRect;
    Rect? endObjRect;
    var routeStart = arrow.start;
    var routeEnd = arrow.end;

    if (arrow.startAttachment != null) {
      startObjRect = solidRects[arrow.startAttachment!.objectId];
      if (startObjRect != null) {
        routeStart = _resolveAttachment(
            arrow.startAttachment!.relativePosition, startObjRect);
      }
    }

    if (arrow.endAttachment != null) {
      endObjRect = solidRects[arrow.endAttachment!.objectId];
      if (endObjRect != null) {
        routeEnd = _resolveAttachment(
            arrow.endAttachment!.relativePosition, endObjRect);
      }
    }

    // Collect obstacles — all solid objects except source and target.
    final sourceId = arrow.startAttachment?.objectId;
    final targetId = arrow.endAttachment?.objectId;
    final obstacles = <Rect>[];
    for (final entry in solidRects.entries) {
      if (entry.key == sourceId || entry.key == targetId) continue;
      obstacles.add(entry.value);
    }

    final waypoints = OrthogonalRouter.route(
      start: routeStart,
      end: routeEnd,
      obstacles: obstacles,
      startObjectRect: startObjRect,
      endObjectRect: endObjRect,
    );

    return [routeStart, ...waypoints, routeEnd];
  }

  /// Convert a relative position (0-1 normalized) to absolute coords on a rect,
  /// snapping to the nearest edge.
  static Offset _resolveAttachment(Offset relPos, Rect rect) {
    final absX = rect.left + relPos.dx * rect.width;
    final absY = rect.top + relPos.dy * rect.height;

    final distLeft = (absX - rect.left).abs();
    final distRight = (absX - rect.right).abs();
    final distTop = (absY - rect.top).abs();
    final distBottom = (absY - rect.bottom).abs();
    final minDist =
        [distLeft, distRight, distTop, distBottom].reduce(math.min);

    if (minDist == distLeft) return Offset(rect.left, absY);
    if (minDist == distRight) return Offset(rect.right, absY);
    if (minDist == distTop) return Offset(absX, rect.top);
    return Offset(absX, rect.bottom);
  }

  // -- Arrowhead -------------------------------------------------------------

  static void _renderArrowhead(List<Offset> path, List<String> svg) {
    if (path.length < 2) return;
    final tip = path.last;
    final prev = path[path.length - 2];

    final dx = tip.dx - prev.dx;
    final dy = tip.dy - prev.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.1) return;

    final ux = dx / len;
    final uy = dy / len;

    final px = -uy;
    final py = ux;

    final s = _arrowHeadSize;
    final base1 = Offset(
        tip.dx - ux * s + px * s * 0.4, tip.dy - uy * s + py * s * 0.4);
    final base2 = Offset(
        tip.dx - ux * s - px * s * 0.4, tip.dy - uy * s - py * s * 0.4);

    svg.add(
        '  <polygon points="${tip.dx},${tip.dy} ${base1.dx},${base1.dy} ${base2.dx},${base2.dy}" '
        'fill="$_arrowStroke"/>');
  }

  // -- Rotation --------------------------------------------------------------

  /// Returns `<g transform="rotate(...)">` if angle is non-zero.
  /// Flutter's angle is in radians; SVG rotate() takes degrees.
  static String _rotateOpen(double angle, Offset center) {
    if (angle.abs() < 0.001) return '';
    final degrees = angle * 180.0 / math.pi;
    return '  <g transform="rotate($degrees ${center.dx} ${center.dy})">';
  }

  static String _rotateClose(double angle) {
    if (angle.abs() < 0.001) return '';
    return '  </g>';
  }

  // -- Bounds ----------------------------------------------------------------

  static void _addPathBounds(List<Offset> points, List<Rect> bounds) {
    var bMinX = double.infinity, bMinY = double.infinity;
    var bMaxX = double.negativeInfinity, bMaxY = double.negativeInfinity;
    for (final p in points) {
      bMinX = math.min(bMinX, p.dx);
      bMinY = math.min(bMinY, p.dy);
      bMaxX = math.max(bMaxX, p.dx);
      bMaxY = math.max(bMaxY, p.dy);
    }
    bounds.add(Rect.fromLTRB(bMinX, bMinY, bMaxX, bMaxY));
  }

  // -- Helpers ---------------------------------------------------------------

  static String _dashArray(LineStyle lineStyle) {
    return switch (lineStyle) {
      LineStyle.dashed => '8,4',
      LineStyle.dotted => '2,4',
      _ => '',
    };
  }

  static String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Converts a Color to an SVG hex color string.
  static String _colorToHex(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }
}
