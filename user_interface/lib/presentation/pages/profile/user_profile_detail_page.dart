// lib/presentation/pages/profile/user_profile_detail_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/self_portrait/self_portrait_controller.dart';
import 'package:lefture/core/utils/self_portrait_format.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/confirm_tray_sheet.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/cover_edit_sheet.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/item_detail_sheet.dart';
import 'package:lefture/presentation/pages/profile/self_portrait/sp_common.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/ai_chat/ai_chat_sheet.dart';
import 'package:lefture/presentation/widgets/ai_chat/chat_world.dart';

/// 閉じたタイルに見せておく件数
const _tilePeek = 3;

enum _Tab { trait, record }

/// 自分像のページ(webappの ProfilePage)。上から「いまのわたし」(表紙。メイン) → 区切り →
/// 最近わかったこと → 確認してほしいこと → 自分像/記録のタブ。
class UserProfileDetailPage extends HookConsumerWidget {
  const UserProfileDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final async = ref.watch(selfPortraitControllerProvider);
    final data = async.asData?.value;
    final tab = useState(_Tab.trait);
    final expanded = useState<Set<String>>({});

    // 「新しい」印は、このページを1回開いたら消す(今回の表示では残しておく)
    final markedSeen = useRef(false);
    useEffect(() {
      if (data == null || markedSeen.value) return null;
      markedSeen.value = true;
      final ids = [
        for (final i in data.items)
          if (i.isNew && i.isActive) i.id,
      ];
      unawaited(
        ref.read(selfPortraitControllerProvider.notifier).markSeen(ids),
      );
      return null;
    }, [data != null]);

    final categoriesById = {
      for (final c in data?.categories ?? const <ProfileCategory>[]) c.id: c,
    };
    final itemsById = {
      for (final i in data?.items ?? const <ProfileItem>[]) i.id: i,
    };

    void openChat(String threadId) {
      unawaited(
        showAiChatSheet(
          context,
          world: ChatWorld.universe,
          threadId: threadId,
        ),
      );
    }

    void openItem(ProfileItem item) {
      unawaited(
        showItemDetailSheet(
          context,
          item: item,
          categoryLabel: categoryPath(l, categoriesById, item.categoryId),
          onOpenChat: openChat,
        ),
      );
    }

    final pending = data?.pending ?? const <ProfileItem>[];
    final proposals = data?.proposals ?? const <CoverProposal>[];
    final confirmCount = pending.length + proposals.length;
    final active = data?.active ?? const <ProfileItem>[];
    final traitCount = active.where((i) => i.kind == 'trait').length;
    final recordCount = active.where((i) => i.kind == 'record').length;
    final kind = tab.value == _Tab.trait ? 'trait' : 'record';

