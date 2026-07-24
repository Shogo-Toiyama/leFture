// lib/presentation/widgets/sticky_topic_header.dart

import 'package:flutter/material.dart';
import 'package:lefture/core/utils/topic_color_utils.dart';
import 'package:lefture/domain/entities/lecture_topic.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

/// トランスクリプト画面上部に常時固定表示され、タップで目次メニューがスライド展開するヘッダーウィジェット。
class StickyTopicHeader extends StatefulWidget {
  const StickyTopicHeader({
    super.key,
    required this.topics,
    required this.currentTopic,
    required this.onTopicSelected,
  });

  final List<LectureTopic> topics;
  final LectureTopic? currentTopic;
  final ValueChanged<LectureTopic> onTopicSelected;

  @override
  State<StickyTopicHeader> createState() => _StickyTopicHeaderState();
}

class _StickyTopicHeaderState extends State<StickyTopicHeader> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.topics.isEmpty || widget.currentTopic == null) {
      return const SizedBox.shrink();
    }

    final currentTopic = widget.currentTopic!;
    final currentIndex = widget.topics.indexOf(currentTopic);
    final safeIndex = currentIndex >= 0 ? currentIndex : 0;
    final totalTopics = widget.topics.length;
    final topicColor = TopicColorUtils.getTopicColor(safeIndex, totalTopics);
    final topicBgColor = TopicColorUtils.getTopicBackgroundColor(
      safeIndex,
      totalTopics,
      alpha: 0.12,
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.paper.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.paper.line, width: 1.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 固定ヘッダーバー ──────────────────────────────────────
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              color: topicBgColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  // トピック番号バッジ
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: topicColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Topic ${currentTopic.index}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // トピックタイトル
                  Expanded(
                    child: Text(
                      currentTopic.displayTitle,
                      style: TextStyle(
                        color: AppColors.paper.textInk,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // 開閉アイコン
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.paper.textPencil,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── スライドダウン目次メニュー ─────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Container(
              constraints: const BoxConstraints(maxHeight: 260),
              color: AppColors.paper.background,
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: widget.topics.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.paper.line,
                ),
                itemBuilder: (context, index) {
                  final topic = widget.topics[index];
                  final isSelected = topic.id == currentTopic.id;
                  final itemColor = TopicColorUtils.getTopicColor(
                    index,
                    totalTopics,
                  );

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _isExpanded = false;
                      });
                      widget.onTopicSelected(topic);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: isSelected
                          ? itemColor.withValues(alpha: 0.12)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          // トピックカラー縦ライン
                          Container(
                            width: 3.5,
                            height: 16,
                            decoration: BoxDecoration(
                              color: itemColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // トピック番号
                          Text(
                            'Topic ${topic.index}',
                            style: TextStyle(
                              color: isSelected
                                  ? itemColor
                                  : AppColors.paper.textPencil,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // トピック名
                          Expanded(
                            child: Text(
                              topic.displayTitle,
                              style: TextStyle(
                                color: AppColors.paper.textInk,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle_rounded,
                              color: itemColor,
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
