import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'model.dart';

/// Paints the paper background and every *committed* item.
///
/// Kept as its own layer so that live drawing (see [DraftPainter]) repaints a
/// single stroke instead of replaying the whole board each frame.
class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.board,
    required this.camera,
    required this.viewport,
    required this.version,
    this.background = PaperColors.page,
  });

  final Board board;
  final Camera camera;
  final Size viewport;
  final Color background;

  /// Bumped by the owner whenever the item list mutates in a way that
  /// `items.length` cannot see (undo replacing one snapshot with another of
  /// the same size, a custom colour change, ...). Comparing it is what makes
  /// undo / redo / clear repaint immediately.
  final int version;

  static const double _step = 32.0;
  static const double _lineStep = 64.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final step = stepFor(_paperStep(board.paper));
    if (board.paper != PaperStyle.blank) {
      _drawPaper(canvas, size, step);
    }

    // Culling: world-space window that can actually be visible.
    final tl = camera.toWorld(Offset.zero);
    final br = camera.toWorld(size.bottomRight(Offset.zero));
    final visible = Rect.fromLTRB(tl.dx, tl.dy, br.dx, br.dy).inflate(2);

    canvas.translate(camera.x, camera.y);
    canvas.scale(camera.scale, camera.scale);
    for (final item in board.items) {
      if (!item.bounds.inflate(item.size).overlaps(visible)) continue;
      item.paint(canvas, camera.scale);
    }
    canvas.restore();
  }

  double _paperStep(PaperStyle paper) =>
      paper == PaperStyle.lines ? _lineStep : _step;

  /// Blits the cached pattern picture, offsetting it so it appears anchored
  /// to the paper rather than to the screen while panning.
  void _drawPaper(Canvas canvas, Size size, double step) {
    final picture = PaperPattern.pictureFor(board.paper, step, size);
    final ox = _posMod(camera.x, step);
    final oy = _posMod(camera.y, step);
    canvas.save();
    canvas.translate(ox - step, oy - step);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  static double _posMod(double a, double b) => ((a % b) + b) % b;

  /// Zoom-aware world spacing: the pattern keeps a readable density instead of
  /// collapsing into moire when zoomed far out.
  double stepFor(double base) {
    var s = camera.scale;
    var step = base;
    while (s < 0.5) {
      s *= 2;
      step /= 2;
    }
    while (s > 2) {
      s /= 2;
      step *= 2;
    }
    return step * camera.scale;
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) =>
      oldDelegate.version != version ||
      oldDelegate.board.paper != board.paper ||
      oldDelegate.background != background ||
      oldDelegate.viewport != viewport ||
      oldDelegate.camera.x != camera.x ||
      oldDelegate.camera.y != camera.y ||
      oldDelegate.camera.scale != camera.scale;
}

/// Records one period of the paper grid into a reusable [ui.Picture].
///
/// Drawing thousands of individual circles/lines every frame was the single
/// biggest cost while gesture-zooming on a phone; a recorded picture turns
/// that into one `canvas.drawPicture` call. Recording is synchronous, unlike
/// `Picture.toImage`.
class PaperPattern {
  PaperPattern._();

  static ui.Picture? _picture;
  static String _key = '';

  static ui.Picture pictureFor(PaperStyle paper, double step, Size size) {
    final key = '${paper.name}|${step.toStringAsFixed(3)}|'
        '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';
    final cached = _picture;
    if (cached != null && _key == key) return cached;
    final picture = _record(paper, step, size);
    _picture = picture;
    _key = key;
    return picture;
  }

  static ui.Picture _record(PaperStyle paper, double step, Size size) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // One spare row/column on every side so the offset blit never shows a gap.
    final w = size.width + step * 2;
    final h = size.height + step * 2;
    switch (paper) {
      case PaperStyle.blank:
        break;
      case PaperStyle.dots:
        _paintDots(canvas, w, h, step);
      case PaperStyle.grid:
        _paintGrid(canvas, w, h, step);
      case PaperStyle.lines:
        _paintLines(canvas, w, h, step);
    }
    return recorder.endRecording();
  }

  static void _paintDots(Canvas canvas, double w, double h, double step) {
    if (step < 6) return;
    final paint = Paint()
      ..color = PaperColors.dot
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;
    final points = <Offset>[];
    for (double y = 0; y < h; y += step) {
      for (double x = 0; x < w; x += step) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  static void _paintGrid(Canvas canvas, double w, double h, double step) {
    if (step < 6) return;
    final paint = Paint()
      ..color = PaperColors.grid
      ..strokeWidth = 1;
    final path = Path();
    for (double y = 0; y < h; y += step) {
      path
        ..moveTo(0, y)
        ..lineTo(w, y);
    }
    for (double x = 0; x < w; x += step) {
      path
        ..moveTo(x, 0)
        ..lineTo(x, h);
    }
    canvas.drawPath(path, paint);
  }

  static void _paintLines(Canvas canvas, double w, double h, double step) {
    if (step < 6) return;
    final paint = Paint()
      ..color = PaperColors.grid
      ..strokeWidth = 1;
    final path = Path();
    for (double y = 0; y < h; y += step) {
      path
        ..moveTo(0, y)
        ..lineTo(w, y);
    }
    canvas.drawPath(path, paint);
  }
}

/// The in-progress stroke/shape plus the tool cursor. Cheap to repaint, so it
/// sits in its own layer above the static board.
class DraftPainter extends CustomPainter {
  DraftPainter({
    required this.camera,
    this.draft,
    this.cursor,
    this.cursorSize = 0,
    this.version = 0,
  });

  final Camera camera;
  final Item? draft;
  final Offset? cursor;
  final double cursorSize;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(camera.x, camera.y);
    canvas.scale(camera.scale, camera.scale);
    draft?.paint(canvas, camera.scale);
    canvas.restore();

    final at = cursor;
    if (at != null && cursorSize > 0) {
      final r = cursorSize * 1.35;
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = const Color(0x33212121)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DraftPainter oldDelegate) =>
      oldDelegate.version != version || oldDelegate.camera != camera;
}

class PaperColors {
  static const Color page = Color(0xFFFAFAFA);
  static const Color dot = Color(0x33000000);
  static const Color grid = Color(0x1A000000);
}

extension on PaperStyle {
  String get name => switch (this) {
        PaperStyle.blank => 'blank',
        PaperStyle.dots => 'dots',
        PaperStyle.grid => 'grid',
        PaperStyle.lines => 'lines',
      };
}
