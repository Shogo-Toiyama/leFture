// lib/presentation/widgets/ai_chat/ai_chat_entry_button.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_page_context.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// AIチャットを開く、右下の丸いボタン。宇宙の画面では金、紙の画面では深い琥珀色。
///
/// 画面の右下にすでにボタンがあるときは、その右隣に置く。講義ページのように文字の上に
/// 重なる画面では[translucent]にして、下の文字がうっすら見えるようにする。
class AiChatEntryButton extends ConsumerWidget {
  const AiChatEntryButton({
    super.key,
    this.world = ChatWorld.universe,
    this.translucent = false,
  });

  final ChatWorld world;
  final bool translucent;

  static const size = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ChatColors.of(world);
    final label = AppLocalizations.of(context).cardSelectionToolbarAskLabel;
    final fill = c.accent;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: translucent ? fill.withValues(alpha: .62) : fill,
          elevation: translucent ? 2 : 6,
          shadowColor: Colors.black.withValues(alpha: translucent ? .2 : .4),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => unawaited(openAiChat(context, ref)),
            child: SizedBox(
              width: size,
              height: size,
              // 塗りつぶしではなく、白い縁だけの吹き出し
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 24,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