    return Scaffold(
      backgroundColor: AppColors.universe.voidBackground,
      appBar: AppBar(
        backgroundColor: AppColors.universe.voidBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: spText,
            size: 18,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l.selfPortraitPageTitle,
          style: const TextStyle(
            color: spText,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: async.isLoading && data == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.starGold),
            )
          : RefreshIndicator(
              color: AppColors.starGold,
              onRefresh: () async {
                try {
                  await ref
                      .read(selfPortraitControllerProvider.notifier)
                      .refresh();
                } catch (_) {}
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  Text(
                    l.selfPortraitPageSubtitle,
                    style: TextStyle(color: spMuted, fontSize: 13.5),
                  ),
                  if (async.hasError && data == null)
                    SpErrorText(l.selfPortraitLoadError),

                  // ── いまのわたし(メイン) ──
                  SpSectionLabel(
                    l.selfPortraitNowSection,
                    color: AppColors.starGold,
                  ),
                  for (final field in CoverField.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CoverTile(
                        field: field,
                        value: data?.cover[field],
                      ),
                    ),

                  // ── ここから下はサブ: 会話からわかってきたこと ──
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Divider(color: spMuted.withValues(alpha: .3)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          l.selfPortraitDividerCaption,
                          style: TextStyle(color: spMuted, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Divider(color: spMuted.withValues(alpha: .3)),
                      ),
                    ],
                  ),

                  if (data != null && data.recent.isNotEmpty) ...[
                    SpSectionLabel(l.selfPortraitRecentSection),
                    for (final r in data.recent)
                      if (itemsById[r.itemId] case final item?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _RecentCard(
                            recent: r,
                            item: item,
                            categoryLabel: categoryPath(
                              l,
                              categoriesById,
                              item.categoryId,
                            ),
                            locale: locale,
                            onTap: () => openItem(item),
                          ),
                        ),
                  ],

                  if (confirmCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _ConfirmBanner(
                        count: confirmCount,
                        sub: [
                          if (pending.isNotEmpty)
                            l.selfPortraitConfirmPendingCount('${pending.length}'),
                          for (final p in proposals)
                            l.selfPortraitProposalTitle(
                              coverFieldLabel(l, p.field),
                            ),
                        ].join(' · '),
                        onTap: () => unawaited(showConfirmTraySheet(context)),
                      ),
                    ),

                  // ── 自分像 / 記録 のタブ ──
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      _TabButton(
                        label: l.selfPortraitTabTraits,
                        count: traitCount,
                        selected: tab.value == _Tab.trait,
                        onTap: () => tab.value = _Tab.trait,
                      ),
                      const SizedBox(width: 8),
                      _TabButton(
                        label: l.selfPortraitTabRecords,
                        count: recordCount,
                        selected: tab.value == _Tab.record,
                        onTap: () => tab.value = _Tab.record,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CategoryTiles(
                    kind: kind,
                    items: [
                      for (final i in active)
                        if (i.kind == kind) i,
                    ],
                    categories: data?.categories ?? const [],
                    locale: locale,
                    expanded: expanded.value,
                    onToggle: (key) {
                      final next = {...expanded.value};
                      if (!next.remove(key)) next.add(key);
                      expanded.value = next;
                    },
                    onOpenItem: openItem,
                  ),

                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text(
                      l.selfPortraitFootnote,
                      style: TextStyle(
                        color: spMuted.withValues(alpha: .85),
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.field, required this.value});

  final CoverField field;
  final CoverValue? value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = (value?.text ?? '').trim();
    return SpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                coverFieldLabel(l, field).toUpperCase(),
                style: const TextStyle(
                  color: AppColors.starGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              if (value?.writtenByAi == true && text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: l.selfPortraitWrittenFromChats,
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: AppColors.starGold,
                    ),
                  ),
                ),
              const Spacer(),
              InkResponse(
                onTap: () => unawaited(
                  showCoverEditSheet(
                    context,
                    field: field,
                    initialText: value?.text,
                  ),
                ),
                radius: 20,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: spMuted,
                    semanticLabel:
                        '${l.selfPortraitEdit}: ${coverFieldLabel(l, field)}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text.isEmpty ? coverFieldEmpty(l, field) : text,
            style: TextStyle(
              color: text.isEmpty ? spMuted.withValues(alpha: .7) : spText,
              fontSize: 14.5,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.recent,
    required this.item,
    required this.categoryLabel,
    required this.locale,
    required this.onTap,
  });

  final RecentItem recent;
  final ProfileItem item;
  final String categoryLabel;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SpCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '$categoryLabel · ${shortDate(item.changedAt, locale)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: spMuted, fontSize: 12),
                ),
              ),
              if (item.isNew) ...[const SizedBox(width: 8), const SpNewChip()],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.content,
            style: const TextStyle(color: spText, fontSize: 14.5, height: 1.55),
          ),
          if (recent.topics.length >= 2) ...[
            const SizedBox(height: 8),
            Text(
              l.selfPortraitConnectedTopics,
              style: TextStyle(color: spMuted, fontSize: 11.5),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final topic in recent.topics)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      topic,
                      style: const TextStyle(color: spText, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ] else if (recent.quote != null) ...[
            const SizedBox(height: 6),
            Text(
              l.selfPortraitQuote(recent.quote!),
              style: TextStyle(
                color: spMuted,
                fontSize: 12.5,
                height: 1.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfirmBanner extends StatelessWidget {
  const _ConfirmBanner({
    required this.count,
    required this.sub,
    required this.onTap,
  });

  final int count;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SpCard(
      onTap: onTap,
      borderColor: AppColors.starGold.withValues(alpha: .55),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.starGold,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFF241A00),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.selfPortraitConfirmBanner,
                  style: const TextStyle(
                    color: spText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(color: spMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: spMuted),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.starGold.withValues(alpha: .18)
                : Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.starGold.withValues(alpha: .7)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.starGold : spText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(color: spMuted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileGroup {
  _TileGroup({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.all,
  });

  final String key;
  final String title;
  final String? subtitle;

  /// 子カテゴリがあるときは見出しごとに分けて出す
  final List<({String? title, List<ProfileItem> items})> sections;
  final List<ProfileItem> all;
}

List<ProfileItem> _sortItems(List<ProfileItem> items, String kind) {
  String key(ProfileItem i) =>
      kind == 'record' ? (i.occurredAt ?? i.changedAt) : i.changedAt;
  return [...items]..sort((a, b) => key(b).compareTo(key(a)));
}

List<_TileGroup> _buildGroups(
  AppLocalizations l,
  String kind,
  List<ProfileItem> items,
  List<ProfileCategory> categories,
) {
  final byId = {for (final c in categories) c.id: c};
  ProfileCategory? topOf(String? cid) {
    final c = cid == null ? null : byId[cid];
    if (c == null) return null;
    final parent = c.parentId == null ? null : byId[c.parentId];
    return parent ?? c;
  }

  final map = <String, _Bucket>{};
  for (final item in items) {
    final top = topOf(item.categoryId);
    final key = top?.id ?? '__other__';
    final bucket = map.putIfAbsent(key, () => _Bucket(top));
    final own = item.categoryId == null ? null : byId[item.categoryId];
    if (own != null && top != null && own.id != top.id) {
      bucket.children.putIfAbsent(own.name, () => []).add(item);
    } else {
      bucket.direct.add(item);
    }
  }

  final out = <_TileGroup>[];
  map.forEach((key, g) {
    final all = _sortItems([
      ...g.direct,
      for (final list in g.children.values) ...list,
    ], kind);
    out.add(
      _TileGroup(
        key: key,
        title: g.top?.name ?? l.selfPortraitOther,
        subtitle: g.children.isEmpty ? null : g.children.keys.join(' · '),
        sections: [
          if (g.direct.isNotEmpty)
            (title: null, items: _sortItems(g.direct, kind)),
          for (final e in g.children.entries)
            (title: e.key, items: _sortItems(e.value, kind)),
        ],
        all: all,
      ),
    );
  });
  // 最近動いたカテゴリを上に
  String latest(_TileGroup g) => g.all.isEmpty
      ? ''
      : (kind == 'record'
            ? (g.all.first.occurredAt ?? g.all.first.changedAt)
            : g.all.first.changedAt);
  out.sort((a, b) => latest(b).compareTo(latest(a)));
  return out;
}

class _Bucket {
  _Bucket(this.top);

  final ProfileCategory? top;
  final Map<String, List<ProfileItem>> children = {};
  final List<ProfileItem> direct = [];
}

class _CategoryTiles extends StatelessWidget {
  const _CategoryTiles({
    required this.kind,
    required this.items,
    required this.categories,
    required this.locale,
    required this.expanded,
    required this.onToggle,
    required this.onOpenItem,
  });

  final String kind;
  final List<ProfileItem> items;
  final List<ProfileCategory> categories;
  final String locale;
  final Set<String> expanded;
  final void Function(String key) onToggle;
  final void Function(ProfileItem item) onOpenItem;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final groups = _buildGroups(l, kind, items, categories);
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          kind == 'trait'
              ? l.selfPortraitEmptyTraits
              : l.selfPortraitEmptyRecords,
          style: TextStyle(color: spMuted, fontSize: 13.5, height: 1.6),
        ),
      );
    }
    return Column(
      children: [
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Tile(
              group: g,
              kind: kind,
              locale: locale,
              isOpen: expanded.contains('$kind:${g.key}'),
              onToggle: () => onToggle('$kind:${g.key}'),
              onOpenItem: onOpenItem,
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.group,
    required this.kind,
    required this.locale,
    required this.isOpen,
    required this.onToggle,
    required this.onOpenItem,
  });

  final _TileGroup group;
  final String kind;
  final String locale;
  final bool isOpen;
  final VoidCallback onToggle;
  final void Function(ProfileItem item) onOpenItem;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final latestDate = kind == 'record' ? group.all.first.occurredAt : null;
    final sub = latestDate != null
        ? l.selfPortraitLatest(shortDate(latestDate, locale))
        : group.subtitle;
    return SpCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.title,
                          style: const TextStyle(
                            color: spText,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (sub != null && sub.isNotEmpty)
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: spMuted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${group.all.length}',
                    style: TextStyle(color: spMuted, fontSize: 13),
                  ),
                  Icon(
                    isOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: spMuted,
                  ),
                ],
              ),
            ),
          ),
          if (isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final section in group.sections) ...[
                    if (section.title != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: Text(
                          section.title!,
                          style: TextStyle(
                            color: spMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    for (final item in section.items)
                      _ItemRow(
                        item: item,
                        kind: kind,
                        locale: locale,
                        onOpen: () => onOpenItem(item),
                      ),
                  ],
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in group.all.take(_tilePeek))
                    InkWell(
                      onTap: () => onOpenItem(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (kind == 'record')
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  shortDate(
                                    item.occurredAt ?? item.changedAt,
                                    locale,
                                  ),
                                  style: TextStyle(
                                    color: AppColors.starGold.withValues(
                                      alpha: .9,
                                    ),
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 7,
                                  right: 8,
                                ),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: item.isNew
                                        ? AppColors.starGold
                                        : spMuted.withValues(alpha: .6),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                item.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: spText,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (group.all.length > _tilePeek)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l.selfPortraitMoreCount('${group.all.length - _tilePeek}'),
                        style: TextStyle(color: spMuted, fontSize: 12),
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

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.kind,
    required this.locale,
    required this.onOpen,
  });

  final ProfileItem item;
  final String kind;
  final String locale;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final range =
        item.firstSeenAt != null &&
            item.lastSeenAt != null &&
            item.firstSeenAt != item.lastSeenAt
        ? '${shortDate(item.firstSeenAt, locale)}〜${shortDate(item.lastSeenAt, locale)}'
        : shortDate(item.lastSeenAt ?? item.changedAt, locale);
    final from = item.evidenceThreads > 0
        ? l.selfPortraitFromConversations('${item.evidenceThreads}')
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kind == 'record')
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 1),
              child: Text(
                shortDate(item.occurredAt ?? item.changedAt, locale),
                style: TextStyle(
                  color: AppColors.starGold.withValues(alpha: .9),
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.content,
                  style: const TextStyle(
                    color: spText,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                if (kind == 'trait')
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        if (item.isNew) ...[
                          const SpNewChip(),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            [from, range].where((s) => s.isNotEmpty).join(' · '),
                            style: TextStyle(color: spMuted, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onOpen,
            tooltip: l.selfPortraitItemActions,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.more_horiz_rounded, color: spMuted, size: 20),
          ),
        ],
      ),
    );
  }
}
