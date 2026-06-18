import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lightweight per-frame profiler for the canvas render object.
///
/// The render object records the cost of its expensive sub-phases each
/// `paint()` via [recordPaint]; a live overlay ([FpsOverlay]) reads the
/// rolling averages and the real frame rate (from [SchedulerBinding]'s
/// frame timings) and paints them on top of the canvas.
///
/// All timings are in microseconds internally, surfaced as milliseconds.
class PaintProfiler {
  PaintProfiler._();
  static final PaintProfiler instance = PaintProfiler._();

  /// Set false to disable all instrumentation (zero overhead in paint()).
  static bool enabled = false;

  // Rolling window of the last [_window] paints for each phase.
  static const int _window = 60;
  final _total = _Ring(_window);
  final _routing = _Ring(_window);
  final _obstacles = _Ring(_window);
  final _grid = _Ring(_window);
  final _children = _Ring(_window);
  final _drawObj = _Ring(_window);
  int _arrowCount = 0;
  int _routeCalls = 0;
  // Instantaneous (last-frame) values — averages mislead after a one-shot
  // import frame decays through the rolling window.
  double lastTotalMs = 0;
  double lastDrawMs = 0;
  double lastRouteMs = 0;
  // Monotonic count of canvas paints. The overlay watches this: if it stops
  // advancing, the canvas RenderObject is genuinely idle (not repainting),
  // regardless of what the FPS line shows.
  int canvasPaintCount = 0;
  int lastCanvasPaintStampMs = 0;

  /// Notifies the overlay to rebuild after each recorded paint.
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Called once per `paint()` with the measured phase costs (microseconds).
  void recordPaint({
    required int totalUs,
    required int routingUs,
    required int obstaclesUs,
    required int arrowCount,
    required int routeCalls,
    int gridUs = 0,
    int childrenUs = 0,
    int drawObjUs = 0,
  }) {
    if (!enabled) return;
    _total.add(totalUs);
    _routing.add(routingUs);
    _obstacles.add(obstaclesUs);
    _grid.add(gridUs);
    _children.add(childrenUs);
    _drawObj.add(drawObjUs);
    _arrowCount = arrowCount;
    _routeCalls = routeCalls;
    lastTotalMs = totalUs / 1000.0;
    lastDrawMs = drawObjUs / 1000.0;
    lastRouteMs = routingUs / 1000.0;
    canvasPaintCount++;
    lastCanvasPaintStampMs = DateTime.now().millisecondsSinceEpoch;
    // We are inside paint(); mutating a ValueNotifier now would schedule a
    // build during the frame. Defer the overlay refresh to the next frame.
    if (!_notifyScheduled) {
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        tick.value++;
      });
    }
  }

  bool _notifyScheduled = false;

  double get avgTotalMs => _total.avg / 1000.0;
  double get avgRoutingMs => _routing.avg / 1000.0;
  double get avgObstaclesMs => _obstacles.avg / 1000.0;
  double get avgGridMs => _grid.avg / 1000.0;
  double get avgChildrenMs => _children.avg / 1000.0;
  double get avgDrawObjMs => _drawObj.avg / 1000.0;
  int get arrowCount => _arrowCount;
  int get routeCalls => _routeCalls;
}

class _Ring {
  _Ring(this.capacity) : _buf = List<int>.filled(capacity, 0);
  final int capacity;
  final List<int> _buf;
  int _len = 0;
  int _head = 0;

  void add(int v) {
    _buf[_head] = v;
    _head = (_head + 1) % capacity;
    if (_len < capacity) _len++;
  }

  double get avg {
    if (_len == 0) return 0;
    var sum = 0;
    for (var i = 0; i < _len; i++) {
      sum += _buf[i];
    }
    return sum / _len;
  }
}

