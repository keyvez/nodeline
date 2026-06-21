import 'dart:ui';

import 'package:flow_draw/src/blocs/canvas/canvas_bloc.dart';
import 'package:flow_draw/src/blocs/selection/selection_bloc.dart';
import 'package:flow_draw/src/blocs/selection/selection_resolver.dart';
import 'package:flow_draw/src/core/agent/tool_call.dart';
import 'package:flow_draw/src/models/drawing_entities.dart';
import 'package:flow_draw/src/models/styles.dart';
import 'package:uuid/uuid.dart';

/// Executes [ToolCall]s against the canvas by translating each into BLoC events.
///
/// This is the deterministic bridge between "what the model asked for" and the
/// app's state. It contains no LLM logic and is fully unit-testable: feed it
/// [ToolCall]s, assert on the resulting [CanvasBloc]/[SelectionBloc] state.
///
/// Every tool returns a [ToolResult] whose [ToolResult.summary] is the line fed
/// back to the model. Unknown tools and bad arguments produce error results
/// rather than throwing, so a single bad call never kills the agent loop.
class ToolDispatcher {
  final CanvasBloc canvasBloc;
  final SelectionBloc selectionBloc;
  final Uuid _uuid;

  /// Default placement grid for created nodes that don't specify x/y.
  static const double _autoColumnWidth = 200;
  static const double _autoRowHeight = 120;
  static const Size _defaultNodeSize = Size(140, 70);

