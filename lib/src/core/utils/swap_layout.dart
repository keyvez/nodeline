import 'dart:ui';

/// Pure geometry for the "Swap" action. Kept separate from the data layer so it
/// can be unit-tested without standing up the editor widget.
class SwapLayout {
  /// Given exactly two boxes by id → world rect, returns new top-left offsets
  /// that place each box's centre where the other's centre was. Sizes are
  /// preserved. Returns an empty map unless exactly two rects are provided.
  static Map<String, Offset> swapBoxCentres(Map<String, Rect> rects) {
    if (rects.length != 2) return const {};
    final ids = rects.keys.toList();
    final a = ids[0];
    final b = ids[1];
    final ra = rects[a]!;
    final rb = rects[b]!;
    return {
      a: rb.center - Offset(ra.width / 2, ra.height / 2),
      b: ra.center - Offset(rb.width / 2, rb.height / 2),
    };
  }
}
