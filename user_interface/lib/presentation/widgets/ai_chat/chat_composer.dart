// lib/presentation/widgets/ai_chat/chat_composer.dart
import 'package:flutter/material.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';

/// 入力欄に文字を入れる依頼(質問の候補を押した・編集を始めた・送れなかった文を戻す)。
/// [nonce]が変わるたびに、同じ文字でも入れ直す。
class ChatPrefill {
  const ChatPrefill({required this.text, required this.nonce});

  final String text;
  final int nonce;
}

/// 会話の下の入力欄。
///
/// スマホではEnterは改行で、送るのは送信ボタンだけ(日本語の変換の確定でEnterを押して、
/// 送ってしまう事故を避けるため。webappはEnterで送信)。
/// 生成中は送信ボタンが停止ボタンになる。
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.colors,
    required this.onSend,
    required this.placeholder,
    this.onStop,
    this.stopping = false,
    this.disabled = false,
    this.prefill,
    this.editingLabel,
    this.onCancelEdit,
    this.selectedText,
    this.onClearSelectedText,
    this.lectureTitle,
    this.onDetachLecture,
  });

  final ChatColors colors;

  /// 送る。空・空白だけのときは呼ばれない。
  final void Function(String content) onSend;
  final String placeholder;

  /// 渡されていれば(=生成中)、送信ボタンの代わりに停止ボタンを出す。
  final VoidCallback? onStop;
  final bool stopping;

  /// 送れない状態(選択した文章が長すぎるなど)。
  final bool disabled;
  final ChatPrefill? prefill;

  /// 編集中の案内(「このメッセージを直しています…」)と、やめるボタン。
  final String? editingLabel;
  final VoidCallback? onCancelEdit;

  /// 「Ask」・返信で添える選択した文章。1回の送信にだけ添える。
  final String? selectedText;
  final VoidCallback? onClearSelectedText;

  /// 話題にしている講義(外せる)。
  final String? lectureTitle;
  final VoidCallback? onDetachLecture;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _applyPrefill();
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    if (widget.prefill != null && widget.prefill?.nonce != old.prefill?.nonce) {
      _applyPrefill();
    }
  }

  void _applyPrefill() {
    final p = widget.prefill;
    if (p == null) return;
    _controller.value = TextEditingValue(
      text: p.text,
      selection: TextSelection.collapsed(offset: p.text.length),
    );
    if (p.text.isNotEmpty) _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSend => _controller.text.trim().isNotEmpty && !widget.disabled;

  void _send() {
    if (!_canSend) return;
    final text = _controller.text.trim();
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.colors;
    final generating = widget.onStop != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editingLabel != null)
          _Bar(
            colors: c,
            icon: Icons.edit_outlined,
            text: widget.editingLabel!,
            tooltip: l10n.aiChatEditCancel,
            onClose: widget.onCancelEdit,
            tint: c.accent,
          ),
        if (widget.selectedText != null)
          _Bar(
            colors: c,
            icon: Icons.format_quote_rounded,
            text: widget.selectedText!,
            maxLines: 2,
            tooltip: l10n.aiChatDismiss,
            onClose: widget.onClearSelectedText,
            tint: c.quoteBorder,
          ),
        if (widget.lectureTitle != null)
          _Bar(
            colors: c,
            icon: Icons.menu_book_outlined,
            text: l10n.aiChatAttachedLecture(widget.lectureTitle!),
            tooltip: l10n.aiChatDismiss,
            onClose: widget.onDetachLecture,
            tint: c.accent,
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          decoration: BoxDecoration(
            color: c.inputBackground,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.inputBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  maxLength: chatMaxMessageChars,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(color: c.text, fontSize: 15, height: 1.5),
                  cursorColor: c.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: false,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintText: widget.placeholder,
                    hintStyle: TextStyle(color: c.hintText),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: generating
                    ? _RoundButton(
                        icon: Icons.stop_rounded,
                        color: c.accent,
                        tooltip: widget.stopping
                            ? l10n.aiChatStopping
                            : l10n.aiChatStop,
                        onTap: widget.stopping ? null : widget.onStop,
                      )
                    : _RoundButton(
                        icon: Icons.arrow_upward_rounded,
                        color: c.accent,
                        tooltip: l10n.aiChatSend,
                        onTap: _canSend ? _send : null,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: enabled ? .9 : .28),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Colors.white.withValues(alpha: enabled ? 1 : .7),
          ),
        ),
      ),
    );
  }
}

/// 入力欄の上に出す細い帯(編集中・選択した文章・話題の講義)。
class _Bar extends StatelessWidget {
  const _Bar({
    required this.colors,
    required this.icon,
    required this.text,
    required this.tint,
    required this.tooltip,
    this.maxLines = 1,
    this.onClose,
  });

  final ChatColors colors;
  final IconData icon;
  final String text;
  final Color tint;
  final String tooltip;
  final int maxLines;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.text, fontSize: 12.5, height: 1.4),
            ),
          ),
          if (onClose != null)
            InkResponse(
              onTap: onClose,
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colors.actionForeground,
                  semanticLabel: tooltip,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
