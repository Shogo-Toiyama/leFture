// lib/presentation/widgets/ai_chat/chat_report_sheet.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/infrastructure/chat/chat_repository.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';

/// 報告に添える本文の上限(管理者宛のメールが長くなりすぎないように。webappのReportSheetと同じ)。
const _maxAttachedChars = 4000;
const _maxMessageChars = 2000;

/// AIの回答の「問題を報告」シート。お問い合わせと同じ /support/submit に、同じ形式で送る
/// (受付コード・確認メール・管理者への通知もお問い合わせと同じ)。
/// どのメッセージについてかは device_info.report に入る。
///
/// Google Playの「AI生成コンテンツ」ポリシーが、アプリ内でAIの返答を報告できる手段を求めているため必須。
Future<void> showChatReportSheet(
  BuildContext context, {
  required ChatColors colors,
  required ChatMessage message,
  String? question,
  required String replyText,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.menuBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ChatReportSheet(
      colors: colors,
      message: message,
      question: question,
      replyText: replyText,
    ),
  );
}

enum _ReportState { editing, sending, sent, failed }

/// 選べる種類(先頭が初期値)。webappの categories と同じ並び。
const _categories = [
  'inappropriate',
  'incorrect',
  'bug',
  'feature_request',
  'other',
];

class _ChatReportSheet extends ConsumerStatefulWidget {
  const _ChatReportSheet({
    required this.colors,
    required this.message,
    required this.question,
    required this.replyText,
  });

  final ChatColors colors;
  final ChatMessage message;
  final String? question;
  final String replyText;

  @override
  ConsumerState<_ChatReportSheet> createState() => _ChatReportSheetState();
}

class _ChatReportSheetState extends ConsumerState<_ChatReportSheet> {
  final _controller = TextEditingController();
  String _category = _categories.first;
  bool _attach = true;
  _ReportState _state = _ReportState.editing;
  String _ticketCode = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _categoryLabel(AppLocalizations l, String c) => switch (c) {
    'inappropriate' => l.aiReportCategoryInappropriate,
    'incorrect' => l.aiReportCategoryIncorrect,
    'bug' => l.aiReportCategoryBug,
    'feature_request' => l.aiReportCategoryFeedback,
    'account' => l.aiReportCategoryAccount,
    _ => l.aiReportCategoryOther,
  };

  /// 添える質問と回答(質問の中の資料の印は、中身を送らないよう「[material]」にする)。
  List<({String heading, String text})> _sections(AppLocalizations l) => [
    if (widget.question != null && widget.question!.trim().isNotEmpty)
      (
        heading: l.aiChatReportQuestion,
        text: widget.question!.replaceAll(chatMentionPattern, '[material]'),
      ),
    (heading: l.aiChatReportReply, text: widget.replyText),
  ];

  Future<void> _submit(AppLocalizations l) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _state == _ReportState.sending) return;
    setState(() => _state = _ReportState.sending);
    try {
      final m = widget.message;
      final code = await ref
          .read(chatRepositoryProvider)
          .submitSupportReport(
            category: _category,
            message: text,
            report: {
              'source': 'ai_chat',
              'thread_id': m.threadId,
              'message_id': m.id,
              'message_status': m.status.name,
              'message_sent_at': m.createdAt.toUtc().toIso8601String(),
              'credits_charged_micro': m.creditsChargedMicro,
              if (_attach)
                'attached': [
                  for (final s in _sections(l))
                    {
                      'heading': s.heading,
                      'text': s.text.length > _maxAttachedChars
                          ? s.text.substring(0, _maxAttachedChars)
                          : s.text,
                    },
                ],
            },
          );
      if (!mounted) return;
      setState(() {
        _ticketCode = code;
        _state = _ReportState.sent;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _ReportState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.colors;
    final sending = _state == _ReportState.sending;
    final canSend = _controller.text.trim().isNotEmpty && !sending;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: _state == _ReportState.sent
              ? _sent(l, c)
              : _form(l, c, canSend, sending),
        ),
      ),
    );
  }

  Widget _title(String text, ChatColors c) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: c.strongText,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      IconButton(
        tooltip: AppLocalizations.of(context).aiChatClose,
        icon: Icon(Icons.close_rounded, color: c.actionForeground),
        onPressed: _state == _ReportState.sending
            ? null
            : () => Navigator.of(context).pop(),
      ),
    ],
  );

  Widget _sent(AppLocalizations l, ChatColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(l.aiReportSentTitle, c),
      const SizedBox(height: 6),
      Text(
        l.aiReportSentBody(_ticketCode),
        style: TextStyle(color: c.text, fontSize: 14, height: 1.6),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.aiChatClose),
        ),
      ),
    ],
  );

  Widget _form(AppLocalizations l, ChatColors c, bool canSend, bool sending) {
    final sections = _sections(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(l.aiChatActionReport, c),
        const SizedBox(height: 4),
        Text(
          l.aiReportCategoryLabel,
          style: TextStyle(color: c.actionForeground, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cat in _categories)
              ChoiceChip(
                label: Text(_categoryLabel(l, cat)),
                selected: _category == cat,
                onSelected: sending
                    ? null
                    : (_) => setState(() => _category = cat),
                selectedColor: c.citeBackground,
                backgroundColor: Colors.transparent,
                side: BorderSide(
                  color: _category == cat ? c.accent : c.menuBorder,
                ),
                labelStyle: TextStyle(
                  color: _category == cat ? c.accent : c.text,
                  fontSize: 13,
                ),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l.aiReportMessageLabel,
          style: TextStyle(color: c.actionForeground, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          enabled: !sending,
          maxLength: _maxMessageChars,
          minLines: 4,
          maxLines: 7,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: c.text, fontSize: 14.5),
          decoration: InputDecoration(
            hintText: l.aiReportMessagePlaceholder,
            hintStyle: TextStyle(color: c.hintText),
            filled: true,
            fillColor: c.inputBackground,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.accent, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.inputBorder),
            ),
            counterStyle: TextStyle(color: c.hintText),
          ),
        ),
        CheckboxListTile(
          value: _attach,
          onChanged: sending
              ? null
              : (v) => setState(() => _attach = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: c.accent,
          title: Text(
            l.aiChatReportAttach,
            style: TextStyle(color: c.text, fontSize: 14),
          ),
        ),
        if (_attach)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              iconColor: c.actionForeground,
              collapsedIconColor: c.actionForeground,
              title: Text(
                l.aiReportAttachPreview,
                style: TextStyle(color: c.actionForeground, fontSize: 13),
              ),
              children: [
                for (final s in sections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.heading,
                          style: TextStyle(
                            color: c.strongText,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.text.length > _maxAttachedChars
                              ? s.text.substring(0, _maxAttachedChars)
                              : s.text,
                          style: TextStyle(
                            color: c.actionForeground,
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          l.aiReportAutoNote,
          style: TextStyle(color: c.hintText, fontSize: 12, height: 1.5),
        ),
        if (_state == _ReportState.failed) ...[
          const SizedBox(height: 8),
          Text(
            l.aiReportFailed,
            style: TextStyle(color: c.danger, fontSize: 13),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: canSend ? () => _submit(l) : null,
            child: Text(sending ? l.aiReportSending : l.aiReportSubmit),
          ),
        ),
      ],
    );
  }
}
