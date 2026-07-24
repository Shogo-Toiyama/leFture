// lib/presentation/widgets/ai_chat_sheet.dart
//
// アプリ内のどこからでも呼び出せる、講義に関するAIチャットのボトムシート。
// ドラッグで高さを変えられる(DraggableScrollableSheet)。
// 現時点では見た目確認用のハリボテ: 会話はダミーで、送信しても
// 固定のプレビュー文言が返るだけ。実際のAI応答は未実装。

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';

/// 講義に関するAIチャットのボトムシートを開く。
Future<void> showAiChatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // つまみ(ハンドル)だけで高さを操作する自前のドラッグ実装を使うため、
    // BottomSheet標準のドラッグ(コンテンツ全体をドラッグして閉じる)は無効化する。
    enableDrag: false,
    builder: (sheetContext) => const _AiChatSheet(),
  );
}

class _ChatMessage {
  const _ChatMessage({required this.isUser, required this.text});
  final bool isUser;
  final String text;
}

// ハリボテ用のダミー会話(ユーザーは短め、AIはまあまあ長めの返答)。
const _fakeConversation = <_ChatMessage>[
  _ChatMessage(
    isUser: true,
    text: "What's the difference between world space and camera space again?",
  ),
  _ChatMessage(
    isUser: false,
    text: "Great question — **world space** is the single global coordinate system that "
        "every object in the scene shares, like a shared map. **Camera space** is that same "
        "scene re-expressed relative to the camera's position and orientation, as if the "
        "camera were sitting at the origin looking down one axis.\n\n"
        "We make that switch so the next step — projection — can always assume the camera "
        "is at a fixed, known spot.",
  ),
  _ChatMessage(isUser: true, text: 'So projection happens right after that?'),
  _ChatMessage(
    isUser: false,
    text: "Exactly. Once everything's in camera space, projection flattens that 3D scene "
        "down onto a 2D image plane — basically simulating what a camera lens or your eye "
        "would see. There are two common flavors:\n\n"
        "- **Perspective projection** — makes far-away objects look smaller, like real life\n"
        "- **Orthographic projection** — keeps parallel lines parallel regardless of "
        "distance, common in CAD and some 2D-style games\n\n"
        "Most game engines default to perspective for anything meant to feel 3D.",
  ),
  _ChatMessage(isUser: true, text: 'Got it, thanks!'),
  _ChatMessage(
    isUser: false,
    text: "Anytime! Want me to pull up the exact slide where the professor covers this, or "
        "quiz you with a couple of practice questions once the lecture wraps up?",
  ),
];

class _AiChatSheet extends HookWidget {
  const _AiChatSheet();

  // 2段階のスナップ位置(初期/最大)+ そこから引き下げると閉じる、他のシートと
  // 揃えた3状態の挙動。ドラッグ中は指に1:1で追従し、離した位置に応じて
  // 最寄りのスナップ位置(または閉じる)へアニメーションする。
  static const double _initialHeightFraction = 0.55;
  static const double _maxHeightFraction = 0.92;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final messages = useState<List<_ChatMessage>>(_fakeConversation);
    final inputCtl = useTextEditingController();
    final heightFraction = useState<double>(_initialHeightFraction);
    final isDragging = useState<bool>(false);
    final screenHeight = MediaQuery.of(context).size.height;

    void send() {
      final text = inputCtl.text.trim();
      if (text.isEmpty) return;
      messages.value = [...messages.value, _ChatMessage(isUser: true, text: text)];
      inputCtl.clear();
      Future.delayed(const Duration(milliseconds: 500), () {
        messages.value = [
          ...messages.value,
          _ChatMessage(
            isUser: false,
            text: l10n.aiChatSheetPreviewFallback,
          ),
        ];
      });
    }

    void onHeaderDragEnd(DragEndDetails details) {
      isDragging.value = false;
      final current = heightFraction.value;
      // 「閉じる」⇔「初期位置」の境界、「初期位置」⇔「最大」の境界の中間点で
      // どちらに寄っているかを判定してスナップする。
      final lowMid = _initialHeightFraction / 2;
      final highMid = (_initialHeightFraction + _maxHeightFraction) / 2;

      if (current < lowMid) {
        Navigator.of(context).pop();
      } else if (current < highMid) {
        heightFraction.value = _initialHeightFraction;
      } else {
        heightFraction.value = _maxHeightFraction;
      }
    }

