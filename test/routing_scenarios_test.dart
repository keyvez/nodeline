import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'routing_test_helpers.dart';

void main() {
  group('routing scenarios', () {
    test('right-to-left side-by-side produces clean path', () {
      final fixture = RoutingFixture(
        name: 'right-to-left-side-by-side',
        sourceRect: const Rect.fromLTWH(200, 160, 100, 80),
        targetRect: const Rect.fromLTWH(420, 160, 100, 80),
        startRelPos: const Offset(1.0, 0.5),
        endRelPos: const Offset(0.0, 0.5),
      );
      final path = fixture.route();
      verifyAxisAligned(path);
      expectAvoidsRects(path, [fixture.sourceRect, fixture.targetRect]);
    });

    test('bottom-exit side-by-side produces valid path', () {
      final fixture = RoutingFixture(
        name: 'bottom-exit-side-by-side',
        sourceRect: const Rect.fromLTWH(200, 160, 100, 80),
        targetRect: const Rect.fromLTWH(420, 160, 100, 80),
        startRelPos: const Offset(0.5, 1.0),
        endRelPos: const Offset(0.0, 0.5),
      );
      final path = fixture.route();
      verifyAxisAligned(path);
      expectExitsFromEdge(path, fixture.sourceRect, 'bottom');
    });

    test('vertically stacked right-to-left', () {
      final fixture = RoutingFixture(
        name: 'vertical-stack-right-to-left',
        sourceRect: const Rect.fromLTWH(100, 50, 180, 100),
        targetRect: const Rect.fromLTWH(100, 250, 180, 100),
        startRelPos: const Offset(0.5, 1.0),
        endRelPos: const Offset(0.5, 0.0),
      );
      final path = fixture.route();
      verifyAxisAligned(path);
      expectMaxSegments(path, 5);
    });

    test('left-edge exit with right target wraps around source', () {
      final fixture = RoutingFixture(
        name: 'left-exit-right-target',
        sourceRect: const Rect.fromLTWH(200, 160, 100, 80),
        targetRect: const Rect.fromLTWH(420, 160, 100, 80),
        startRelPos: const Offset(0.0, 0.5),
        endRelPos: const Offset(0.0, 0.5),
      );
      final path = fixture.route();
      verifyAxisAligned(path);
      // Should have waypoints — a U-turn around source
      expect(path.length, greaterThan(2));
    });

    test('diagonal offset boxes avoid both objects', () {
      final fixture = RoutingFixture(
        name: 'diagonal-offset',
        sourceRect: const Rect.fromLTWH(100, 50, 180, 150),
        targetRect: const Rect.fromLTWH(150, 180, 160, 130),
        startRelPos: const Offset(0.0, 1.0),
        endRelPos: const Offset(0.0, 0.5),
      );
      final path = fixture.route();
      verifyAxisAligned(path);
      expectAvoidsRects(path, [fixture.targetRect]);
    });
  });

  // -----------------------------------------------------------------------
  // Captured from saved drawings (extracted via tool/extract_routing_fixture)
  // -----------------------------------------------------------------------
  group('captured scenarios', () {
    // Scene: two side-by-side rectangles connected right→left with two
    // additional rectangles below acting as obstacles.
    test('horizontal connection with obstacles below', () {
      final fixture = RoutingFixture(
        name: 'captured-horizontal-with-obstacles',
        sourceRect: const Rect.fromLTWH(-611.890625, -304.9609375, 232.49609375, 155.4609375),
        targetRect: const Rect.fromLTWH(-318.00625, -308.484375, 232.49609375, 155.4609375),
        startRelPos: const Offset(1.0, 0.5),
        endRelPos: const Offset(0.0, 0.5),
        obstacles: [
          Rect.fromLTWH(-590.98046875, -33.0078125, 214.578125, 141.30078125),
          Rect.fromLTWH(-318.4921875, -31.2734375, 234.69140625, 143.03515625),
        ],
      );
      final path = fixture.route();
      print('Captured path: $path');
      print('Segments: ${path.length - 1}');
      verifyAxisAligned(path);
      expectAvoidsRects(path, [fixture.sourceRect, fixture.targetRect]);
      // Two nearly-aligned adjacent boxes: should be a direct horizontal
      // connection (at most 3 segments: exit stub, horizontal, entry stub)
      expectMaxSegments(path, 3);
      // Exit should go right from source's right edge
      expectExitsFromEdge(path, fixture.sourceRect, 'right');
    });

    // Same as above but with slightly increased gap between boxes.
    // Tests various gap sizes to ensure clean paths.
    // Exact geometry from the current saved drawing (target moved right)
    test('horizontal connection exact app geometry', () {
      final fixture = RoutingFixture(
        name: 'captured-horizontal-exact',
        sourceRect: const Rect.fromLTWH(-611.890625, -304.9609375, 232.49609375, 155.4609375),
        targetRect: const Rect.fromLTWH(-305.9359375, -304.65625, 232.49609375, 155.4609375),
        startRelPos: const Offset(1.0, 0.5),
        endRelPos: const Offset(0.0, 0.5),
        obstacles: [
          Rect.fromLTWH(-590.98046875, -33.0078125, 214.578125, 141.30078125),
          Rect.fromLTWH(-318.4921875, -31.2734375, 234.69140625, 143.03515625),
        ],
      );
      final path = fixture.route();
      print('Exact app path: $path');
      print('Exact app segments: ${path.length - 1}');
      verifyAxisAligned(path);
      expectMaxSegments(path, 3);
      expectExitsFromEdge(path, fixture.sourceRect, 'right');
      expectNoUTurn(path);
    });

    for (final gapExtra in [10, 15, 18, 20, 30, 40, 80]) {
      test('horizontal connection with +${gapExtra}px gap', () {
        final fixture = RoutingFixture(
          name: 'captured-horizontal-gap-$gapExtra',
          sourceRect: const Rect.fromLTWH(-611.890625, -304.9609375, 232.49609375, 155.4609375),
          targetRect: Rect.fromLTWH(-318.00625 + gapExtra, -308.484375, 232.49609375, 155.4609375),
          startRelPos: const Offset(1.0, 0.5),
          endRelPos: const Offset(0.0, 0.5),
          obstacles: [
            Rect.fromLTWH(-590.98046875, -33.0078125, 214.578125, 141.30078125),
            Rect.fromLTWH(-318.4921875, -31.2734375, 234.69140625, 143.03515625),
          ],
        );
        final path = fixture.route();
        print('Gap +$gapExtra path: $path');
        print('Gap +$gapExtra segments: ${path.length - 1}');
        verifyAxisAligned(path);
        // Close gaps should produce ≤3 segments; larger gaps allow 4
        // (clean L-corner without fold-backs)
        expectMaxSegments(path, 4);
        expectExitsFromEdge(path, fixture.sourceRect, 'right');
        // Should never have fold-backs / U-turns
        expectNoUTurn(path);
      });
    }
  });
}
