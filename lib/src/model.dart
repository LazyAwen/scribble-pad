import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

enum Tool { pen, marker, eraser, line, arrow, rect, ellipse, text }

enum ShapeKind { line, arrow, rect, ellipse }

enum PaperStyle { blank, dots, grid, lines }

const List<Color> kPalette = <Color>[
  Color(0xFF1B1B1F),
  Color(0xFFE03131),
  Color(0xFF1971C2),
  Color(0xFF2F9E44),
  Color(0xFFF08C00),
  Color(0xFF9C36B5),
];

sealed class Item {
  Item({required this.color, required this.size});

  final Color color;
  final double size;

  /// Bounding box in world coordinates, used for export and the eraser.
  Rect get bounds;

  /// Eraser test: does the disk at [p] with radius [r] touch this item?
  bool hitByDisk(Offset p, double r);

  void paint(Canvas canvas, double scale);
}

class Stroke extends Item {
  Stroke({
    required super.color,
    required super.size,
    required this.points,
    this.alpha = 1.0,
    this.isMarker = false,
  });

  /// Flat list: [x0, y0, x1, y1, ...].
  final List<double> points;
  final double alpha;
  final bool isMarker;

  @override
  Rect get bounds {
    if (points.length < 2) return Rect.zero;
    var minX = points[0];
    var maxX = points[0];
    var minY = points[1];
    var maxY = points[1];
    for (var i = 2; i + 1 < points.length; i += 2) {
      if (points[i] < minX) minX = points[i];
      if (points[i] > maxX) maxX = points[i];
      if (points[i + 1] < minY) minY = points[i + 1];
      if (points[i + 1] > maxY) maxY = points[i + 1];
    }
    final pad = size / 2;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  @override
  bool hitByDisk(Offset p, double r) {
    final reach = (r + size / 2).clamp(0.0, 1.0e12);
    final rr = reach * reach;
    // Coarse bbox reject first: strokes can hold thousands of points.
    if (!bounds.inflate(reach).contains(p) && _distToBox2(p, bounds) > rr) return false;
    for (var i = 0; i + 1 < points.length; i += 2) {
      final dx = points[i] - p.dx;
      final dy = points[i + 1] - p.dy;
      if (dx * dx + dy * dy <= rr) return true;
    }
    // Points alone miss long segments; test each one too.
    for (var i = 0; i + 3 < points.length; i += 2) {
      if (_distToSegment2(
            p,
            Offset(points[i], points[i + 1]),
            Offset(points[i + 2], points[i + 3]),
          ) <=
          rr) {
        return true;
      }
    }
    return false;
  }

  static double _distToBox2(Offset p, Rect b) {
    final dx = p.dx < b.left ? b.left - p.dx : (p.dx > b.right ? p.dx - b.right : 0.0);
    final dy = p.dy < b.top ? b.top - p.dy : (p.dy > b.bottom ? p.dy - b.bottom : 0.0);
    return dx * dx + dy * dy;
  }

  static double _distToSegment2(Offset p, Offset a, Offset b) {
    final vx = b.dx - a.dx;
    final vy = b.dy - a.dy;
    final wx = p.dx - a.dx;
    final wy = p.dy - a.dy;
    final len2 = vx * vx + vy * vy;
    double t = len2 == 0 ? 0 : (wx * vx + wy * vy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = a.dx + t * vx - p.dx;
    final cy = a.dy + t * vy - p.dy;
    return cx * cx + cy * cy;
  }

  /// Catmull-Rom -> cubic bezier: smooth ink without resampling the raw points.
  Path buildPath() {
    final path = Path();
    final n = points.length ~/ 2;
    if (n < 2) return path;
    path.moveTo(points[0], points[1]);
    if (n == 2) {
      path.lineTo(points[2], points[3]);
      return path;
    }
    const k = 1.0 / 6.0;
    for (var i = 0; i < n - 1; i++) {
      final i0 = i > 0 ? i - 1 : 0;
      final i3 = i + 2 < n ? i + 2 : n - 1;
      final p1 = Offset(points[2 * i], points[2 * i + 1]);
      final p2 = Offset(points[2 * i + 2], points[2 * i + 3]);
      final c1 = Offset(p1.dx + (p2.dx - points[2 * i0]) * k, p1.dy + (p2.dy - points[2 * i0 + 1]) * k);
      final c2 = Offset(p2.dx - (points[2 * i3] - p1.dx) * k, p2.dy - (points[2 * i3 + 1] - p1.dy) * k);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, double scale) {
    if (points.length < 2) return;
    canvas.drawPath(
      buildPath(),
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = size
        ..strokeCap = isMarker ? StrokeCap.square : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true,
    );
  }
}

class Shape extends Item {
  Shape({
    required super.color,
    required super.size,
    required this.kind,
    required this.a,
    required this.b,
  });

  final ShapeKind kind;
  final Offset a;
  final Offset b;

  Rect get rect => Rect.fromPoints(a, b);

  @override
  Rect get bounds => rect.inflate(size);

  @override
  bool hitByDisk(Offset p, double r) {
    final box = bounds;
    switch (kind) {
      case ShapeKind.line:
      case ShapeKind.arrow:
        return Stroke._distToSegment2(p, a, b) <= (r + size / 2) * (r + size / 2);
      case ShapeKind.rect:
        return box.inflate(r).contains(p);
      case ShapeKind.ellipse:
        // Approximate the ring by testing the inscribed/surrounding circle.
        final c = rect.center;
        final rad = rect.shortestSide / 2;
        final d = (p - c).distance;
        return (d - rad).abs() <= r + size / 2 || d <= rad;
    }
  }

  @override
  void paint(Canvas canvas, double scale) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    switch (kind) {
      case ShapeKind.line:
        canvas.drawLine(a, b, paint);
      case ShapeKind.arrow:
        canvas.drawLine(a, b, paint);
        _arrowHead(canvas, paint);
      case ShapeKind.rect:
        canvas.drawRect(rect, paint);
      case ShapeKind.ellipse:
        canvas.drawOval(rect, paint);
    }
  }

  void _arrowHead(Canvas canvas, Paint paint) {
    final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
    final len = (size * 3 + 10).clamp(10.0, 40.0);
    const spread = 0.42;
    canvas.drawPath(
      Path()
        ..moveTo(b.dx, b.dy)
        ..lineTo(b.dx - len * math.cos(angle - spread), b.dy - len * math.sin(angle - spread))
        ..lineTo(b.dx - len * math.cos(angle + spread), b.dy - len * math.sin(angle + spread))
        ..close(),
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );
  }
}

class TextItem extends Item {
  TextItem({
    required super.color,
    required super.size,
    required this.text,
    required this.origin,
  });

  final String text;
  final Offset origin;

  @override
  Rect get bounds => Rect.fromLTWH(origin.dx, origin.dy, size * 0.6 * text.length, size * 1.2);

  @override
  bool hitByDisk(Offset p, double r) => bounds.inflate(r).contains(p);

  @override
  void paint(Canvas canvas, double scale) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, height: 1.2)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, origin);
  }
}

class ImageItem extends Item {
  ImageItem({required this.image, required this.dest})
      : super(color: const Color(0xFF000000), size: 0);

  final ui.Image image;
  final Rect dest;

  @override
  Rect get bounds => dest;

  @override
  bool hitByDisk(Offset p, double r) => dest.inflate(r).contains(p);

  @override
  void paint(Canvas canvas, double scale) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dest, Paint()..isAntiAlias = true);
  }
}

class Board {
  Board();

  final List<Item> items = <Item>[];
  PaperStyle paper = PaperStyle.dots;

  /// Union of every item box, in world coordinates; zero when empty.
  Rect get contentBounds {
    Rect? acc;
    for (final item in items) {
      final b = item.bounds;
      acc = acc == null ? b : acc.expandToInclude(b);
    }
    return acc ?? Rect.zero;
  }
}

/// World <-> screen transform: screen = world * scale + (x, y).
class Camera {
  Camera({this.x = 0, this.y = 0, this.scale = 1.0});

  double x;
  double y;
  double scale;

  Offset toWorld(Offset screen) => Offset((screen.dx - x) / scale, (screen.dy - y) / scale);

  Offset toScreen(Offset world) => Offset(world.dx * scale + x, world.dy * scale + y);
}
