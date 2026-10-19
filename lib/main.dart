import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/color_picker.dart';
import 'src/help_panel.dart';
import 'src/model.dart';
import 'src/painter.dart';
import 'src/toolbar.dart';

const String kAppTitle = '涂想 Doodle';
const double kExportPad = 40;
const double kExportPixelRatio = 2.0;
const String kGalleryFolder = '涂想';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DoodleApp());
}

class DoodleApp extends StatelessWidget {
  const DoodleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1971C2)),
      ),
      home: const BoardPage(),
    );
  }
}

/// Remembers where the user wants exports to land.
class SavePathStore {
  static const String _prefKey = 'save_dir';
  static const String _treePrefKey = 'save_tree_uri';
  static const String _treeNamePrefKey = 'save_tree_name';

  static Future<String?> loadCustom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_prefKey);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> saveCustom(String dir) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_prefKey, dir);
    } catch (_) {
      return false;
    }
  }

  /// The SAF folder the user picked on Android: its grant survives restarts,
  /// so remembering the URI is what makes the choice stick.
  static Future<Map<String, String>?> loadTree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uri = prefs.getString(_treePrefKey);
      if (uri == null || uri.isEmpty) return null;
      return <String, String>{
        'uri': uri,
        'name': prefs.getString(_treeNamePrefKey) ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTree(Map<String, String> tree) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_treePrefKey, tree['uri'] ?? '');
      await prefs.setString(_treeNamePrefKey, tree['name'] ?? '');
    } catch (_) {
      // A preference write failure must not break an export.
    }
  }

  static Future<void> clearTree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_treePrefKey);
      await prefs.remove(_treeNamePrefKey);
    } catch (_) {
      // ignore
    }
  }

  /// Returns the first candidate that exists (or can be created) and is
  /// actually writable. A write probe is the only reliable test, since scoped
  /// storage quietly refuses writes that a `stat` says are fine.
  static Future<String?> pickWritable(List<String> candidates) async {
    for (final c in candidates) {
      try {
        final d = Directory(c);
        if (!await d.exists()) await d.create(recursive: true);
        final probe =
            File('${d.path}${Platform.pathSeparator}.w${DateTime.now().millisecondsSinceEpoch}');
        await probe.writeAsString('1', flush: true);
        await probe.delete();
        return d.path;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}

class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> with TickerProviderStateMixin {
  final Board _board = Board();
  final Camera _camera = Camera();

  /// Bumped whenever the committed item list changes in a way a length compare
  /// cannot see (undo restoring an equal-sized snapshot, a paper swap, ...).
  /// Comparing it is what makes undo / redo / clear repaint immediately.
  int _version = 0;

  /// Separate counter for the live stroke, so drawing never repaints the board.
  int _draftVersion = 0;

  /// Snapshots of the item list; index 0 is the empty board.
  final List<List<Item>> _history = <List<Item>>[<Item>[]];
  int _historyIndex = 0;

  Tool _tool = Tool.pen;
  Color _color = kPalette.first;
  double _size = 3.0;
  Item? _draft;

  bool _toolbarCollapsed = false;
  Offset? _cursor;

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

  late final AnimationController _camAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
  )..addListener(_tickCameraAnimation);
  Camera _camFrom = Camera();
  Camera _camTo = Camera();

  String? _customSaveDir;

  /// Android only: a system-picked folder and its persistable grant.
  Map<String, String>? _saveTree;

  /// Bridges to the Kotlin side, where MediaStore and SAF live. Scoped storage
  /// makes raw File writes fail on Android 11+, so every phone export goes here.
  static const MethodChannel _saveChannel = MethodChannel('doodle/save');

  static const double _minScale = 0.1;
  static const double _maxScale = 12.0;
  static const double _eraserBoost = 1.35;

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  @override
  void initState() {
    super.initState();
    SavePathStore.loadCustom().then((v) {
      if (mounted && v != null) setState(() => _customSaveDir = v);
    });
    if (Platform.isAndroid) {
      SavePathStore.loadTree().then((t) {
        if (mounted && t != null) setState(() => _saveTree = t);
      });
    }
  }

  @override
  void dispose() {
    _camAnim.dispose();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Size get _viewport {
    final o = _canvasKey.currentContext?.findRenderObject();
    return o is RenderBox ? o.size : const Size(1024, 768);
  }

  // ---------------------------------------------------------------- history

  void _bump() => _version++;

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
      _bump();
    });
  }

  void _redo() {
    if (!_canRedo) return;
    setState(() {
      _historyIndex++;
      _applyHistorySnapshot();
      _bump();
    });
  }

  void _clear() {
    if (_board.items.isEmpty) return;
    setState(() {
      _board.items.clear();
      _draft = null;
      _bump();
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
    var commitQueued = false;
    setState(() {
      _bump();
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
          if (_eraseAt(w)) commitQueued = true;
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
      _draftVersion++;
    });
    if (commitQueued) _commit();
  }

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
        _bump();
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
      var commitQueued = false;
      setState(() {
        if (_eraseAt(w)) commitQueued = true;
        _draftVersion++;
      });
      if (commitQueued) _commit();
      return;
    }

    final d = _draft;
    if (d is Stroke) {
      final last = Offset(d.points[d.points.length - 2], d.points[d.points.length - 1]);
      // Drop sub-pixel jitter: keeps point counts sane on a 1000 Hz stylus
      // without visibly changing the line.
      if ((w - last).distance * _camera.scale < 1.0) return;
      setState(() {
        d.points
          ..add(w.dx)
          ..add(w.dy);
        // The draft is its own layer; bumping this is what makes ink appear
        // while the button is still down.
        _draftVersion++;
      });
    } else if (d is Shape) {
      setState(() {
        _draft = Shape(
          color: d.color,
          size: d.size,
          kind: d.kind,
          a: d.a,
          b: _snap(d.a, w),
        );
        _draftVersion++;
      });
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
        setState(() {
          _board.items.add(d);
          _bump();
        });
        _commit();
        return;
      }
      setState(() {});
      return;
    }
    if (d is Shape) {
      final moved = (d.b - d.a).distance;
      if (moved >= 2) {
        setState(() {
          _board.items.add(Shape(
            color: d.color,
            size: d.size,
            kind: d.kind,
            a: d.a,
            b: _snap(d.a, d.b),
          ));
          _bump();
        });
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
      _bump();
    });
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    // Wheel zooms (the whiteboard convention); Shift+wheel pans instead.
    if (HardwareKeyboard.instance.isShiftPressed) {
      setState(() {
        _camera.x -= e.scrollDelta.dx;
        _camera.y -= e.scrollDelta.dy;
        _bump();
      });
      return;
    }
    final factor = e.scrollDelta.dy > 0 ? 0.88 : 1.12;
    _zoomStep(factor, anchorScreen: e.localPosition);
  }

  // ------------------------------------------------------------------ camera

  Camera _cameraZoomedAround(double newScale, Offset screenAnchor) {
    final world = _camera.toWorld(screenAnchor);
    final s = newScale.clamp(_minScale, _maxScale);
    return Camera(
      x: screenAnchor.dx - world.dx * s,
      y: screenAnchor.dy - world.dy * s,
      scale: s,
    );
  }

  void _zoomStep(double factor, {Offset? anchorScreen}) {
    _animateTo(_cameraZoomedAround(_camera.scale * factor, anchorScreen ?? _centerScreen()));
  }

  void _zoomReset() => _animateTo(_cameraZoomedAround(1.0, _centerScreen()));

  Offset _centerScreen() {
    final s = _viewport;
    return Offset(s.width / 2, s.height / 2);
  }

  Camera _fitCamera() {
    final bounds = _board.contentBounds;
    if (bounds.isEmpty) return Camera();
    final size = _viewport;
    const pad = 48.0;
    final s = math
        .min((size.width - pad * 2) / bounds.width, (size.height - pad * 2) / bounds.height)
        .clamp(_minScale, _maxScale);
    return Camera(
      x: size.width / 2 - bounds.center.dx * s,
      y: size.height / 2 - bounds.center.dy * s,
      scale: s,
    );
  }

  void _animateTo(Camera to) {
    _camFrom = Camera(x: _camera.x, y: _camera.y, scale: _camera.scale);
    _camTo = to;
    _camAnim
      ..stop()
      ..reset()
      ..forward();
  }

  void _tickCameraAnimation() {
    if (!mounted) return;
    final t = Curves.easeOutCubic.transform(_camAnim.value);
    setState(() {
      _camera.x = ui.lerpDouble(_camFrom.x, _camTo.x, t)!;
      _camera.y = ui.lerpDouble(_camFrom.y, _camTo.y, t)!;
      _camera.scale = ui.lerpDouble(_camFrom.scale, _camTo.scale, t)!;
      _bump();
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
      _bump();
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

      final size = _viewport;
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
        _bump();
      });
      _commit();
    } catch (err) {
      _toast('插入图片失败：$err');
    }
  }

  // ----------------------------------------------------------------- export

  Future<Uint8List> _renderPng() async {
    final Rect bounds = _board.contentBounds;
    final Rect out = bounds.isEmpty
        ? const Rect.fromLTWH(0, 0, 1280, 720)
        : bounds.inflate(kExportPad);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Camera cam = Camera(
      x: -out.left * kExportPixelRatio,
      y: -out.top * kExportPixelRatio,
      scale: kExportPixelRatio,
    );
    final Size canvasSize =
        Size(out.width * kExportPixelRatio, out.height * kExportPixelRatio);
    // Paper off, white ground: an exported PNG should not ship the grid.
    final flat = Board()
      ..items.addAll(_board.items)
      ..paper = PaperStyle.blank;
    BoardPainter(
      board: flat,
      camera: cam,
      viewport: canvasSize,
      version: _version,
      background: const Color(0xFFFFFFFF),
    ).paint(canvas, canvasSize);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image =
        await picture.toImage(canvasSize.width.ceil(), canvasSize.height.ceil());
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('encode failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  String _exportName() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Doodle-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.png';
  }

  /// Desktop: a folder next to the program first, then Documents — an app
  /// installed under Program Files cannot write into its own directory.
  Future<List<String>> _desktopImageDirs() async {
    final exe = File(Platform.resolvedExecutable);
    final out = <String>[
      ?_customSaveDir,
      '${exe.parent.path}${Platform.pathSeparator}涂想图片',
    ];
    try {
      final docs = await getApplicationDocumentsDirectory();
      out.add('${docs.path}${Platform.pathSeparator}涂想');
    } catch (_) {}
    return out;
  }

  /// Desktop: absolute file to write, or null when the user cancelled.
  Future<String?> _desktopTarget(String name) async {
    final dirs = await _desktopImageDirs();
    final dir = await SavePathStore.pickWritable(dirs) ?? dirs.last;
    try {
      final target = await getSaveLocation(
        suggestedName: name,
        initialDirectory: dir,
        acceptedTypeGroups: <XTypeGroup>[
          const XTypeGroup(label: 'png', extensions: <String>['png']),
        ],
      );
      // Cancelling must not silently write somewhere else.
      return target?.path;
    } catch (_) {
      return null;
    }
  }

  /// Android 11+ blocks raw writes under /storage/emulated/0, so the file goes
  /// into a Pictures subfolder through MediaStore — visible in the gallery app
  /// and in any file manager, with no storage permission prompt.
  Future<String> _saveViaMediaStore(Uint8List png, String name) async {
    final path = await _saveChannel.invokeMethod<String>(
      'savePng',
      <String, Object?>{
        'bytes': png,
        'name': name,
        'folder': kGalleryFolder,
      },
    );
    if (path == null || path.isEmpty) {
      throw StateError('安卓保存失败');
    }
    return path;
  }

  /// Android write path: honour a SAF folder the user picked, else MediaStore.
  Future<String> _exportAndroid(Uint8List png, String name) async {
    final tree = _saveTree;
    if (tree != null) {
      try {
        final path = await _saveChannel.invokeMethod<String>(
          'saveToTree',
          <String, Object?>{
            'bytes': png,
            'name': name,
            'treeUri': tree['uri'],
          },
        );
        if (path != null && path.isNotEmpty) return path;
      } catch (_) {
        // The grant expires or the folder gets deleted (SD card pulled). Drop
        // it and fall back rather than losing the drawing.
        await SavePathStore.clearTree();
        if (mounted) setState(() => _saveTree = null);
      }
    }
    return _saveViaMediaStore(png, name);
  }

  /// Android has no `getDirectoryPath`; the system folder picker comes from the
  /// native side, which also keeps the write grant alive across restarts.
  Future<void> _chooseAndroidFolder() async {
    try {
      final picked = await _saveChannel.invokeMapMethod<String, String>('pickFolder');
      if (picked == null) {
        _toast('已取消');
        return;
      }
      final uri = picked['uri'] ?? '';
      if (uri.isEmpty) {
        _toast('已取消');
        return;
      }
      final tree = <String, String>{
        'uri': uri,
        'name': picked['name'] ?? '',
      };
      await SavePathStore.saveTree(tree);
      if (!mounted) return;
      setState(() => _saveTree = tree);
      final label = tree['name']!.isNotEmpty
          ? tree['name']!
          : (picked['path']?.isNotEmpty == true ? picked['path']! : '所选文件夹');
      _toast('保存位置已设为：$label');
    } catch (err) {
      _toast('选择文件夹失败：$err');
    }
  }

  Future<void> _exportPng() async {
    if (_board.items.isEmpty) {
      _toast('画板还是空的');
      return;
    }
    final Uint8List png;
    try {
      png = await _renderPng();
    } catch (err) {
      _toast('渲染失败：$err');
      return;
    }
    final String name = _exportName();
    try {
      if (Platform.isAndroid) {
        final path = await _exportAndroid(png, name);
        if (!mounted) return;
        await _showExportSheet(path, png, name);
        return;
      }
      final String? target = await _desktopTarget(name);
      if (target == null) {
        _toast('已取消导出');
        return;
      }
      await File(target).writeAsBytes(png, flush: true);
      if (!mounted) return;
      _toast('已保存到：$target');
    } catch (err) {
      _toast('导出失败：$err');
    }
  }

  Future<void> _showExportSheet(
    String path,
    Uint8List png,
    String name,
  ) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ExportSheet(
        path: path,
        onShare: () async {
          Navigator.of(ctx).pop();
          await _share(path, png, name);
        },
        onCopyDir: () async {
          final dir = File(path).parent.path;
          await Clipboard.setData(ClipboardData(text: dir));
          if (mounted) _toast('已复制文件夹路径：$dir');
        },
      ),
    );
  }

  /// The intent sheet needs a real file path, and a MediaStore URI handed to
  /// another app either fails or loses its read grant, so drop the PNG into the
  /// cache under its own name and share that copy.
  Future<String> _shareableCopy(Uint8List png, String name) async {
    try {
      final cache = await getTemporaryDirectory();
      final copy = File('${cache.path}${Platform.pathSeparator}$name');
      await copy.writeAsBytes(png, flush: true);
      return copy.path;
    } catch (_) {
      // No usable cache directory: fall through to the original path.
      return '';
    }
  }

  Future<void> _share(String path, Uint8List png, String name) async {
    try {
      final copy = await _shareableCopy(png, name);
      final target = copy.isEmpty ? path : copy;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(target)],
          text: kAppTitle,
          subject: File(target).uri.pathSegments.last,
        ),
      );
    } catch (err) {
      _toast('分享失败：$err');
    }
  }

  Future<void> _chooseSaveDir() async {
    if (Platform.isAndroid) {
      await _chooseAndroidFolder();
      return;
    }
    try {
      final dir = await getDirectoryPath();
      if (dir == null) {
        _toast('已取消');
        return;
      }
      final ok = await SavePathStore.pickWritable(<String>[dir]);
      if (ok == null) {
        _toast('这个文件夹不可写，换一个试试：$dir');
        return;
      }
      await SavePathStore.saveCustom(ok);
      if (!mounted) return;
      setState(() => _customSaveDir = ok);
      _toast('保存位置已设为：$ok');
    } catch (err) {
      _toast('选择文件夹失败：$err');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
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
      if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) {
        _zoomStep(1.2);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
        _zoomStep(1 / 1.2);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit0) {
        _zoomReset();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.keyF) {
      if (_board.items.isNotEmpty) _animateTo(_fitCamera());
      return KeyEventResult.handled;
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

  Future<void> _pickColor() async {
    final picked = await showColorPickerDialog(
      context: context,
      initial: _color,
      presets: kPalette,
    );
    if (picked == null) return;
    setState(() => _color = picked);
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final isTouch = Platform.isAndroid || Platform.isIOS;
    return Scaffold(
      body: Focus(
        onKeyEvent: _onKey,
        autofocus: true,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return Listener(
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
                      onHover: (ev) {
                        if (isTouch) return;
                        setState(() => _cursor = ev.localPosition);
                      },
                      onExit: (_) => setState(() => _cursor = null),
                      child: RepaintBoundary(
                        key: _canvasKey,
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: CustomPaint(
                                isComplex: true,
                                painter: BoardPainter(
                                  board: _board,
                                  camera: _camera,
                                  viewport: size,
                                  version: _version,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: DraftPainter(
                                  camera: _camera,
                                  draft: _draft,
                                  cursor: _tool == Tool.eraser ? _cursor : null,
                                  cursorSize: _size,
                                  version: _draftVersion,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: HelpPanel(
                  alignment: Alignment.topLeft,
                  isTouchDevice: isTouch,
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
              right: 12,
              top: 96,
              child: _ZoomControls(
                scale: _camera.scale,
                onZoomIn: () => _zoomStep(1.2),
                onZoomOut: () => _zoomStep(1 / 1.2),
                onReset: _zoomReset,
                onFit: _board.items.isEmpty ? null : () => _animateTo(_fitCamera()),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: _toolbarCollapsed ? -120 : 0,
              child: IgnorePointer(
                ignoring: _toolbarCollapsed,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _toolbarCollapsed ? 0 : 1,
                  child: SafeArea(
                    child: Center(
                      child: ToolSection(
                        tool: _tool,
                        color: _color,
                        size: _size,
                        paper: _board.paper,
                        canUndo: _canUndo,
                        canRedo: _canRedo,
                        onToggleCollapse: () =>
                            setState(() => _toolbarCollapsed = !_toolbarCollapsed),
                        onPickColor: _pickColor,
                        onChooseSaveDir: _chooseSaveDir,
                        onTool: (t) => setState(() {
                          _tool = t;
                          _draft = null;
                        }),
                        onColor: (c) => setState(() => _color = c),
                        onSize: (s) => setState(() => _size = s),
                        onPaper: (p) => setState(() {
                          _board.paper = p;
                          _bump();
                        }),
                        onUndo: _undo,
                        onRedo: _redo,
                        onClear: _clear,
                        onSave: _exportPng,
                        onImage: _insertImage,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: SafeArea(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _toolbarCollapsed ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_toolbarCollapsed,
                    child: FloatingActionButton.extended(
                      heroTag: 'toolbar',
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('展开工具栏'),
                      onPressed: () => setState(() => _toolbarCollapsed = false),
                    ),
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

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    this.onFit,
  });

  final double scale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback? onFit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: '放大',
              icon: const Icon(Icons.add, size: 20),
              onPressed: onZoomIn,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${(scale * 100).round()}%',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: '缩小',
              icon: const Icon(Icons.remove, size: 20),
              onPressed: onZoomOut,
            ),
            IconButton(
              tooltip: '100%',
              icon: const Icon(Icons.looks_one_outlined, size: 19),
              onPressed: onReset,
            ),
            IconButton(
              tooltip: '适应内容 (F)',
              icon: const Icon(Icons.fit_screen_outlined, size: 19),
              onPressed: onFit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportSheet extends StatelessWidget {
  const _ExportSheet({
    required this.path,
    required this.onShare,
    required this.onCopyDir,
  });

  final String path;
  final VoidCallback onShare;
  final VoidCallback onCopyDir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline),
              SizedBox(width: 8),
              Text('导出成功', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(path, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('分享到 QQ / 微信'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCopyDir,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('复制路径'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