    // reverse:true にして、逆順(最新が先頭)のリストを渡す。これで常に
    // 一番下(=最新の会話)を向いた状態になり、上にスクロールした場合だけ
    // 過去の会話に遡る。シートの高さ自体はヘッダーのドラッグでのみ変わる。
    final reversedMessages = messages.value.reversed.toList();

    return AnimatedContainer(
      duration: isDragging.value ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      height: screenHeight * heightFraction.value,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1C2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ヘッダー全体(つまみ+タイトル行)をドラッグ対象にする。
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => isDragging.value = true,
            onVerticalDragUpdate: (details) {
              heightFraction.value = (heightFraction.value - details.delta.dy / screenHeight)
                  .clamp(0.0, _maxHeightFraction);
            },
            onVerticalDragEnd: onHeaderDragEnd,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 14, bottom: 10),
                  alignment: Alignment.center,
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.universe.glassBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 18, color: AppColors.starGold),
                      const SizedBox(width: 8),
                      Text(
                        l10n.aiChatSheetTitle,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: AppColors.universe.textComet),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.universe.glassBorder),
          Expanded(
            child: ListView.separated(
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount: reversedMessages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _ChatBubble(message: reversedMessages[i]),
            ),
          ),
          Divider(height: 1, color: AppColors.universe.glassBorder),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).viewInsets.bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputCtl,
                    style: TextStyle(color: AppColors.universe.textStarlight),
                    decoration: InputDecoration(
                      hintText: l10n.aiChatSheetInputHint,
                      hintStyle: TextStyle(color: AppColors.universe.textComet),
                      filled: true,
                      fillColor: AppColors.universe.glassWhiteLow,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: AppColors.universe.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: AppColors.universe.glassBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: AppColors.starGold),
                      ),
                    ),
                    onSubmitted: (_) => send(),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.starGold,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: send,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
                    ),
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    // ユーザーの発言は今まで通り吹き出しで表示する。
    if (message.isUser) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.starGold.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                ),
                border: Border.all(color: AppColors.starGold.withValues(alpha: 0.4)),
              ),
              child: Text(
                message.text,
                style: TextStyle(color: AppColors.universe.textStarlight, fontSize: 13.5, height: 1.4),
              ),
            ),
          ),
        ],
      );
    }

    // AIの回答は吹き出しに入れず、Markdownとしてそのまま流し込む。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: AppColors.starGold.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.auto_awesome, size: 14, color: AppColors.starGold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MarkdownBody(
            data: message.text,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: TextStyle(color: AppColors.universe.textStarlight, fontSize: 13.5, height: 1.5),
              pPadding: const EdgeInsets.only(bottom: 6),
              strong: TextStyle(color: AppColors.universe.textStarlight, fontWeight: FontWeight.bold),
              em: TextStyle(color: AppColors.universe.textStarlight, fontStyle: FontStyle.italic),
              listBullet: TextStyle(color: AppColors.universe.textComet, fontSize: 13.5),
              listIndent: 18,
              h1: TextStyle(color: AppColors.universe.textStarlight, fontSize: 18, fontWeight: FontWeight.bold),
              h2: TextStyle(color: AppColors.universe.textStarlight, fontSize: 16, fontWeight: FontWeight.bold),
              h3: TextStyle(color: AppColors.universe.textStarlight, fontSize: 14, fontWeight: FontWeight.bold),
              code: TextStyle(
                color: AppColors.starGold,
                backgroundColor: AppColors.universe.glassWhiteLow,
                fontSize: 12.5,
              ),
              codeblockDecoration: BoxDecoration(
                color: AppColors.universe.glassWhiteLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.universe.glassBorder),
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.starGold, width: 3)),
              ),
              blockquotePadding: const EdgeInsets.only(left: 12),
              a: TextStyle(color: AppColors.starGold, decoration: TextDecoration.underline),
            ),
          ),
        ),
      ],
    );
  }
}
