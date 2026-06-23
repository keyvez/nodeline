import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:nodeline/src/blocs/canvas/canvas_bloc.dart';
import 'package:nodeline/src/models/drawing_entities.dart';

/// A small toggleable HUD badge that shows the live count of edge crossings
/// (arrow-vs-arrow segment intersections) in the current diagram. Useful for
/// watching the count drop while running Tidy or hand-tuning connections.
class CrossingCounter extends StatefulWidget {
  const CrossingCounter({super.key});

  @override
  State<CrossingCounter> createState() => _CrossingCounterState();
}

class _CrossingCounterState extends State<CrossingCounter> {
  bool _enabled = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 80,
      right: 12,
      child: GestureDetector(
        onTap: () => setState(() => _enabled = !_enabled),
        behavior: HitTestBehavior.opaque,
        child: BlocBuilder<CanvasBloc, CanvasState>(
          // Recompute whenever objects change (also fires on viewport changes,
          // which is fine — crossings are viewport-independent and cheap here).
          buildWhen: (a, b) =>
              _enabled &&
              (a.drawingObjects != b.drawingObjects ||
                  a.nodes != b.nodes),
          builder: (context, state) {
            final count = _enabled ? _countCrossings(state) : 0;
            final color = !_enabled
                ? const Color(0x99000000)
                : count == 0
                    ? const Color(0xCC047857) // green when crossing-free
                    : const Color(0xCC1D4ED8);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _enabled
                      ? const Color(0xFF60A5FA)
                      : const Color(0x33FFFFFF),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _enabled ? Icons.call_split : Icons.call_split_outlined,
                    size: 13,
                    color: const Color(0xFFE5E7EB),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _enabled ? 'Crossings: $count' : 'Crossings',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFE5E7EB),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Polyline for an arrow: the path actually drawn (renderedPath) when present,
  /// else a straight start→waypoints→end fallback.
  List<Offset> _poly(ArrowObject a) {
    final r = a.renderedPath;
    if (r != null && r.length >= 2) return r;
    return [a.start, ...?a.waypoints, a.end];
  }

  int _countCrossings(CanvasState state) {
    final polys = state.drawingObjects.values
        .whereType<ArrowObject>()
        .map(_poly)
        .where((p) => p.length >= 2)
        .toList();
    int total = 0;
    for (var i = 0; i < polys.length; i++) {
      for (var j = i + 1; j < polys.length; j++) {
        final a = polys[i], b = polys[j];
        for (var x = 0; x < a.length - 1; x++) {
          for (var y = 0; y < b.length - 1; y++) {
            if (_segCross(a[x], a[x + 1], b[y], b[y + 1])) total++;
          }
        }
      }
    }
    return total;
  }

  bool _segCross(Offset p1, Offset p2, Offset p3, Offset p4) {
    final d1 = p2 - p1, d2 = p4 - p3;
    final cross = d1.dx * d2.dy - d1.dy * d2.dx;
    if (cross.abs() < 1e-10) return false;
    final t = ((p3.dx - p1.dx) * d2.dy - (p3.dy - p1.dy) * d2.dx) / cross;
    final u = ((p3.dx - p1.dx) * d1.dy - (p3.dy - p1.dy) * d1.dx) / cross;
    return t > 0.01 && t < 0.99 && u > 0.01 && u < 0.99;
  }
}
