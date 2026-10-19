import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'model.dart';

typedef ToolChanged = void Function(Tool tool);
typedef ColorChanged = void Function(Color color);
typedef SizeChanged = void Function(double size);
typedef PaperChanged = void Function(PaperStyle paper);

class ToolSection extends StatelessWidget {
  const ToolSection({
    super.key,
    required this.tool,
    required this.color,
    required this.size,
    required this.paper,
    required this.canUndo,
    required this.canRedo,
    required this.onTool,
    required this.onColor,
    required this.onSize,
    required this.onPaper,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onSave,
    required this.onImage,
  });

  final Tool tool;
  final Color color;
  final double size;
  final PaperStyle paper;
  final bool canUndo;
  final bool canRedo;
  final ToolChanged onTool;
  final ColorChanged onColor;
  final SizeChanged onSize;
  final PaperChanged onPaper;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final VoidCallback onImage;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _ToolButton(
                icon: Icons.edit,
                label: '画笔',
                tooltip: '画笔 (1)',
                selected: tool == Tool.pen,
                onTap: () => onTool(Tool.pen),
              ),
              _ToolButton(
                icon: Icons.highlight,
                label: '荧光笔',
                tooltip: '荧光笔 (2)',
                selected: tool == Tool.marker,
                onTap: () => onTool(Tool.marker),
              ),
              _ToolButton(
                icon: Icons.auto_fix_normal,
                label: '橡皮',
                tooltip: '橡皮 (3)',
                selected: tool == Tool.eraser,
                onTap: () => onTool(Tool.eraser),
              ),
              _ToolButton(
                icon: Icons.remove,
                label: '直线',
                tooltip: '直线 (4) — 按住 Shift 吸附角度',
                selected: tool == Tool.line,
                onTap: () => onTool(Tool.line),
              ),
              _ToolButton(
                icon: Icons.arrow_forward,
                label: '箭头',
                tooltip: '箭头 (5)',
                selected: tool == Tool.arrow,
                onTap: () => onTool(Tool.arrow),
              ),
              _ToolButton(
                icon: Icons.rectangle_outlined,
                label: '矩形',
                tooltip: '矩形 (6)',
                selected: tool == Tool.rect,
                onTap: () => onTool(Tool.rect),
              ),
              _ToolButton(
                icon: Icons.circle_outlined,
                label: '椭圆',
                tooltip: '椭圆 (7)',
                selected: tool == Tool.ellipse,
                onTap: () => onTool(Tool.ellipse),
              ),
              _ToolButton(
                icon: Icons.title,
                label: '文字',
                tooltip: '文字 (8)',
                selected: tool == Tool.text,
                onTap: () => onTool(Tool.text),
              ),
              const _Divider(),
              for (final c in kPalette)
                _Swatch(color: c, selected: color == c, onTap: () => onColor(c)),
              const _Divider(),
              SizedBox(
                width: 132,
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.line_weight, size: 18),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: 48,
                        divisions: 47,
                        value: size.clamp(1, 48),
                        onChanged: onSize,
                      ),
                    ),
                  ],
                ),
              ),
              const _Divider(),
              _PaperMenu(paper: paper, onChanged: onPaper),
              const _Divider(),
              IconButton(
                tooltip: '插入图片',
                icon: const Icon(Icons.image_outlined),
                onPressed: onImage,
              ),
              IconButton(
                tooltip: '撤销 (Ctrl+Z)',
                icon: const Icon(Icons.undo),
                onPressed: canUndo ? onUndo : null,
              ),
              IconButton(
                tooltip: '重做 (Ctrl+Shift+Z)',
                icon: const Icon(Icons.redo),
                onPressed: canRedo ? onRedo : null,
              ),
              IconButton(
                tooltip: '清空画板',
                icon: const Icon(Icons.delete_outline),
                onPressed: onClear,
              ),
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('导出 PNG'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 19, color: fg),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hex = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return Tooltip(
      message: '#$hex',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.black12,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 15,
                  color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _PaperMenu extends StatelessWidget {
  const _PaperMenu({required this.paper, required this.onChanged});

  final PaperStyle paper;
  final PaperChanged onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PaperStyle>(
      tooltip: '底纹',
      initialValue: paper,
      onSelected: onChanged,
      itemBuilder: (context) => const <PopupMenuEntry<PaperStyle>>[
        PopupMenuItem(value: PaperStyle.blank, child: Text('空白')),
        PopupMenuItem(value: PaperStyle.dots, child: Text('点阵')),
        PopupMenuItem(value: PaperStyle.grid, child: Text('网格')),
        PopupMenuItem(value: PaperStyle.lines, child: Text('横线')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.grid_on, size: 18),
            const SizedBox(width: 4),
            Text(_label(paper), style: const TextStyle(fontSize: 12)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  static String _label(PaperStyle p) => switch (p) {
        PaperStyle.blank => '空白',
        PaperStyle.dots => '点阵',
        PaperStyle.grid => '网格',
        PaperStyle.lines => '横线',
      };
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 1,
        height: 24,
        child: VerticalDivider(width: 1, thickness: 1),
      );
}

/// Keeps the ring used by the eraser cursor preview in one place.
double ringRadius(double size) => size * 1.35 + 4 * math.log(size + 1);
