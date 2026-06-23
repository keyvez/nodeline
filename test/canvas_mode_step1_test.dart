import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodeline/src/blocs/canvas/canvas_bloc.dart';
import 'package:nodeline/src/blocs/selection/selection_resolver.dart';
import 'package:nodeline/src/models/drawing_entities.dart';
import 'package:nodeline/src/models/styles.dart';

/// Tests for Canvas Mode step 1: the selection resolver and the
/// ObjectsLineStyleChanged event. Both are pure model/bloc work, so they need
/// no LLM and no rendering — exactly why they go first.

RectangleObject _rect(String id, {String? text, Rect? rect}) => RectangleObject(
      id: id,
      rect: rect ?? const Rect.fromLTWH(0, 0, 100, 80),
      text: text,
    );

ArrowObject _arrow(String id, {String? label}) => ArrowObject(
      id: id,
      start: const Offset(0, 0),
      end: const Offset(100, 100),
      arrowLabel: label,
    );

void main() {
  group('SelectionResolver', () {
    test('empty query selects everything', () {
      final objects = <String, DrawingObject>{
        'r1': _rect('r1'),
        'a1': _arrow('a1'),
      };
      final result = SelectionResolver.resolve(objects, const SelectionQuery());
      expect(result, {'r1', 'a1'});
    });

    test('kind=edge selects only arrows and lines', () {
      final objects = <String, DrawingObject>{
        'r1': _rect('r1'),
        'a1': _arrow('a1'),
        'l1': LineObject(id: 'l1', start: Offset.zero, end: const Offset(10, 0)),
      };
      final result = SelectionResolver.resolve(
        objects,
        const SelectionQuery(kind: SelectionKind.edge),
      );
      expect(result, {'a1', 'l1'});
    });

    test('kind=node excludes edges and frames', () {
      final objects = <String, DrawingObject>{
        'r1': _rect('r1'),
        'c1': CircleObject(id: 'c1', rect: const Rect.fromLTWH(0, 0, 50, 50)),
        'a1': _arrow('a1'),
        'f1': FigureObject(id: 'f1', rect: const Rect.fromLTWH(0, 0, 500, 500)),
      };
      final result = SelectionResolver.resolve(
        objects,
        const SelectionQuery(kind: SelectionKind.node),
      );
      expect(result, {'r1', 'c1'});
    });

    test('labelContains matches case-insensitively on node text', () {
      final objects = <String, DrawingObject>{
        'joy': _rect('joy', text: 'Joy'),
        'anger': _rect('anger', text: 'Anger'),
      };
      final result = SelectionResolver.resolve(
        objects,
        const SelectionQuery(labelContains: 'joy'),
      );
      expect(result, {'joy'});
    });

    test('labelMatches uses regex on arrow labels', () {
      final objects = <String, DrawingObject>{
        'a1': _arrow('a1', label: 'Yes'),
        'a2': _arrow('a2', label: 'No'),
      };
      final result = SelectionResolver.resolve(
        objects,
        const SelectionQuery(labelMatches: r'^y', kind: SelectionKind.edge),
      );
      expect(result, {'a1'});
    });

    test('frame by label selects explicit childrenIds members', () {
      final objects = <String, DrawingObject>{
        'frame': FigureObject(
          id: 'frame',
          rect: const Rect.fromLTWH(0, 0, 1000, 1000),
          label: 'Emotions',
          childrenIds: const {'joy', 'anger'},
        ),
        'joy': _rect('joy', text: 'Joy', rect: const Rect.fromLTWH(10, 10, 50, 50)),
        'anger': _rect('anger', text: 'Anger', rect: const Rect.fromLTWH(70, 10, 50, 50)),
        'outside': _rect('outside', rect: const Rect.fromLTWH(5000, 5000, 50, 50)),
      };
      final result = SelectionResolver.resolve(
        objects,
        const SelectionQuery(
          frameLabel: 'emotions',
          // disable spatial fallback to test pure membership
          spatialFallback: false,
        ),
      );
      expect(result, {'joy', 'anger'});
    });

    test('frame spatial fallback includes objects inside the rect but not in childrenIds', () {
      final objects = <String, DrawingObject>{
        'frame': FigureObject(
          id: 'frame',
          rect: const Rect.fromLTWH(0, 0, 200, 200),
          label: 'Emotions',
          childrenIds: const {}, // membership not recorded (e.g. after a move)
        ),
        'inside': _rect('inside', rect: const Rect.fromLTWH(10, 10, 50, 50)),
        'outside': _rect('outside', rect: const Rect.fromLTWH(500, 500, 50, 50)),
      };
      final result = SelectionResolver.resolve(
        objects,
        const SelectionQuery(frameLabel: 'Emotions'),
      );
      expect(result, {'inside'});
    });

    test('frame + kind filters members by type', () {
      final objects = <String, DrawingObject>{
        'frame': FigureObject(
          id: 'frame',
          rect: const Rect.fromLTWH(0, 0, 1000, 1000),
          label: 'Flow',
          childrenIds: const {'r1', 'a1'},
        ),
        'r1': _rect('r1', rect: const Rect.fromLTWH(10, 10, 50, 50)),
        'a1': _arrow('a1'),
      };
      final result = SelectionResolver.resolve(
        objects,
        const SelectionQuery(
          frameLabel: 'Flow',
          kind: SelectionKind.node,
          spatialFallback: false,
        ),
      );
      expect(result, {'r1'});
    });

    test('naming a nonexistent frame returns empty', () {
      final objects = <String, DrawingObject>{'r1': _rect('r1')};
      final result = SelectionResolver.resolve(
        objects,
        const SelectionQuery(frameLabel: 'Nope'),
      );
      expect(result, isEmpty);
    });
  });

  group('ObjectsLineStyleChanged', () {
    test('sets dashed style on selected shapes and edges only', () async {
      final bloc = CanvasBloc();
      addTearDown(bloc.close);

      bloc
        ..add(DrawingObjectAdded(_rect('r1')))
        ..add(DrawingObjectAdded(_arrow('a1')))
        ..add(DrawingObjectAdded(_rect('r2')));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const ObjectsLineStyleChanged({'r1', 'a1'}, LineStyle.dashed));
      await Future<void>.delayed(Duration.zero);

      final objs = bloc.state.drawingObjects;
      expect((objs['r1'] as RectangleObject).lineStyle, LineStyle.dashed);
      expect((objs['a1'] as ArrowObject).lineStyle, LineStyle.dashed);
      // Unselected object is untouched.
      expect((objs['r2'] as RectangleObject).lineStyle, LineStyle.solid);
    });

    test('is undoable as a single step', () async {
      final bloc = CanvasBloc();
      addTearDown(bloc.close);

      bloc.add(DrawingObjectAdded(_rect('r1')));
      await Future<void>.delayed(Duration.zero);

      bloc.add(const ObjectsLineStyleChanged({'r1'}, LineStyle.dotted));
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state.drawingObjects['r1'] as RectangleObject).lineStyle,
          LineStyle.dotted);

      bloc.add(UndoRequested());
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state.drawingObjects['r1'] as RectangleObject).lineStyle,
          LineStyle.solid);
    });

    test('ignores ids that do not exist', () async {
      final bloc = CanvasBloc();
      addTearDown(bloc.close);

      bloc.add(DrawingObjectAdded(_rect('r1')));
      await Future<void>.delayed(Duration.zero);

      // Should not throw.
      bloc.add(const ObjectsLineStyleChanged({'ghost'}, LineStyle.dashed));
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state.drawingObjects['r1'] as RectangleObject).lineStyle,
          LineStyle.solid);
    });
  });
}
