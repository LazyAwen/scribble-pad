import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';

import 'src/model.dart';
import 'src/painter.dart';
import 'src/toolbar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScribbleApp());
}

class ScribbleApp extends StatelessWidget {
  const ScribbleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scribble Pad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1971C2)),
      ),
      home: const BoardPage(),
    );
  }
}

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  final Board _board = Board();
  final Camera _camera = Camera();

  /// Snapshots of the item list; index 0 is the empty board.
  final List<List<Item>> _history = <List<Item>>[<Item>[]];
  int _historyIndex = 0;

  Tool _tool = Tool.pen;
  Color _color = kPalette.first;
  double _size = 3.0;
  Item? _draft;

  /// Live pointers: id -> latest local position. Two at once means pan/zoom.
  final Map<int, Offset> _pointers = <int, Offset>{};
  bool _gesturing = false;
  double _gestureDist = 0;
  double _gestureBaseScale = 1;
  Offset? _gestureWorldAnchor;

  /// Desktop-only: right or middle drag pans.
  bool _panning = false;
  Offset? _panLast;

  final GlobalKey _canvasKey = GlobalKey();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  Offset? _textAt;

  static const double _minScale = 0.1;
  static const double _maxScale = 12.0;
  static const double _eraserBoost = 1.35;

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  @override
  void dispose() {
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- history

  void _commit() {
    _history.removeRange(_historyIndex + 1, _history.length);
    _history.add(List<Item>.of(_board.items));
    if (_history.length > 200) _history.removeAt(0);
    _historyIndex = _history.length - 1;
  }

  void _applyHistorySnapshot() {
    _board.items
      ..clear()
      ..addAll(_history[_historyIndex]);
    _draft = null;
  }

  void _undo() {
    if (!_canUndo) return;
    setState(() {
      _historyIndex--;
      _applyHistorySnapshot();
    });
  }

  void _redo() {
    if (!_canRedo) return;
    setState(() {
      _historyIndex++;
      _applyHistorySnapshot();
    });
  }

  void _clear() {
    if (_board.items.isEmpty) return;
    setState(() {
      _board.items.clear();
      _draft = null;
    });
    _commit();
  }

  // ---------------------------------------------------------------- pointer

  void _onPointerDown(PointerDownEvent e) {
    // Middle / right mouse button always pans, whatever tool is held.
    if (e.buttons != kPrimaryButton && e.buttons != 0) {
      _panning = true;
      _panLast = e.localPosition;
      return;
    }

    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length >= 2) {
      _beginGesture();
      return;
    }
    if (_pointers.length != 1) return;

    if (_draft != null) return;

    if (_tool == Tool.text) {
      _openTextEditor(_camera.toWorld(e.localPosition));
      return;
    }

    final w = _camera.toWorld(e.localPosition);
    setState(() {
      switch (_tool) {
        case Tool.pen:
        case Tool.marker:
          _draft = Stroke(
            color: _color,
            size: _size,
            points: <double>[w.dx, w.dy],
            alpha: _tool == Tool.marker ? 0.35 : 1.0,
            isMarker: _tool == Tool.marker,
          );
        case Tool.eraser:
          if (_eraseAt(w)) _commitQueued = true;
        case Tool.line:
        case Tool.arrow:
        case Tool.rect:
        case Tool.ellipse:
          _draft = Shape(
            color: _color,
            size: _size,
            kind: _shapeKind(_tool),
            a: w,
            b: w,
          );
        case Tool.text:
          break;
      }
    });
    if (_commitQueued) {
      _commitQueued = false;
      _commit();
    }
  }

  bool _commitQueued = false;

  ShapeKind _shapeKind(Tool t) => switch (t) {
        Tool.line => ShapeKind.line,
        Tool.arrow => ShapeKind.arrow,
        Tool.rect => ShapeKind.rect,
        _ => ShapeKind.ellipse,
      };

  void _onPointerMove(PointerMoveEvent e) {
    if (_panning) {
      final d = e.localPosition - (_panLast ?? e.localPosition);
      setState(() {
        _camera.x += d.dx;
        _camera.y += d.dy;
      });
      _panLast = e.localPosition;
      return;
    }

    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length >= 2) {
      if (_gesturing) _updateGesture();
      return;
    }
    if (_pointers.length != 1) return;

    final w = _camera.toWorld(e.localPosition);

    if (_tool == Tool.eraser) {
      setState(() {
        if (_eraseAt(w)) _commitQueued = true;
      });
      return;
    }

    final d = _draft;
    if (d is Stroke) {
      final last = Offset(d.points[d.points.length - 2], d.points[d.points.length - 1]);
      // Drop sub-pixel jitter: keeps point counts sane on a 1000 Hz stylus
      // without visibly changing the line.
      if ((w - last).distance * _camera.scale < 1.0) return;
      d.points
        ..add(w.dx)
        ..add(w.dy);
      setState(() {});
    } else if (d is Shape) {
      setState(() => _draft = Shape(
            color: d.color,
            size: d.size,
            kind: d.kind,
            a: d.a,
            b: _snap(d.a, w),
          ));
    }
  }

  /// Shift constrains lines to 15-degree steps and rects/ellipses to squares.
  Offset _snap(Offset a, Offset b) {
    if (!HardwareKeyboard.instance.isShiftPressed) return b;
    if (_tool == Tool.line || _tool == Tool.arrow) {
      const step = math.pi / 12;
      final len = (b - a).distance;
      final snapped = (math.atan2(b.dy - a.dy, b.dx - a.dx) / step).round() * step;
      return Offset(a.dx + len * math.cos(snapped), a.dy + len * math.sin(snapped));
    }
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final side = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
    return Offset(a.dx + side * dx.sign, a.dy + side * dy.sign);
  }

  /// Whole-stroke eraser: any touched stroke goes, so it behaves like a board
  /// marker rather than nudging individual pixels.
  bool _eraseAt(Offset w) {
    final r = _size * _eraserBoost;
    final before = _board.items.length;
    _board.items.removeWhere((item) => item.hitByDisk(w, r));
    return _board.items.length != before;
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);

    if (_panning) {
      if (_pointers.isEmpty) {
        _panning = false;
        _panLast = null;
      }
      return;
    }

    if (_pointers.isNotEmpty) {
      // One finger of a pinch lifted: drop the draft so drawing does not
      // resume underneath the remaining finger.
      if (_gesturing) {
        setState(() => _draft = null);
      }
      return;
    }

    if (_gesturing) {
      _gesturing = false;
      setState(() => _draft = null);
      return;
    }

    final d = _draft;
    _draft = null;
    if (d is Stroke) {
      if (d.points.length >= 2) {
        _board.items.add(d);
        setState(() {});
        _commit();
        return;
      }
      setState(() {});
      return;
    }
    if (d is Shape) {
      final moved = (d.b - d.a).distance;
      if (moved >= 2) {
        _board.items.add(Shape(
          color: d.color,
          size: d.size,
          kind: d.kind,
          a: d.a,
          b: _snap(d.a, d.b),
        ));
        setState(() {});
        _commit();
        return;
      }
    }
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) {
      _panning = false;
      _panLast = null;
      _gesturing = false;
      setState(() => _draft = null);
    }
  }

  void _beginGesture() {
    final pts = _pointers.values.toList();
    _gestureDist = (pts[0] - pts[1]).distance;
    _gestureBaseScale = _camera.scale;
    _gestureWorldAnchor =
        _camera.toWorld(Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2));
    _gesturing = true;
    setState(() => _draft = null);
  }

  void _updateGesture() {
    final pts = _pointers.values.toList();
    final centroid = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    final dist = (pts[0] - pts[1]).distance;
    if (_gestureDist <= 0) return;
    final scale = (_gestureBaseScale * dist / _gestureDist).clamp(_minScale, _maxScale);
    final anchor = _gestureWorldAnchor!;
    setState(() {
      _camera.scale = scale;
      _camera.x = centroid.dx - anchor.dx * scale;
      _camera.y = centroid.dy - anchor.dy * scale;
    });
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final before = _camera.toWorld(e.localPosition);
    if (HardwareKeyboard.instance.isControlPressed) {
      setState(() => _camera.scale =
          (_camera.scale * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(_minScale, _maxScale));
    } else {
      setState(() {
        _camera.x -= e.scrollDelta.dx;
        _camera.y -= e.scrollDelta.dy;
      });
      return;
    }
    final after = _camera.toWorld(e.localPosition);
    setState(() {
      _camera.x += (after.dx - before.dx) * _camera.scale;
      _camera.y += (after.dy - before.dy) * _camera.scale;
    });
  }

  // ------------------------------------------------------------------- text

  void _openTextEditor(Offset world) {
    setState(() {
      _textAt = world;
      _textController.clear();
    });
    _textFocus.requestFocus();
  }

  void _submitText() {
    final t = _textController.text.trim();
    final at = _textAt;
    setState(() => _textAt = null);
    _textController.clear();
    if (t.isEmpty || at == null) return;
    setState(() {
      _board.items.add(TextItem(
        color: _color,
        size: (_size * 6).clamp(12.0, 400.0),
        text: t,
        origin: at,
      ));
    });
    _commit();
  }

  // ------------------------------------------------------------------ image

  Future<void> _insertImage() async {
    try {
      const group = XTypeGroup(
        label: 'images',
        extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image img = frame.image;

      final render = _canvasKey.currentContext?.findRenderObject();
      final size = render is RenderBox ? render.size : const Size(1024, 768);
      final center = _camera.toWorld(size.center(Offset.zero));
      final targetW = size.width * 0.5 / _camera.scale;
      final scaleF = targetW / img.width;
      final w = img.width * scaleF;
      final h = img.height * scaleF;

      setState(() {
        _board.items.add(ImageItem(
          image: img,
          dest: Rect.fromLTWH(center.dx - w / 2, center.dy - h / 2, w, h),
        ));
      });
      _commit();
    } catch (err) {
      _toast('插入图片失败：$err');
    }
  }

  // ----------------------------------------------------------------- export

  Future<void> _exportPng() async {
    if (_board.items.isEmpty) {
      _toast('画板还是空的');
      return;
    }
    try {
      const double pad = 40;
      const double px = 2.0;
      final Rect bounds = _board.contentBounds;
      final Rect out = bounds.isEmpty ? const Rect.fromLTWH(0, 0, 1280, 720) : bounds.inflate(pad);

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Camera cam = Camera(x: -out.left * px, y: -out.top * px, scale: px);
      final Size canvasSize = Size(out.width * px, out.height * px);
      BoardPainter(
        board: _board,
        camera: cam,
        background: const Color(0xFFFFFFFF),
      ).paint(canvas, canvasSize);

      final ui.Picture picture = recorder.endRecording();
      final ui.Image image =
          await picture.toImage(canvasSize.width.ceil(), canvasSize.height.ceil());
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('encode failed');
      final Uint8List png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      final String name = 'scribble-${DateTime.now().millisecondsSinceEpoch}.png';
      // No save dialog (Android, or the user cancelled): fall back to a known
      // writable directory so the export never silently disappears.
      final FileSaveLocation? target = await _saveTarget(name);
      String? path = target?.path;
      if (path == null) {
        for (final dir in await _fallbackDirs()) {
          try {
            final p = '${dir.path}${Platform.pathSeparator}$name';
            await File(p).writeAsBytes(png, flush: true);
            path = p;
            break;
          } catch (_) {
            continue;
          }
        }
      } else {
        await File(path).writeAsBytes(png, flush: true);
      }
      if (path == null) throw StateError('no writable directory');
      _toast('已导出：$path');
    } catch (err) {
      _toast('导出失败：$err');
    }
  }

  /// Desktop: native save dialog. Android/mobile: null -> caller falls back.
  static Future<FileSaveLocation?> _saveTarget(String name) async {
    try {
      return await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: <XTypeGroup>[
          const XTypeGroup(label: 'png', extensions: <String>['png']),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<Directory>> _fallbackDirs() async {
    final out = <Directory>[];
    for (final get in <Future<Directory?> Function()>[
      getDownloadsDirectory,
      getApplicationDocumentsDirectory,
      getTemporaryDirectory,
    ]) {
      try {
        final d = await get();
        if (d != null) out.add(d);
      } catch (_) {}
    }
    return out;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------------- keys

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final mod = keys.isControlPressed || keys.isMetaPressed;
    final key = event.logicalKey;

    if (mod) {
      if (key == LogicalKeyboardKey.keyZ) {
        if (keys.isShiftPressed) {
          _redo();
        } else {
          _undo();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _redo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        _exportPng();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // A switch keeps this exhaustive-able and avoids a const map whose keys
    // override == (LogicalKeyboardKey does, so it cannot be a const map key).
    final Tool? t = switch (key) {
      LogicalKeyboardKey.digit1 => Tool.pen,
      LogicalKeyboardKey.digit2 => Tool.marker,
      LogicalKeyboardKey.digit3 => Tool.eraser,
      LogicalKeyboardKey.digit4 => Tool.line,
      LogicalKeyboardKey.digit5 => Tool.arrow,
      LogicalKeyboardKey.digit6 => Tool.rect,
      LogicalKeyboardKey.digit7 => Tool.ellipse,
      LogicalKeyboardKey.digit8 => Tool.text,
      _ => null,
    };
    if (t != null) {
      setState(() {
        _tool = t;
        _draft = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        onKeyEvent: _onKey,
        autofocus: true,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                onPointerSignal: _onPointerSignal,
                child: MouseRegion(
                  cursor: _tool == Tool.text
                      ? SystemMouseCursors.text
                      : SystemMouseCursors.precise,
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: CustomPaint(
                      isComplex: true,
                      painter: BoardPainter(
                        board: _board,
                        camera: _camera,
                        draft: _draft,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
            if (_textAt case final at?)
              Positioned(
                left: _camera.toScreen(at).dx.clamp(8.0, 100000.0),
                top: (_camera.toScreen(at).dy - 12).clamp(8.0, 100000.0),
                child: SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _textController,
                    focusNode: _textFocus,
                    autofocus: true,
                    style: TextStyle(color: _color, fontSize: (_size * 6).clamp(12.0, 96.0)),
                    decoration: const InputDecoration(
                      hintText: '输入文字，回车确认',
                      filled: true,
                      fillColor: Color(0xEEFFFFFF),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _submitText(),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Center(
                  child: ToolSection(
                    tool: _tool,
                    color: _color,
                    size: _size,
                    paper: _board.paper,
                    canUndo: _canUndo,
                    canRedo: _canRedo,
                    onTool: (t) => setState(() {
                      _tool = t;
                      _draft = null;
                    }),
                    onColor: (c) => setState(() => _color = c),
                    onSize: (s) => setState(() => _size = s),
                    onPaper: (p) => setState(() => _board.paper = p),
                    onUndo: _undo,
                    onRedo: _redo,
                    onClear: _clear,
                    onSave: _exportPng,
                    onImage: _insertImage,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
