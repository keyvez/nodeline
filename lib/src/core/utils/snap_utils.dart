import 'dart:ui';

const double kGridSize = 16.0;

Offset snapOffset(Offset o) => Offset(
      (o.dx / kGridSize).round() * kGridSize,
      (o.dy / kGridSize).round() * kGridSize,
    );

Rect snapRect(Rect r) {
  final snapped = snapOffset(r.topLeft);
  return Rect.fromLTWH(
    snapped.dx,
    snapped.dy,
    (r.width / kGridSize).round() * kGridSize,
    (r.height / kGridSize).round() * kGridSize,
  );
}
