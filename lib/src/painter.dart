import 'package:flutter/widgets.dart';

import 'model.dart';

/// Paints the paper background, every committed item, and the in-progress draft.
class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.board,
    required this.camera,
    this.draft,
    this.background = PaperColors.page,
  });

  final Board board;
  final Camera camera;
  final Item? draft;
  final Color background;

  static const double _step = 32.0;
  static const double _lineStep = 64.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    switch (board.paper) {
      case PaperStyle.blank:
        break;
      case PaperStyle.dots:
        _dots(canvas, size);
      case PaperStyle.grid:
        _grid(canvas, size);
      case PaperStyle.lines:
        _lines(canvas, size);
    }

    canvas.translate(camera.x, camera.y);
    canvas.scale(camera.scale, camera.scale);
    for (final item in board.items) {
      item.paint(canvas, camera.scale);
    }
    draft?.paint(canvas, camera.scale);
    canvas.restore();
  }

  /// Paper rhythm follows the zoom, so zooming out never turns it into moire.
  double stepFor(double base) {
    var s = camera.scale;
    var step = base;
    // Keep world-space spacing, but halve the world step while zoomed far out
    // so the page keeps a readable density.
    while (s < 0.5) {
      s *= 2;
      step /= 2;
    }
    while (s > 2) {
      s /= 2;
      step *= 2;
    }
    return step;
  }

  void _dots(Canvas canvas, Size size) {
    final step = stepFor(_step) * camera.scale;
    if (step < 6) return;
    final paint = Paint()..color = PaperColors.dot;
    final ox = camera.x % step;
    final oy = camera.y % step;
    for (double y = oy - step; y < size.height + step; y += step) {
      for (double x = ox - step; x < size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  void _grid(Canvas canvas, Size size) {
    final step = stepFor(_step) * camera.scale;
    if (step < 6) return;
    final paint = Paint()
      ..color = PaperColors.grid
      ..strokeWidth = 1;
    final ox = camera.x % step;
    final oy = camera.y % step;
    for (double y = oy - step; y < size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (double x = ox - step; x < size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _lines(Canvas canvas, Size size) {
    final step = stepFor(_lineStep) * camera.scale;
    if (step < 6) return;
    final paint = Paint()
      ..color = PaperColors.grid
      ..strokeWidth = 1;
    final oy = camera.y % step;
    for (double y = oy - step; y < size.height + step; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) =>
      oldDelegate.board.items.length != board.items.length ||
      oldDelegate.draft != draft ||
      oldDelegate.camera.x != camera.x ||
      oldDelegate.camera.y != camera.y ||
      oldDelegate.camera.scale != camera.scale ||
      oldDelegate.board.paper != board.paper ||
      oldDelegate.background != background;
}

class PaperColors {
  static const Color page = Color(0xFFFAFAFA);
  static const Color dot = Color(0x33000000);
  static const Color grid = Color(0x1A000000);
}
