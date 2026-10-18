// lib/presentation/widgets/ai_chat/chat_thread_list_view.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lefture/application/chat/chat_threads.dart';
import 'package:lefture/domain/entities/chat.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';

/// 会話の履歴(webappのChatThreadList)。端末のキャッシュにある前回の一覧がすぐ出て、
/// 開いたあとサーバーの最新に追いつく。名前の変更・削除ができる。
class ChatThreadListView extends ConsumerStatefulWidget {
  const ChatThreadListView({
    super.key,
    required this.colors,
    required this.onSelect,
    this.activeThreadId,
    this.onDeleted,
  });

  final ChatColors colors;
  final String? activeThreadId;
  final void Function(String threadId) onSelect;

  /// 会話を削除した(今開いていた会話なら、呼び出し側が新しい会話に切り替える)。
  final void Function(String threadId)? onDeleted;

  @override
  ConsumerState<ChatThreadListView> createState() => _ChatThreadListViewState();
}

class _ChatThreadListViewState extends ConsumerState<ChatThreadListView> {
  String? _editingId;
  final _title = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 開いたら、サーバーの最新に追いつく。失敗しても前回の一覧は残る
    unawaited(
      Future(() async {
        try {
          await ref.read(chatThreadActionsProvider.notifier).refresh();
        } catch (_) {}
      }),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String _time(BuildContext context, DateTime at) {
    final locale = Localizations.localeOf(context).toString();
    final local = at.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay
        ? DateFormat.jm(locale).format(local)
        : DateFormat.MMMd(locale).format(local);
  }

  Future<void> _commitRename(String threadId) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _editingId = null);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(chatThreadActionsProvider.notifier)
          .rename(threadId, title);
      if (mounted) setState(() => _editingId = null);
    } catch (_) {
      // 名前を変えられなかった: 編集は閉じずに、もう一度押せるようにする
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(ChatThread thread) async {
    final l = AppLocalizations.of(context);
    final c = widget.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.menuBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l.aiChatDeleteConfirmTitle,
          style: TextStyle(color: c.strongText, fontSize: 17),
        ),
        content: Text(
          l.aiChatDeleteConfirmMessage,
          style: TextStyle(color: c.text, fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              MaterialLocalizations.of(context).cancelButtonLabel,
              style: TextStyle(color: c.actionForeground),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.aiChatDelete, style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(chatThreadActionsProvider.notifier).delete(thread.id);
      widget.onDeleted?.call(thread.id);
    } catch (_) {
      // 消せなかった: 一覧はそのまま残る
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = widget.colors;
    final threads = ref.watch(chatThreadListProvider);
    return threads.when(
      loading: () => _skeleton(c),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l.aiChatThreadsEmpty,
          style: TextStyle(color: c.stageText, fontSize: 13.5),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l.aiChatThreadsEmpty,
              style: TextStyle(color: c.stageText, fontSize: 13.5, height: 1.6),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (context, i) => _row(context, list[i]),
        );
      },
    );
  }

  Widget _skeleton(ChatColors c) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            height: 52,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: c.chipBackground,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
      ],
    ),
  );

  Widget _row(BuildContext context, ChatThread thread) {
    final l = AppLocalizations.of(context);
    final c = widget.colors;
    final active = thread.id == widget.activeThreadId;
    final title = (thread.title?.trim().isNotEmpty ?? false)
        ? thread.title!
        : l.aiChatThreadUntitled;
    final decoration = BoxDecoration(
      color: active ? c.accent.withValues(alpha: .09) : null,
      borderRadius: BorderRadius.circular(12),
    );

    if (_editingId == thread.id) {
      return Container(
        decoration: decoration,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _title,
                autofocus: true,
                maxLength: 100,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_commitRename(thread.id)),
                style: TextStyle(color: c.text, fontSize: 14.5),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: InputBorder.none,
                  hintText: l.aiChatRename,
                  hintStyle: TextStyle(color: c.hintText),
                ),
              ),
            ),
            IconButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(_commitRename(thread.id)),
              tooltip: MaterialLocalizations.of(context).okButtonLabel,
              icon: Icon(Icons.check_rounded, size: 19, color: c.accent),
            ),
            IconButton(
              onPressed: () => setState(() => _editingId = null),
              tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
              icon: Icon(
                Icons.close_rounded,
                size: 19,
                color: c.actionForeground,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: decoration,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onSelect(thread.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 17,
                      color: c.actionForeground,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.actionForegroundStrong,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            _time(context, thread.lastMessageAt),
                            style: TextStyle(
                              color: c.stageText,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              _title.text = thread.title ?? '';
              setState(() => _editingId = thread.id);
            },
            tooltip: l.aiChatRename,
            icon: Icon(
              Icons.edit_outlined,
              size: 17,
              color: c.actionForeground,
            ),
          ),
          IconButton(
            onPressed: () => unawaited(_confirmDelete(thread)),
            tooltip: l.aiChatDelete,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: c.actionForeground,
            ),
          ),
        ],
      ),
    );
  }
}
