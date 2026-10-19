import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A collapsible panel pinned to a corner; when collapsed it is just a small
/// floating "?" chip. It never blocks pointer events outside its own body.
class HelpPanel extends StatefulWidget {
  const HelpPanel({
    super.key,
    this.alignment = Alignment.bottomLeft,
    this.isTouchDevice = false,
    this.initialExpanded = false,
  });

  final AlignmentGeometry alignment;
  final bool isTouchDevice;
  final bool initialExpanded;

  @override
  State<HelpPanel> createState() => _HelpPanelState();
}

class _HelpPanelState extends State<HelpPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<_HelpEntry> entries = widget.isTouchDevice
        ? _kTouchEntries
        : _kDesktopEntries;
    return _FillPassthrough(
      child: Align(
        alignment: widget.alignment,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: widget.alignment,
            clipBehavior: Clip.antiAlias,
            child: _expanded
                ? _HelpCard(entries: entries, onClose: _toggle)
                : _HelpChip(onOpen: _toggle),
          ),
        ),
      ),
    );
  }
}

/// One gesture row: an icon, a bold label and its description.
class _HelpEntry {
  const _HelpEntry(this.icon, this.title, this.detail);

  final IconData icon;
  final String title;
  final String detail;
}

const List<_HelpEntry> _kDesktopEntries = <_HelpEntry>[
  _HelpEntry(
    Icons.edit,
    '画笔/荧光笔',
    '按住左键拖动即可书写；数字键 1–8 快速切换工具',
  ),
  _HelpEntry(Icons.auto_fix_normal, '橡皮', '按住左键划过整条笔迹即可删除'),
  _HelpEntry(
    Icons.remove,
    '直线/箭头/矩形/椭圆',
    '按住左键从起点拖到终点，按住 Shift 吸附 15° 或画正方/正圆',
  ),
  _HelpEntry(Icons.title, '文字', '选中文字工具后点击画布，输入内容回车确认'),
  _HelpEntry(Icons.pan_tool, '平移', '按住鼠标右键或中键拖动；也可以直接滚动滚轮'),
  _HelpEntry(
    Icons.zoom_in,
    '缩放',
    '滚轮缩放（以光标为中心）；Ctrl+滚轮同样缩放；工具栏右下角也有 +/− 按钮',
  ),
  _HelpEntry(Icons.undo, '撤销/重做', 'Ctrl+Z 撤销，Ctrl+Shift+Z 或 Ctrl+Y 重做'),
  _HelpEntry(Icons.download, '导出', 'Ctrl+S 或点“导出 PNG”，可自选保存文件夹'),
  _HelpEntry(
    Icons.keyboard,
    '键盘',
    '1=画笔 2=荧光笔 3=橡皮 4=直线 5=箭头 6=矩形 7=椭圆 8=文字',
  ),
];

const List<_HelpEntry> _kTouchEntries = <_HelpEntry>[
  _HelpEntry(Icons.edit, '画笔/荧光笔', '单指按住拖动即可书写'),
  _HelpEntry(Icons.auto_fix_normal, '橡皮', '单指划过整条笔迹即可删除'),
  _HelpEntry(Icons.remove, '图形', '单指从起点拖到终点'),
  _HelpEntry(Icons.title, '文字', '点一下画布，输入内容回车确认'),
  _HelpEntry(Icons.pan_tool, '平移', '单指拖动空白处，或双指同时拖动'),
  _HelpEntry(Icons.zoom_in, '缩放', '双指捏合；右下角也有 +/− 按钮'),
  _HelpEntry(Icons.undo, '撤销/重做', '用工具栏的撤销/重做按钮'),
  _HelpEntry(
    Icons.download,
    '导出',
    '点“导出 PNG”，默认存到相册的“涂想”文件夹；保存后可分享或复制路径',
  ),
];

/// The collapsed state: a small circular "?" chip that opens the card.
class _HelpChip extends StatelessWidget {
  const _HelpChip({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: null,
      tooltip: '操作说明',
      onPressed: onOpen,
      child: const Icon(Icons.help_outline),
    );
  }
}

/// The expanded state: a compact, scrollable card of gesture rows.
class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.entries, required this.onClose});

  final List<_HelpEntry> entries;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.55;
    return Material(
      color: scheme.surface.withValues(alpha: 0.93),
      elevation: 6,
      shadowColor: const Color(0x33000000),
      surfaceTintColor: const Color(0x00000000),
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _HelpCardHeader(onClose: onClose),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final _HelpEntry entry in entries)
                      _HelpRow(entry: entry),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header strip holding the title and the close button.
class _HelpCardHeader extends StatelessWidget {
  const _HelpCardHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.help_outline, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '操作说明',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: '收起',
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// A single gesture row: icon on the left, label + description on the right.
class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.entry});

  final _HelpEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(entry.icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  entry.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.3,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fills the space it is given but never hit-tests itself, so taps that land
/// outside the panel body keep reaching whatever is painted underneath.
///
/// This keeps the panel usable both as a plain [Stack] child and inside a
/// [Positioned.fill]: it always has a real size to align its content against,
/// and the expanded card clips its own content while the collapsed chip stays
/// the only tap target.
class _FillPassthrough extends SingleChildRenderObjectWidget {
  const _FillPassthrough({required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFillPassthrough();
  }
}

class _RenderFillPassthrough extends RenderProxyBox {
  _RenderFillPassthrough({RenderBox? child}) : super(child);

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
      size = constraints.biggest;
      child.layout(
        BoxConstraints.tight(constraints.biggest),
        parentUsesSize: false,
      );
    } else {
      child.layout(constraints.loosen(), parentUsesSize: true);
      size = constraints.constrain(child.size);
    }
  }
}
