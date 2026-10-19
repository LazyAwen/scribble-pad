import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the picker as a dialog and returns the chosen color, or null if cancelled.
Future<Color?> showColorPickerDialog({
  required BuildContext context,
  required Color initial,
  List<Color> presets = const <Color>[],
}) {
  return showDialog<Color>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0x33000000),
    builder: (BuildContext dialogContext) {
      return _ColorPickerDialog(initial: initial, presets: presets);
    },
  );
}

/// Side length the saturation/value square wants to be.
const double _kSquareSize = 220.0;

/// Height reserved for each horizontal slider strip.
const double _kStripHeight = 34.0;

/// Radius of the round thumb drawn on the saturation/value square.
const double _kSquareThumbRadius = 9.0;

/// Evenly spaced hue stops: 0°, 60°, ... 360° (wraps back to red).
const List<Color> _kHueStops = <Color>[
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF00FF00),
  Color(0xFF00FFFF),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

/// The four HSV channels the picker edits.
class _Hsv {
  const _Hsv(this.alpha, this.hue, this.saturation, this.value);

  final double alpha;
  final double hue;
  final double saturation;
  final double value;

  Color toColor() {
    return HSVColor.fromAHSV(alpha, hue, saturation, value).toColor();
  }
}

/// Reports a saturation/value pick as `(saturation, value)`, both 0..1.
typedef _SvChanged = void Function(double saturation, double value);

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initial,
    required this.presets,
  });

  final Color initial;
  final List<Color> presets;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late _Hsv _hsv;
  late final TextEditingController _hexController;
  late final FocusNode _hexFocus;

  @override
  void initState() {
    super.initState();
    final HSVColor initial = HSVColor.fromColor(widget.initial);
    _hsv = _Hsv(initial.alpha, initial.hue, initial.saturation, initial.value);
    _hexController = TextEditingController(text: _hexText(_hsv.toColor()));
    _hexFocus = FocusNode();
    _hexFocus.addListener(_onHexFocusChanged);
  }

  @override
  void dispose() {
    _hexFocus.removeListener(_onHexFocusChanged);
    _hexFocus.dispose();
    _hexController.dispose();
    super.dispose();
  }

  void _update(_Hsv next) {
    setState(() {
      _hsv = next;
    });
    if (_hexFocus.hasFocus) {
      return;
    }
    _hexController.text = _hexText(next.toColor());
  }

  void _onHueChanged(double hue) {
    _update(_Hsv(_hsv.alpha, hue, _hsv.saturation, _hsv.value));
  }

  void _onAlphaChanged(double alpha) {
    _update(_Hsv(alpha, _hsv.hue, _hsv.saturation, _hsv.value));
  }

  void _onSvChanged(double saturation, double value) {
    _update(_Hsv(_hsv.alpha, _hsv.hue, saturation, value));
  }

  void _onPresetTap(Color color) {
    final HSVColor hsv = HSVColor.fromColor(color);
    final _Hsv next = _Hsv(hsv.alpha, hsv.hue, hsv.saturation, hsv.value);
    _update(next);
    _hexController.text = _hexText(next.toColor());
  }

  void _onHexFocusChanged() {
    if (_hexFocus.hasFocus) {
      return;
    }
    _commitHex(_hexController.text);
  }

  void _onHexChanged(String text) {
    final _Hsv? parsed = _parseHex(text, _hsv.alpha);
    if (parsed != null) {
      _update(parsed);
    }
  }

  void _onHexSubmitted(String text) {
    final _Hsv? parsed = _parseHex(text, _hsv.alpha);
    if (parsed != null) {
      _update(parsed);
    }
    _hexController.text = _hexText(_hsv.toColor());
    _hexFocus.unfocus();
  }

  void _commitHex(String text) {
    final _Hsv? parsed = _parseHex(text, _hsv.alpha);
    if (parsed != null) {
      _update(parsed);
    }
    _hexController.text = _hexText(_hsv.toColor());
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _confirm() {
    Navigator.of(context).pop(_hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color current = _hsv.toColor();
    final List<Color> presets = widget.presets;
    final TextStyle? labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final TextStyle? valueStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurface,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('自定义颜色', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(child: Text('色相', style: labelStyle)),
                  Text('${_hsv.hue.round()}°', style: valueStyle),
                ],
              ),
              _HueStrip(hue: _hsv.hue, onChanged: _onHueChanged),
              const SizedBox(height: 10),
              Text('饱和度 / 明度', style: labelStyle),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double size = constraints.maxWidth < _kSquareSize
                      ? constraints.maxWidth
                      : _kSquareSize;
                  return Center(
                    child: _SvSquare(
                      size: size,
                      hue: _hsv.hue,
                      saturation: _hsv.saturation,
                      value: _hsv.value,
                      onChanged: _onSvChanged,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(child: Text('不透明度', style: labelStyle)),
                  Text('${(_hsv.alpha * 100).round()}%', style: valueStyle),
                ],
              ),
              _AlphaStrip(
                color: current.withValues(alpha: 1.0),
                alpha: _hsv.alpha,
                onChanged: _onAlphaChanged,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  _PreviewSwatch(color: current),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexController,
                      focusNode: _hexFocus,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: _onHexChanged,
                      onSubmitted: _onHexSubmitted,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9a-fA-F#]'),
                        ),
                      ],
                      style: const TextStyle(
                        fontSize: 15,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '十六进制 #RRGGBB',
                        helperText: '支持 #RRGGBB 或 #AARRGGBB',
                        helperMaxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
              if (presets.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text('预设', style: labelStyle),
                const SizedBox(height: 6),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: presets.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final Color preset = presets[index];
                      return _PresetSwatch(
                        color: preset,
                        selected: _isSameColor(preset, current),
                        onTap: () => _onPresetTap(preset),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(onPressed: _cancel, child: const Text('取消')),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: _confirm, child: const Text('确定')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal hue slider drawn over a static rainbow gradient.
class _HueStrip extends StatelessWidget {
  const _HueStrip({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kStripHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(7)),
                    gradient: const LinearGradient(colors: _kHueStops),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned.fill(
              child: _TransparentTrackSlider(
                value: hue,
                max: 360.0,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal alpha slider drawn over a fading gradient plus checkerboard.
class _AlphaStrip extends StatelessWidget {
  const _AlphaStrip({
    required this.color,
    required this.alpha,
    required this.onChanged,
  });

  final Color color;
  final double alpha;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kStripHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(7)),
                  child: Stack(
                    children: <Widget>[
                      const Positioned.fill(
                        child: CustomPaint(painter: _CheckerPainter(square: 7)),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                color,
                                color.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: _TransparentTrackSlider(
                value: alpha,
                max: 1.0,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A [Slider] with an invisible track, so whatever it is stacked over shows through.
class _TransparentTrackSlider extends StatelessWidget {
  const _TransparentTrackSlider({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 14.0,
        activeTrackColor: const Color(0x00000000),
        inactiveTrackColor: const Color(0x00000000),
        thumbColor: const Color(0xFFFFFFFF),
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Slider(min: 0.0, max: max, value: value, onChanged: onChanged),
    );
  }
}

/// The draggable saturation/value square for the current hue.
class _SvSquare extends StatelessWidget {
  const _SvSquare({
    required this.size,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double size;
  final double hue;
  final double saturation;
  final double value;
  final _SvChanged onChanged;

  void _pick(Offset local) {
    final double s = _clamp(local.dx / size);
    final double v = 1.0 - _clamp(local.dy / size);
    onChanged(s, v);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (DragDownDetails details) => _pick(details.localPosition),
          onPanUpdate: (DragUpdateDetails details) =>
              _pick(details.localPosition),
          onTapDown: (TapDownDetails details) => _pick(details.localPosition),
          child: CustomPaint(
            painter: _SvPainter(
              hue: hue,
              saturation: saturation,
              value: value,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the SV plane: white→hue horizontally, transparent→black vertically.
class _SvPainter extends CustomPainter {
  const _SvPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });

  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Color hueColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();

    final Paint saturationPaint = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.topRight,
        <Color>[const Color(0xFFFFFFFF), hueColor],
      );
    canvas.drawRect(rect, saturationPaint);

    final Paint valuePaint = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomLeft,
        <Color>[const Color(0x00000000), const Color(0xFF000000)],
      );
    canvas.drawRect(rect, valuePaint);

    final Offset center = Offset(
      saturation * size.width,
      (1.0 - value) * size.height,
    );
    final Paint ring = Paint()
      ..color = const Color(0x99000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..isAntiAlias = true;
    canvas.drawCircle(center, _kSquareThumbRadius, ring);

    final Paint knob = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..isAntiAlias = true;
    canvas.drawCircle(center, _kSquareThumbRadius - 1.5, knob);
  }

  @override
  bool shouldRepaint(covariant _SvPainter oldDelegate) {
    return oldDelegate.hue != hue ||
        oldDelegate.saturation != saturation ||
        oldDelegate.value != value;
  }
}

/// Grey checkerboard used behind anything translucent so alpha reads correctly.
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter({this.square = 8.0});

  final double square;

  @override
  void paint(Canvas canvas, Size size) {
    final int columns = (size.width / square).ceil();
    final int rows = (size.height / square).ceil();
    final Paint light = Paint()..color = const Color(0xFFFFFFFF);
    final Paint dark = Paint()..color = const Color(0xFFCFD8DC);
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < columns; x++) {
        final bool isLight = (x + y).isEven;
        canvas.drawRect(
          Rect.fromLTWH(x * square, y * square, square, square),
          isLight ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) {
    return oldDelegate.square != square;
  }
}

/// The live preview: the current color laid over a checkerboard.
class _PreviewSwatch extends StatelessWidget {
  const _PreviewSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: Border.all(color: const Color(0x4D000000)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: CustomPaint(painter: _CheckerPainter(square: 7)),
          ),
          Positioned.fill(child: ColoredBox(color: color)),
        ],
      ),
    );
  }
}

/// One tappable preset chip.
class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          border: Border.all(
            color: selected
                ? const Color(0xFF1565C0)
                : const Color(0x33000000),
            width: selected ? 2.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: CustomPaint(painter: _CheckerPainter(square: 6)),
            ),
            Positioned.fill(child: ColoredBox(color: color)),
          ],
        ),
      ),
    );
  }
}

double _clamp(double v) {
  if (v < 0.0) {
    return 0.0;
  }
  if (v > 1.0) {
    return 1.0;
  }
  return v;
}

/// Formats a color as `RRGGBB`, or `AARRGGBB` when it is not opaque (no `#`).
String _hexText(Color color) {
  final int argb = color.toARGB32();
  final int a = (argb >> 24) & 0xFF;
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  final String alpha = a == 0xFF ? '' : _twoDigitHex(a);
  return '#$alpha${_twoDigitHex(r)}${_twoDigitHex(g)}${_twoDigitHex(b)}'
      .toUpperCase();
}

String _twoDigitHex(int v) {
  return v.toRadixString(16).padLeft(2, '0');
}

/// Parses `#RRGGBB` / `#AARRGGBB` (leading `#` optional), keeping [fallbackAlpha].
_Hsv? _parseHex(String raw, double fallbackAlpha) {
  final String text = raw.trim().replaceAll('#', '');
  if (text.length != 6 && text.length != 8) {
    return null;
  }
  final int? parsed = int.tryParse(text, radix: 16);
  if (parsed == null) {
    return null;
  }
  final int rgb = parsed & 0xFFFFFF;
  final double alpha = text.length == 8
      ? ((parsed >> 24) & 0xFF) / 255.0
      : fallbackAlpha;
  final HSVColor hsv = HSVColor.fromColor(
    Color.fromARGB(
      (alpha * 255.0).round() & 0xFF,
      (rgb >> 16) & 0xFF,
      (rgb >> 8) & 0xFF,
      rgb & 0xFF,
    ),
  );
  return _Hsv(alpha, hsv.hue, hsv.saturation, hsv.value);
}

bool _isSameColor(Color a, Color b) {
  return a.toARGB32() == b.toARGB32();
}
