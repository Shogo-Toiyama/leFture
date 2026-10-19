// lib/presentation/widgets/ai_chat/chat_message_actions.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lefture/application/chat/chat_conversation.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/sheet_style.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_report_sheet.dart';

/// メッセージの下の操作行(コピー・編集・作り直し・「…」メニュー)。webappのChatMessageActionsと同じ。
///
/// - 自分のメッセージ: コピー・編集
/// - AIの回答: コピー・作り直し(最後の回答だけ)・「…」(詳細・報告)
/// コピーは押した瞬間に軽く振動して、チェックを1.4秒だけ出す。
class ChatMessageActions extends StatefulWidget {
  const ChatMessageActions({
    super.key,
    required this.copyText,
    required this.colors,
    this.detailsFor,
    this.question,
    this.onEdit,
    this.onRegenerate,
  });

  /// コピーする文字列(出典の印などの不要なものを取り除いた本文)。
  final String copyText;
  final ChatColors colors;

  /// 渡すと「…」メニュー(詳細・報告)を出す。自分のメッセージには渡さない。
  final LocalChatMessage? detailsFor;

  /// この回答のもとになった質問(報告に添える)。[detailsFor]と一緒に渡す。
  final String? question;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;

  @override
  State<ChatMessageActions> createState() => _ChatMessageActionsState();
}

class _ChatMessageActionsState extends State<ChatMessageActions> {
  Timer? _copiedTimer;
  bool _copied = false;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.copyText));
    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: _copied ? Icons.check_rounded : Icons.content_copy_rounded,
          label: _copied ? l10n.aiChatActionCopied : l10n.aiChatActionCopy,
          color: _copied ? c.actionDone : c.actionForeground,
          onTap: _copy,
        ),
        if (widget.onEdit != null)
          _ActionButton(
            icon: Icons.edit_outlined,
            label: l10n.aiChatActionEdit,
            color: c.actionForeground,
            onTap: widget.onEdit!,
          ),
        if (widget.onRegenerate != null)
          _ActionButton(
            icon: Icons.refresh_rounded,
            label: l10n.aiChatActionRegenerate,
            color: c.actionForeground,
            onTap: widget.onRegenerate!,
          ),
        if (widget.detailsFor != null)
          _MoreMenu(
            colors: c,
            message: widget.detailsFor!,
            question: widget.question,
            copyText: widget.copyText,
          ),
      ],
    );
  }
}

/// 操作行の1つのボタン。見た目は小さく(アイコン16)、押せる範囲は広く(36×36)。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

enum _MoreChoice { details, report }

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.colors,
    required this.message,
    required this.question,
    required this.copyText,
  });

  final ChatColors colors;
  final LocalChatMessage message;
  final String? question;
  final String copyText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = colors;
    final itemStyle = TextStyle(color: c.actionForegroundStrong, fontSize: 14);
    return Semantics(
      button: true,
      label: l10n.aiChatActionMore,
      child: PopupMenuButton<_MoreChoice>(
        tooltip: l10n.aiChatActionMore,
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: c.actionForeground,
        ),
        color: c.menuBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.menuBorder),
        ),
        constraints: const BoxConstraints(minWidth: 180),
        onSelected: (choice) {
          switch (choice) {
            case _MoreChoice.details:
              unawaited(
                showChatMessageDetailsSheet(
                  context,
                  colors: c,
                  message: message.message,
                ),
              );
            case _MoreChoice.report:
              unawaited(
                showChatReportSheet(
                  context,
                  colors: c,
                  message: message.message,
                  question: question,
                  replyText: copyText,
                ),
              );
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _MoreChoice.details,
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: c.actionForeground,
                ),
                const SizedBox(width: 10),
                Text(l10n.aiChatActionDetails, style: itemStyle),
              ],
            ),
          ),
          PopupMenuItem(
            value: _MoreChoice.report,
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 16, color: c.actionForeground),
                const SizedBox(width: 10),
                Text(l10n.aiChatActionReport, style: itemStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 回答の詳細: いつ送ったか・何クレジットかかったか・出典の数。原価や内部の振り分けは出さない。
Future<void> showChatMessageDetailsSheet(
  BuildContext context, {
  required ChatColors colors,
  required ChatMessage message,
}) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toString();
  final credits = message.creditsCharged;
  final sentAt = TimeOfDay.fromDateTime(message.createdAt.toLocal());
  final date = MaterialLocalizations.of(
    context,
  ).formatShortDate(message.createdAt.toLocal());
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(sentAt, alwaysUse24HourFormat: true);
  final creditsText = credits > 0
      ? l10n.aiChatCreditsUsed(_formatCredits(credits, locale))
      : l10n.aiChatDetailNoCharge;

  Widget row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(color: colors.actionForeground, fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: colors.text, fontSize: 14),
          ),
        ),
      ],
    ),
  );

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.menuBackground,
    shape: kSheetShape,
    builder: (_) => withSheetHandle(
      handleColor: colors.actionForeground.withValues(alpha: .4),
      SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiChatActionDetails,
              style: TextStyle(
                color: colors.strongText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            row(l10n.aiChatDetailSentAt, '$date $time'),
            if (message.status == ChatMessageStatus.stopped)
              row(l10n.aiChatDetailStatus, l10n.aiChatDetailStatusStopped),
            row(l10n.aiChatDetailCredits, creditsText),
            row(
              l10n.aiChatDetailSources,
              l10n.aiChatDetailSourcesCount('${message.citations.length}'),
            ),
          ],
        ),
      ),
    ),
    ),
  );
}

/// クレジットの表示(小数2桁まで。整数ならそのまま)。
String _formatCredits(double credits, String locale) {
  final rounded = (credits * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}