/// Live FPS + paint-cost overlay. Add as a Stack child over the canvas.
///
/// FPS is derived from real frame timings reported by the engine, so it
/// reflects actual on-screen smoothness (build + layout + paint + raster),
/// not just the paint phase we instrument.
class FpsOverlay extends StatefulWidget {
  const FpsOverlay({super.key});

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay> {
  final List<double> _frameMs = [];
  double _fps = 0;
  int _lastFrameStampMs = 0; // engine clock of the most recent frame seen
  Timer? _refreshTimer;
  // Canvas-paint-rate tracking: sample canvasPaintCount each refresh tick to
  // derive paints/sec. This is the meaningful number — engine FPS is polluted
  // by this overlay's own 500ms refresh frames.
  int _lastSampledPaintCount = 0;
  int _lastSampleStampMs = 0;
  double _canvasFps = 0;
  bool _canvasIdle = true;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Refresh the readout on a low-frequency timer instead of every frame.
    // A Timer does NOT schedule render frames on its own, and setState here
    // only rebuilds this tiny overlay subtree (the canvas is a separate
    // RenderObject), so the app still goes fully idle when nothing moves —
    // while the number stays "live" enough to read.
    _refreshTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = PaintProfiler.instance;

    // Canvas paints/sec since the last sample — the honest "is it repainting"
    // number. If the canvas hasn't painted in >600ms, it is genuinely idle.
    final dPaints = p.canvasPaintCount - _lastSampledPaintCount;
    final dtMs = now - _lastSampleStampMs;
    if (dtMs > 0) {
      _canvasFps = dPaints * 1000.0 / dtMs;
    }
    _lastSampledPaintCount = p.canvasPaintCount;
    _lastSampleStampMs = now;
    _canvasIdle = (now - p.lastCanvasPaintStampMs) > 600;
    if (_canvasIdle) _canvasFps = 0;

    // Engine FPS (overlay-polluted) only meaningful while actively painting.
    final engineIdleMs = now - _lastFrameStampMs;
    final displayFps = engineIdleMs > 700 ? 0.0 : _fps;
    setState(() => _fps = displayFps);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!mounted) return;
    for (final t in timings) {
      // Total frame time = build/UI thread + raster thread.
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      _frameMs.add(ms);
    }
    while (_frameMs.length > 60) {
      _frameMs.removeAt(0);
    }
    _lastFrameStampMs = DateTime.now().millisecondsSinceEpoch;
    if (_frameMs.isEmpty) return;
    final avgMs = _frameMs.reduce((a, b) => a + b) / _frameMs.length;
    // IMPORTANT: do NOT setState() here. addTimingsCallback fires after every
    // frame; calling setState would mark this widget dirty and schedule the
    // next frame, creating a self-perpetuating repaint loop that pegs the app
    // at a constant framerate even when the canvas is idle. The 500ms timer
    // above does the (frame-free) display refresh.
    _fps = avgMs > 0 ? 1000.0 / avgMs : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 80,
      left: 12,
      child: IgnorePointer(
        child: ValueListenableBuilder<int>(
          valueListenable: PaintProfiler.instance.tick,
          builder: (context, _, __) {
            final p = PaintProfiler.instance;
            final headline = _canvasIdle
                ? 'IDLE (canvas not repainting)'
                : '${_canvasFps.toStringAsFixed(0)} canvas fps';
            final headColor = _canvasIdle
                ? const Color(0xFF60A5FA) // blue = good (truly idle)
                : _canvasFps >= 55
                    ? const Color(0xFF4ADE80)
                    : _canvasFps >= 30
                        ? const Color(0xFFFACC15)
                        : const Color(0xFFF87171);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xCC000000),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFFE5E7EB),
                  height: 1.4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        color: headColor,
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('paints  ${p.canvasPaintCount}'),
                    Text('paint   ${p.lastTotalMs.toStringAsFixed(2)} ms '
                        '(avg ${p.avgTotalMs.toStringAsFixed(1)})'),
                    Text('  draw  ${p.lastDrawMs.toStringAsFixed(2)} ms'),
                    Text('  route ${p.lastRouteMs.toStringAsFixed(2)} ms '
                        '(${p.routeCalls}×)'),
                    Text('engine  ${_fps.toStringAsFixed(0)} fps'),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
