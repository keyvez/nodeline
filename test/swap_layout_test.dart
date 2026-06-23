import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/core/utils/swap_layout.dart';

void main() {
  group('SwapLayout.swapBoxCentres', () {
    test('swaps centres of two equal-size boxes', () {
      final rects = {
        'a': const Rect.fromLTWH(0, 0, 100, 100), // centre (50,50)
        'b': const Rect.fromLTWH(300, 300, 100, 100), // centre (350,350)
      };
      final offsets = SwapLayout.swapBoxCentres(rects);
      // a moves so its centre lands on b's old centre (350,350) → TL (300,300).
      expect(offsets['a'], const Offset(300, 300));
      // b moves so its centre lands on a's old centre (50,50) → TL (0,0).
      expect(offsets['b'], const Offset(0, 0));
    });

    test('preserves each box size when sizes differ (centres swap, not TLs)',
        () {
      final rects = {
        'small': const Rect.fromLTWH(0, 0, 40, 40), // centre (20,20)
        'big': const Rect.fromLTWH(200, 100, 200, 100), // centre (300,150)
      };
      final offsets = SwapLayout.swapBoxCentres(rects);
      // small's new centre = big's old centre (300,150); small is 40x40 →
      // TL (280,130).
      expect(offsets['small'], const Offset(280, 130));
      // big's new centre = small's old centre (20,20); big is 200x100 →
      // TL (-80,-30).
      expect(offsets['big'], const Offset(-80, -30));

      // Sanity: applying the offsets really lands each centre on the other's.
      final newSmallCentre = offsets['small']! + const Offset(20, 20);
      final newBigCentre = offsets['big']! + const Offset(100, 50);
      expect(newSmallCentre, const Offset(300, 150));
      expect(newBigCentre, const Offset(20, 20));
    });

    test('swapping is an involution: applying it twice restores positions', () {
      final rects = {
        'a': const Rect.fromLTWH(10, 10, 60, 30),
        'b': const Rect.fromLTWH(500, 200, 80, 80),
      };
      final once = SwapLayout.swapBoxCentres(rects);
      final rectsAfter = {
        'a': Rect.fromLTWH(once['a']!.dx, once['a']!.dy, 60, 30),
        'b': Rect.fromLTWH(once['b']!.dx, once['b']!.dy, 80, 80),
      };
      final twice = SwapLayout.swapBoxCentres(rectsAfter);
      expect(twice['a']!.dx, closeTo(10, 1e-9));
      expect(twice['a']!.dy, closeTo(10, 1e-9));
      expect(twice['b']!.dx, closeTo(500, 1e-9));
      expect(twice['b']!.dy, closeTo(200, 1e-9));
    });

    test('returns empty unless exactly two boxes', () {
      expect(SwapLayout.swapBoxCentres({}), isEmpty);
      expect(
          SwapLayout.swapBoxCentres(
              {'a': const Rect.fromLTWH(0, 0, 10, 10)}),
          isEmpty);
      expect(
          SwapLayout.swapBoxCentres({
            'a': const Rect.fromLTWH(0, 0, 10, 10),
            'b': const Rect.fromLTWH(20, 20, 10, 10),
            'c': const Rect.fromLTWH(40, 40, 10, 10),
          }),
          isEmpty);
    });
  });
}
