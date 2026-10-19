import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The address where users send bug reports, ideas, and complaints.
const String kFeedbackEmail = 'lazyawen@163.com';

/// Shown in the mail template so reports can be matched to a build.
const String kAppVersion = '2.1.0';

/// Builds the `mailto:` used by the feedback button: a pre-filled subject with
/// the app version, plus a body template asking for the things that actually
/// help debugging (device, steps to reproduce).
Uri feedbackUri() {
  final String topic = Uri.encodeComponent('涂想 Doodle 使用反馈');
  final String body = Uri.encodeComponent(
    '（可选）你的联系方式：\n'
    '问题 / 建议：\n'
    '\n'
    '怎么复现：\n'
    '1. \n'
    '2. \n'
    '3. \n'
    '\n'
    '期望的效果：\n'
    '\n'
    '--- 以下信息我们不会改，留着方便定位问题 ---\n'
    '版本：$kAppVersion\n',
  );
  return Uri.parse('mailto:$kFeedbackEmail?subject=$topic&body=$body');
}

/// Shows the feedback address with two actions: open the mail app, or copy the
/// address to the clipboard (for the many devices with no mail app set up).
Future<void> showFeedbackSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      return const SafeArea(child: _FeedbackSheet());
    },
  );
}

/// Tries to hand the mail intent to the system. Returns false instead of
/// throwing when no mail client is installed, so callers can fall back to
/// showing the address again.
Future<bool> sendFeedback() async {
  final Uri uri = feedbackUri();
  try {
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri);
    }
    // Some platforms report no handler even though one exists; trying anyway
    // is harmless and covers those devices.
    return await launchUrl(uri, mode: LaunchMode.platformDefault);
  } catch (_) {
    return false;
  }
}

class _FeedbackSheet extends StatelessWidget {
  const _FeedbackSheet();

  Future<void> _open(BuildContext context) async {
    final bool ok = await sendFeedback();
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('没找到邮件应用，可以先复制下面的邮箱地址'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: kFeedbackEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('邮箱地址已复制'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // Scrollable so the sheet still fits on short screens (phones in landscape,
    // small windows) instead of overflowing its Column.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.mail_outline, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '反馈意见',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '哪里不好用、想要什么功能、或者发现 bug，都欢迎写信告诉我。'
            '这个软件完全离线没法自动上报，所以你的邮件就是唯一的反馈渠道 —— 真的会看。',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    kFeedbackEmail,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '复制邮箱',
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _open(context),
            icon: const Icon(Icons.alternate_email, size: 18),
            label: const Text('写邮件给我'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
