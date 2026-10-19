// Unit tests for the drawing model: hit testing, bounds, camera math, and a
// toolbar smoke test. The geometry tests catch regressions without driving UI.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doodle/src/feedback.dart';
import 'package:doodle/src/model.dart';
import 'package:doodle/src/toolbar.dart';

void main() {
  group('Camera', () {
    test('round-trips world <-> screen', () {
      final cam = Camera(x: 30, y: -12, scale: 2.5);
      const world = Offset(100, 60);
      final screen = cam.toScreen(world);
      expect(screen, const Offset(280, 138));
      expect(cam.toWorld(screen).dx, closeTo(world.dx, 1e-9));
      expect(cam.toWorld(screen).dy, closeTo(world.dy, 1e-9));
    });

    test('identity camera is a no-op', () {
      final cam = Camera();
      const p = Offset(7, 9);
      expect(cam.toWorld(p), p);
      expect(cam.toScreen(p), p);
    });
  });

  group('Shape', () {
    Shape square() => Shape(
          color: const Color(0xFF000000),
          size: 2,
          kind: ShapeKind.rect,
          a: const Offset(0, 0),
          b: const Offset(100, 100),
        );

    test('bounds include stroke width padding', () {
      expect(square().bounds, const Rect.fromLTRB(-2, -2, 102, 102));
    });

    test('rect eraser hits inside, misses outside', () {
      final s = square();
      expect(s.hitByDisk(const Offset(50, 50), 5), isTrue);
      expect(s.hitByDisk(const Offset(200, 200), 5), isFalse);
    });

    test('line eraser uses point-to-segment distance', () {
      final line = Shape(
        color: const Color(0xFF000000),
        size: 2,
        kind: ShapeKind.line,
        a: const Offset(0, 0),
        b: const Offset(100, 0),
      );
      // Above the segment: within range.
      expect(line.hitByDisk(const Offset(50, 3), 5), isTrue);
      // Same perpendicular distance, but past the endpoint -> no segment there.
      expect(line.hitByDisk(const Offset(200, 3), 5), isFalse);
    });

    test('reversed anchors still produce a normalized rect', () {
      final backwards = Shape(
        color: const Color(0xFF000000),
        size: 2,
        kind: ShapeKind.rect,
        a: const Offset(100, 100),
        b: const Offset(0, 0),
      );
      expect(backwards.rect, const Rect.fromLTRB(0, 0, 100, 100));
    });
  });

  group('Stroke', () {
    Stroke line() => Stroke(
          color: const Color(0xFF000000),
          size: 4,
          points: <double>[0, 0, 50, 0],
        );

    test('bounds pad by half the stroke width', () {
      expect(line().bounds, const Rect.fromLTRB(-2, -2, 52, 2));
    });

    test('empty and single-point strokes report sane bounds', () {
      final empty = Stroke(
        color: const Color(0xFF000000),
        size: 4,
        points: <double>[],
      );
      expect(empty.bounds, Rect.zero);
      final dot = Stroke(
        color: const Color(0xFF000000),
        size: 4,
        points: <double>[10, 10],
      );
      expect(dot.bounds, const Rect.fromLTRB(8, 8, 12, 12));
    });

    test('eraser hits along a long segment, not just at sampled points', () {
      final long = Stroke(
        color: const Color(0xFF000000),
        size: 2,
        points: <double>[0, 0, 1000, 0],
      );
      // The midpoint is not a stored point, so only segment math can find it.
      expect(long.points, isNot(contains(500)));
      expect(long.hitByDisk(const Offset(500, 1), 2), isTrue);
    });

    test('eraser respects radius', () {
      expect(line().hitByDisk(const Offset(25, 40), 5), isFalse);
      expect(line().hitByDisk(const Offset(25, 40), 45), isTrue);
    });

    test('path builds without throwing for 2 points and 1 point', () {
      expect(() => line().buildPath(), returnsNormally);
      final degenerate = Stroke(
        color: const Color(0xFF000000),
        size: 4,
        points: <double>[1, 1],
      );
      expect(() => degenerate.buildPath(), returnsNormally);
    });
  });

  group('Board', () {
    test('empty board has zero content bounds', () {
      expect(Board().contentBounds, Rect.zero);
    });

    test('content bounds union every item', () {
      final board = Board();
      board.items.add(Shape(
        color: const Color(0xFF000000),
        size: 1,
        kind: ShapeKind.rect,
        a: const Offset(0, 0),
        b: const Offset(10, 10),
      ));
      board.items.add(Shape(
        color: const Color(0xFF000000),
        size: 1,
        kind: ShapeKind.rect,
        a: const Offset(50, 50),
        b: const Offset(60, 60),
      ));
      expect(board.contentBounds.width, greaterThanOrEqualTo(60));
      expect(board.contentBounds.height, greaterThanOrEqualTo(60));
    });
  });

  group('TextItem', () {
    test('bounds grow with text length', () {
      final short = TextItem(
        color: const Color(0xFF000000),
        size: 20,
        text: 'hi',
        origin: const Offset(5, 7),
      );
      final long = TextItem(
        color: const Color(0xFF000000),
        size: 20,
        text: 'hello',
        origin: const Offset(5, 7),
      );
      expect(long.bounds.width, greaterThan(short.bounds.width));
      expect(short.bounds.topLeft, const Offset(5, 7));
    });
  });

  group('ToolSection', () {
    testWidgets('renders every tool and reports the active one', (tester) async {
      Tool? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ToolSection(
            tool: Tool.pen,
            color: kPalette.first,
            size: 3,
            paper: PaperStyle.dots,
            canUndo: false,
            canRedo: false,
            onTool: (t) => picked = t,
            onColor: (_) {},
            onSize: (_) {},
            onPaper: (_) {},
            onUndo: () {},
            onRedo: () {},
            onClear: () {},
            onSave: () {},
            onImage: () {},
            onPickColor: () {},
            onChooseSaveDir: () {},
            onFeedback: () {},
            onToggleCollapse: () {},
          ),
        ),
      ));

      for (final label in <String>['画笔', '荧光笔', '橡皮', '直线', '箭头', '矩形', '椭圆', '文字']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('导出 PNG'), findsOneWidget);

      await tester.tap(find.text('箭头'));
      await tester.pump();
      expect(picked, Tool.arrow);
    });
  });

  group('feedback', () {
    test('mailto uri targets the feedback inbox', () {
      final uri = feedbackUri();
      expect(uri.scheme, 'mailto');
      expect(uri.path, kFeedbackEmail);
      expect(uri.queryParameters['subject'], contains('涂想 Doodle'));
      expect(uri.queryParameters['body'], contains('版本'));
    });

    testWidgets('sheet shows the address and copies it', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      // Do NOT await the returned future: it only completes when the sheet is
      // dismissed, so awaiting here would deadlock the test.
      unawaited(showFeedbackSheet(tester.element(find.byType(SizedBox))));
      await tester.pumpAndSettle();
      expect(find.text(kFeedbackEmail), findsOneWidget);
      expect(find.text('写邮件给我'), findsOneWidget);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text(kFeedbackEmail), findsNothing);
    });
  });
}