  ToolDispatcher({
    required this.canvasBloc,
    required this.selectionBloc,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  /// The set of tool names this dispatcher handles. Step 3 derives the model's
  /// tool schema list from the same names.
  static const Set<String> toolNames = {
    'select',
    'clear_selection',
    'color_objects',
    'set_line_style',
    'create_nodes',
    'create_edges',
    'delete_objects',
    'align',
    'distribute',
    'auto_layout',
    'lay_along_guide',
    'get_selection',
    'get_canvas_summary',
  };

  /// Executes a single tool call. Never throws — failures become error results.
  ToolResult dispatch(ToolCall call) {
    try {
      return switch (call.name) {
        'select' => _select(call),
        'clear_selection' => _clearSelection(call),
        'color_objects' => _colorObjects(call),
        'set_line_style' => _setLineStyle(call),
        'create_nodes' => _createNodes(call),
        'create_edges' => _createEdges(call),
        'delete_objects' => _deleteObjects(call),
        'align' => _align(call),
        'distribute' => _distribute(call),
        'auto_layout' => _autoLayout(call),
        'lay_along_guide' => _layAlongGuide(call),
        'get_selection' => _getSelection(call),
        'get_canvas_summary' => _getCanvasSummary(call),
        _ => ToolResult.error('Unknown tool: ${call.name}', callId: call.id),
      };
    } catch (e) {
      return ToolResult.error('Tool ${call.name} failed: $e', callId: call.id);
    }
  }

  // --- selection ----------------------------------------------------------

  ToolResult _select(ToolCall c) {
    final query = _queryFromArgs(c.args);
    final ids = SelectionResolver.resolve(canvasBloc.state.drawingObjects, query);
    selectionBloc.add(SelectionReplaced(
      nodeIds: const {},
      drawingObjectIds: ids,
    ));
    return ToolResult.ok(
      'Selected ${ids.length} object(s)',
      callId: c.id,
      data: {'ids': ids.toList()},
    );
  }

  ToolResult _clearSelection(ToolCall c) {
    selectionBloc.add(SelectionCleared());
    return ToolResult.ok('Cleared selection', callId: c.id);
  }

  /// Builds a [SelectionQuery] from loosely-typed tool arguments.
  SelectionQuery _queryFromArgs(Map<String, dynamic> a) {
    return SelectionQuery(
      frameLabel: a['frame'] as String? ?? a['frameLabel'] as String?,
      frameId: a['frameId'] as String?,
      kind: _kindFromString(a['kind'] as String? ?? a['type'] as String?),
      labelContains: a['labelContains'] as String? ?? a['label'] as String?,
      labelMatches: a['labelMatches'] as String?,
      spatialFallback: a['spatialFallback'] as bool? ?? true,
    );
  }

  // --- styling ------------------------------------------------------------

  ToolResult _colorObjects(ToolCall c) {
    final ids = _idsFromArgs(c.args);
    if (ids.isEmpty) return ToolResult.error('No target ids', callId: c.id);
    final fill = _parseColor(c.args['fill'] ?? c.args['fillColor']);
    final stroke = _parseColor(c.args['stroke'] ?? c.args['strokeColor']);
    final clearFill = c.args['clearFill'] as bool? ?? false;
    final clearStroke = c.args['clearStroke'] as bool? ?? false;
    if (fill == null && stroke == null && !clearFill && !clearStroke) {
      return ToolResult.error('No color change specified', callId: c.id);
    }
    canvasBloc.add(ObjectColorsChanged(
      ids,
      fillColor: fill,
      strokeColor: stroke,
      clearFill: clearFill,
      clearStroke: clearStroke,
    ));
    return ToolResult.ok('Colored ${ids.length} object(s)', callId: c.id);
  }

  ToolResult _setLineStyle(ToolCall c) {
    final ids = _idsFromArgs(c.args);
    if (ids.isEmpty) return ToolResult.error('No target ids', callId: c.id);
    final style = _lineStyleFromString(c.args['style'] as String?);
    if (style == null) {
      return ToolResult.error(
        'Unknown line style: ${c.args['style']} (use solid/dashed/dotted/rough)',
        callId: c.id,
      );
    }
    canvasBloc.add(ObjectsLineStyleChanged(ids, style));
    return ToolResult.ok(
      'Set ${ids.length} object(s) to ${style.name}',
      callId: c.id,
    );
  }

  // --- creation -----------------------------------------------------------

  ToolResult _createNodes(ToolCall c) {
    final list = (c.args['nodes'] as List?) ?? const [];
    if (list.isEmpty) return ToolResult.error('No nodes provided', callId: c.id);

    final created = <String, String>{}; // label -> id
    var index = 0;
    for (final raw in list) {
      final n = (raw as Map).cast<String, dynamic>();
      final id = _uuid.v4();
      final label = n['label'] as String? ?? n['text'] as String? ?? '';
      final size = Size(
        (n['width'] as num?)?.toDouble() ?? _defaultNodeSize.width,
        (n['height'] as num?)?.toDouble() ?? _defaultNodeSize.height,
      );
      final pos = _autoPosition(n, index);
      final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
      final fill = _parseColor(n['fill'] ?? n['fillColor']);
      final stroke = _parseColor(n['stroke'] ?? n['strokeColor']);

      final obj = _makeNode(
        id: id,
        shape: (n['shape'] as String?)?.toLowerCase(),
        rect: rect,
        label: label,
        fill: fill,
        stroke: stroke,
      );
      canvasBloc.add(DrawingObjectAdded(obj));
      if (label.isNotEmpty) created[label] = id;
      index++;
    }
    return ToolResult.ok(
      'Created ${list.length} node(s)',
      callId: c.id,
      data: {'labelToId': created},
    );
  }

  DrawingObject _makeNode({
    required String id,
    required String? shape,
    required Rect rect,
    required String label,
    Color? fill,
    Color? stroke,
  }) {
    switch (shape) {
      case 'circle':
      case 'ellipse':
      case 'oval':
        return CircleObject(
            id: id, rect: rect, text: label, fillColor: fill, strokeColor: stroke);
      case 'diamond':
      case 'decision':
        return DiamondObject(
            id: id, rect: rect, text: label, fillColor: fill, strokeColor: stroke);
      case 'parallelogram':
      case 'io':
        return ParallelogramObject(
            id: id, rect: rect, text: label, fillColor: fill, strokeColor: stroke);
      case 'rectangle':
      case 'rect':
      case 'box':
      case null:
      default:
        return RectangleObject(
            id: id, rect: rect, text: label, fillColor: fill, strokeColor: stroke);
    }
  }

  Offset _autoPosition(Map<String, dynamic> n, int index) {
    final x = (n['x'] as num?)?.toDouble();
    final y = (n['y'] as num?)?.toDouble();
    if (x != null && y != null) return Offset(x, y);
    // Simple vertical stack with column wrapping for un-positioned nodes.
    const perColumn = 6;
    final col = index ~/ perColumn;
    final row = index % perColumn;
    return Offset(col * _autoColumnWidth, row * _autoRowHeight);
  }

  ToolResult _createEdges(ToolCall c) {
    final list = (c.args['edges'] as List?) ?? const [];
    if (list.isEmpty) return ToolResult.error('No edges provided', callId: c.id);

    final byId = canvasBloc.state.drawingObjects;
    // Resolve endpoints by id or by (unique) label.
    final labelToId = <String, String>{};
    for (final o in byId.values) {
      final l = SelectionResolver.labelOf(o);
      if (l != null && l.isNotEmpty) labelToId.putIfAbsent(l.toLowerCase(), () => o.id);
    }

    String? resolve(String? ref) {
      if (ref == null) return null;
      if (byId.containsKey(ref)) return ref;
      return labelToId[ref.toLowerCase()];
    }

    var made = 0;
    final unresolved = <String>[];
    for (final raw in list) {
      final e = (raw as Map).cast<String, dynamic>();
      final fromId = resolve(e['from'] as String?);
      final toId = resolve(e['to'] as String?);
      if (fromId == null || toId == null) {
        unresolved.add('${e['from']}→${e['to']}');
        continue;
      }
      final from = byId[fromId]!;
      final to = byId[toId]!;
      final style = _lineStyleFromString(e['style'] as String?) ?? LineStyle.solid;
      final arrow = ArrowObject(
        id: _uuid.v4(),
        start: from.rect.center,
        end: to.rect.center,
        pathType: LinkPathType.orthogonal,
        startAttachment:
            ObjectAttachment(objectId: fromId, relativePosition: const Offset(0.5, 0.5)),
        endAttachment:
            ObjectAttachment(objectId: toId, relativePosition: const Offset(0.5, 0.5)),
        lineStyle: style,
        arrowLabel: e['label'] as String?,
      );
      canvasBloc.add(DrawingObjectAdded(arrow));
      made++;
    }
    if (made == 0) {
      return ToolResult.error(
        'Could not resolve any edge endpoints: ${unresolved.join(', ')}',
        callId: c.id,
      );
    }
    final note = unresolved.isEmpty ? '' : ' (${unresolved.length} unresolved)';
    return ToolResult.ok('Created $made edge(s)$note', callId: c.id);
  }

  ToolResult _deleteObjects(ToolCall c) {
    final ids = _idsFromArgs(c.args);
    if (ids.isEmpty) return ToolResult.error('No target ids', callId: c.id);
    canvasBloc.add(ObjectsRemoved(nodeIds: const {}, drawingObjectIds: ids));
    return ToolResult.ok('Deleted ${ids.length} object(s)', callId: c.id);
  }

  // --- layout -------------------------------------------------------------

  ToolResult _align(ToolCall c) {
    final ids = _idsFromArgs(c.args);
    final type = _alignmentFromString(c.args['alignment'] as String?);
    if (type == null) {
      return ToolResult.error('Unknown alignment: ${c.args['alignment']}', callId: c.id);
    }
    canvasBloc.add(ObjectsAligned(ids, type));
    return ToolResult.ok('Aligned ${ids.length} object(s) (${type.name})', callId: c.id);
  }

  ToolResult _distribute(ToolCall c) {
    final ids = _idsFromArgs(c.args);
    final type = _distributionFromString(c.args['direction'] as String?);
    if (type == null) {
      return ToolResult.error('Unknown distribution: ${c.args['direction']}', callId: c.id);
    }
    canvasBloc.add(ObjectsDistributed(ids, type));
    return ToolResult.ok('Distributed ${ids.length} object(s) (${type.name})', callId: c.id);
  }

  ToolResult _autoLayout(ToolCall c) {
    canvasBloc.add(const AutoLayoutRequested());
    return ToolResult.ok('Requested auto-layout', callId: c.id);
  }

  ToolResult _layAlongGuide(ToolCall c) {
    canvasBloc.add(const LayoutAlongGuideRequested());
    return ToolResult.ok('Requested lay-along-guide', callId: c.id);
  }

  // --- read tools ---------------------------------------------------------

  ToolResult _getSelection(ToolCall c) {
    final ids = selectionBloc.state.selectedDrawingObjectIds;
    final objs = canvasBloc.state.drawingObjects;
    final items = [
      for (final id in ids)
        if (objs[id] != null)
          {
            'id': id,
            'type': _typeName(objs[id]!),
            'label': SelectionResolver.labelOf(objs[id]!),
          },
    ];
    return ToolResult.ok(
      '${items.length} selected',
      callId: c.id,
      data: {'selection': items},
    );
  }

  ToolResult _getCanvasSummary(ToolCall c) {
    final objs = canvasBloc.state.drawingObjects;
    final counts = <String, int>{};
    final frames = <Map<String, dynamic>>[];
    for (final o in objs.values) {
      final t = _typeName(o);
      counts[t] = (counts[t] ?? 0) + 1;
      if (o is FigureObject) {
        frames.add({'id': o.id, 'label': o.label, 'childrenIds': o.childrenIds.toList()});
      }
    }
    return ToolResult.ok(
      '${objs.length} objects',
      callId: c.id,
      data: {'counts': counts, 'frames': frames},
    );
  }

  // --- arg parsing helpers ------------------------------------------------

  /// Resolves the target ids for a tool: an explicit `ids` list if present,
  /// otherwise the current selection.
  Set<String> _idsFromArgs(Map<String, dynamic> a) {
    final raw = a['ids'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toSet();
    }
    return {...selectionBloc.state.selectedDrawingObjectIds};
  }

  static Color? _parseColor(dynamic v) {
    if (v == null) return null;
    if (v is int) return Color(v);
    if (v is! String) return null;
    var s = v.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.length == 6) s = 'FF$s'; // add opaque alpha
    if (s.length == 3) {
      // #RGB shorthand
      s = 'FF${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
    }
    final value = int.tryParse(s, radix: 16);
    return value == null ? null : Color(value);
  }

  static SelectionKind _kindFromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'node':
      case 'nodes':
        return SelectionKind.node;
      case 'edge':
      case 'edges':
      case 'arrow':
      case 'arrows':
        return s!.toLowerCase().startsWith('arrow')
            ? SelectionKind.arrow
            : SelectionKind.edge;
      case 'line':
      case 'lines':
        return SelectionKind.line;
      case 'rectangle':
      case 'rect':
        return SelectionKind.rectangle;
      case 'circle':
        return SelectionKind.circle;
      case 'diamond':
        return SelectionKind.diamond;
      case 'parallelogram':
        return SelectionKind.parallelogram;
      case 'forkjoin':
      case 'fork':
        return SelectionKind.forkJoin;
      case 'text':
        return SelectionKind.text;
      case 'frame':
      case 'figure':
        return SelectionKind.frame;
      default:
        return SelectionKind.any;
    }
  }

  static LineStyle? _lineStyleFromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'solid':
        return LineStyle.solid;
      case 'dashed':
      case 'dash':
        return LineStyle.dashed;
      case 'dotted':
      case 'dot':
        return LineStyle.dotted;
      case 'rough':
      case 'sketch':
        return LineStyle.rough;
      default:
        return null;
    }
  }

  static AlignmentType? _alignmentFromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'left':
        return AlignmentType.left;
      case 'centerh':
      case 'center-h':
      case 'horizontalcenter':
        return AlignmentType.centerH;
      case 'right':
        return AlignmentType.right;
      case 'top':
        return AlignmentType.top;
      case 'centerv':
      case 'center-v':
      case 'verticalcenter':
        return AlignmentType.centerV;
      case 'bottom':
        return AlignmentType.bottom;
      default:
        return null;
    }
  }

  static DistributionType? _distributionFromString(String? s) {
    switch (s?.toLowerCase()) {
      case 'horizontal':
      case 'h':
        return DistributionType.horizontal;
      case 'vertical':
      case 'v':
        return DistributionType.vertical;
      default:
        return null;
    }
  }

  static String _typeName(DrawingObject o) {
    if (o is RectangleObject) return 'rectangle';
    if (o is CircleObject) return 'circle';
    if (o is DiamondObject) return 'diamond';
    if (o is ParallelogramObject) return 'parallelogram';
    if (o is ForkJoinObject) return 'forkJoin';
    if (o is ArrowObject) return 'arrow';
    if (o is LineObject) return 'line';
    if (o is TextObject) return 'text';
    if (o is FigureObject) return 'frame';
    if (o is PencilStrokeObject) return 'drawing';
    return 'object';
  }
}
