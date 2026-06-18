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
  int _arrowCount = 0;
  int _routeCalls = 0;

  /// Notifies the overlay to rebuild after each recorded paint.
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Called once per `paint()` with the measured phase costs (microseconds).
  void recordPaint({
    required int totalUs,
    required int routingUs,
    required int obstaclesUs,
    required int arrowCount,
    required int routeCalls,
  }) {
    if (!enabled) return;
    _total.add(totalUs);
    _routing.add(routingUs);
    _obstacles.add(obstaclesUs);
    _arrowCount = arrowCount;
    _routeCalls = routeCalls;
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

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
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
    if (_frameMs.isEmpty) return;
    final avgMs = _frameMs.reduce((a, b) => a + b) / _frameMs.length;
    setState(() => _fps = avgMs > 0 ? 1000.0 / avgMs : 0);
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
            final fpsColor = _fps >= 55
                ? const Color(0xFF4ADE80)
                : _fps >= 30
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
                      '${_fps.toStringAsFixed(0)} fps',
                      style: TextStyle(
                        color: fpsColor,
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text('paint   ${p.avgTotalMs.toStringAsFixed(2)} ms'),
                    Text('  route ${p.avgRoutingMs.toStringAsFixed(2)} ms '
                        '(${p.routeCalls}×)'),
                    Text('  obst  ${p.avgObstaclesMs.toStringAsFixed(2)} ms'),
                    Text('arrows  ${p.arrowCount}'),
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
