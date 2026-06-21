import 'dart:ui';

import 'package:flow_draw/src/models/drawing_entities.dart';

/// The kind of object a [SelectionQuery] matches against.
///
/// [node] means "a content shape" — anything that can hold a label and act as a
/// box in the diagram (rectangle, circle, diamond, parallelogram, fork/join).
/// [edge] means a connector (arrow or line). The remaining values target a
/// single concrete type. [any] disables type filtering.
enum SelectionKind {
  any,
  node,
  edge,
  rectangle,
  circle,
  diamond,
  parallelogram,
  forkJoin,
  arrow,
  line,
  text,
  frame,
}

/// A declarative description of "which objects to select", resolved against the
/// current canvas by [SelectionResolver]. This is the structured form the
/// agent's `select` tool produces and the manual UI can reuse.
///
/// All provided constraints are ANDed together. A query with no constraints
/// (the default) matches every object — equivalent to "select all".
class SelectionQuery {
  /// Restrict to a single frame ([FigureObject]) by its label (case-insensitive,
  /// substring match). Members are taken from the frame's explicit
  /// [FigureObject.childrenIds]; when [spatialFallback] is true, objects whose
  /// bounds are (mostly) inside the frame rect are also included so the result
  /// stays correct after manual moves that didn't update membership.
  final String? frameLabel;

  /// Restrict to a single frame by id (takes precedence over [frameLabel]).
  final String? frameId;

  /// Restrict to a kind/type of object.
  final SelectionKind kind;

  /// Restrict to objects whose label/text matches this (case-insensitive,
  /// substring) — e.g. "joy" to find the emotion node.
  final String? labelContains;

  /// Restrict to objects whose label/text matches this regular expression.
  final String? labelMatches;

  /// When true (default) and a frame is named, also include objects spatially
  /// inside the frame even if not listed in its [FigureObject.childrenIds].
  final bool spatialFallback;

  const SelectionQuery({
    this.frameLabel,
    this.frameId,
    this.kind = SelectionKind.any,
    this.labelContains,
    this.labelMatches,
    this.spatialFallback = true,
  });
}

/// Resolves a [SelectionQuery] into a concrete set of drawing-object ids against
/// a snapshot of the canvas's `drawingObjects` map.
///
/// Pure and side-effect free so it is fully unit-testable without a BLoC or any
/// LLM. The agent's `select` tool calls [resolve] and feeds the result to
/// `SelectionReplaced`.
class SelectionResolver {
  /// Fraction of an object's area that must lie within a frame's rect for the
  /// spatial fallback to consider it a member.
  static const double _spatialCoverageThreshold = 0.6;

  /// Returns the ids of every drawing object matching [query].
  static Set<String> resolve(
    Map<String, DrawingObject> drawingObjects,
    SelectionQuery query,
  ) {
    // 1. Establish the candidate pool — either a frame's members or everything.
    Iterable<DrawingObject> candidates = drawingObjects.values;

    final frame = _findFrame(drawingObjects, query);
    if (query.frameId != null || query.frameLabel != null) {
      if (frame == null) return const {}; // named a frame that doesn't exist
      candidates = _membersOf(frame, drawingObjects, query.spatialFallback);
    }

    // 2. Apply type + label constraints.
    final labelRe =
        query.labelMatches != null ? RegExp(query.labelMatches!, caseSensitive: false) : null;
    final labelSub = query.labelContains?.toLowerCase();

    final result = <String>{};
    for (final obj in candidates) {
      if (obj is FigureObject && query.kind != SelectionKind.frame) {
        // Frames are containers; don't fold them into a member selection unless
        // explicitly asked for frames.
        continue;
      }
      if (!_matchesKind(obj, query.kind)) continue;

      if (labelSub != null || labelRe != null) {
        final label = labelOf(obj)?.toLowerCase();
        if (label == null) continue;
        if (labelSub != null && !label.contains(labelSub)) continue;
        if (labelRe != null && !labelRe.hasMatch(label)) continue;
      }
      result.add(obj.id);
    }
    return result;
  }

  /// The frame referenced by the query, if any (by id first, then by label).
  static FigureObject? _findFrame(
    Map<String, DrawingObject> drawingObjects,
    SelectionQuery query,
  ) {
    if (query.frameId != null) {
      final o = drawingObjects[query.frameId];
      return o is FigureObject ? o : null;
    }
    if (query.frameLabel != null) {
      final needle = query.frameLabel!.toLowerCase();
      for (final o in drawingObjects.values) {
        if (o is FigureObject && o.label.toLowerCase().contains(needle)) {
          return o;
        }
      }
    }
    return null;
  }

  /// The members of [frame]: its explicit [FigureObject.childrenIds], plus —
  /// when [spatialFallback] is set — any object whose bounds are mostly inside
  /// the frame rect (so the result survives moves that didn't update membership).
  static List<DrawingObject> _membersOf(
    FigureObject frame,
    Map<String, DrawingObject> drawingObjects,
    bool spatialFallback,
  ) {
    final ids = <String>{...frame.childrenIds};
    if (spatialFallback) {
      for (final o in drawingObjects.values) {
        if (o.id == frame.id) continue;
        if (o is FigureObject) continue;
        if (_mostlyInside(o.rect, frame.rect)) ids.add(o.id);
      }
    }
    return [
      for (final id in ids)
        if (drawingObjects[id] != null && drawingObjects[id]!.id != frame.id)
          drawingObjects[id]!,
    ];
  }

  /// Whether [inner]'s area is at least [_spatialCoverageThreshold] contained in
  /// [outer].
  static bool _mostlyInside(Rect inner, Rect outer) {
    final overlap = inner.intersect(outer);
    if (overlap.isEmpty || overlap.width <= 0 || overlap.height <= 0) {
      return false;
    }
    final innerArea = inner.width * inner.height;
    if (innerArea <= 0) return false;
    final overlapArea = overlap.width * overlap.height;
    return overlapArea / innerArea >= _spatialCoverageThreshold;
  }

  static bool _matchesKind(DrawingObject obj, SelectionKind kind) {
    switch (kind) {
      case SelectionKind.any:
        return true;
      case SelectionKind.node:
        return obj is RectangleObject ||
            obj is CircleObject ||
            obj is DiamondObject ||
            obj is ParallelogramObject ||
            obj is ForkJoinObject;
      case SelectionKind.edge:
        return obj is ArrowObject || obj is LineObject;
      case SelectionKind.rectangle:
        return obj is RectangleObject;
      case SelectionKind.circle:
        return obj is CircleObject;
      case SelectionKind.diamond:
        return obj is DiamondObject;
      case SelectionKind.parallelogram:
        return obj is ParallelogramObject;
      case SelectionKind.forkJoin:
        return obj is ForkJoinObject;
      case SelectionKind.arrow:
        return obj is ArrowObject;
      case SelectionKind.line:
        return obj is LineObject;
      case SelectionKind.text:
        return obj is TextObject;
      case SelectionKind.frame:
        return obj is FigureObject;
    }
  }

  /// The human-readable label/text of an object, if it has one.
  static String? labelOf(DrawingObject obj) {
    if (obj is RectangleObject) return obj.text;
    if (obj is CircleObject) return obj.text;
    if (obj is DiamondObject) return obj.text;
    if (obj is ParallelogramObject) return obj.text;
    if (obj is ArrowObject) return obj.arrowLabel;
    if (obj is TextObject) return obj.text;
    if (obj is FigureObject) return obj.label;
    return null;
  }
}
