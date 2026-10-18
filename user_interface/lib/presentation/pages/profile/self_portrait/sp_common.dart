// lib/presentation/pages/profile/self_portrait/sp_common.dart
import 'package:flutter/material.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

// 自分像・AIのメモの画面で共通の、宇宙の画面(ダーク)向けの部品。

const spText = Color(0xFFF2F2F2);
const spSheetBackground = Color(0xFF171B2B);

Color get spMuted => AppColors.universe.textComet;

/// 表紙の欄の名前。
String coverFieldLabel(AppLocalizations l, CoverField f) => switch (f) {
  CoverField.bio => l.selfPortraitCoverBio,
  CoverField.interests => l.selfPortraitCoverInterests,
  CoverField.futureGoals => l.selfPortraitCoverFutureGoals,
};

/// 欄がまだ空のときの案内。
String coverFieldEmpty(AppLocalizations l, CoverField f) => switch (f) {
  CoverField.bio => l.selfPortraitCoverBioEmpty,
  CoverField.interests => l.selfPortraitCoverInterestsEmpty,
  CoverField.futureGoals => l.selfPortraitCoverFutureGoalsEmpty,
};

/// 「親 › 子」の形のカテゴリ名。カテゴリが無ければ「その他」。
String categoryPath(
  AppLocalizations l,
  Map<String, ProfileCategory> byId,
  String? id,
) {
  final c = id == null ? null : byId[id];
  if (c == null) return l.selfPortraitOther;
  final parent = c.parentId == null ? null : byId[c.parentId];
  return parent != null ? '${parent.name} › ${c.name}' : c.name;
}

/// ガラス風のカード。タップできるときは[onTap]を渡す。
class SpCard extends StatelessWidget {
  const SpCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Material(
      color: AppColors.universe.glassWhiteLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: borderColor ?? AppColors.universe.glassBorder.withValues(alpha: .35),
          width: .8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 小さな見出し(大文字・字間広め)。
class SpSectionLabel extends StatelessWidget {
  const SpSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color ?? spMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class SpNewChip extends StatelessWidget {
  const SpNewChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.starGold,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        AppLocalizations.of(context).selfPortraitNew,
        style: const TextStyle(
          color: Color(0xFF241A00),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

/// 読み込みや操作に失敗したときの一行。
class SpErrorText extends StatelessWidget {
  const SpErrorText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.correctionRed, fontSize: 13),
    ),
  );
}

/// 自分像のシート(項目・確認トレイ・表紙の編集)の入れ物。下から出る暗いシート。
Future<T?> showSpSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: spSheetBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Padding(
      // キーボードが出たら、その分だけ持ち上げる
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}

/// シートの見出し行(題名と閉じる)。
class SpSheetHeader extends StatelessWidget {
  const SpSheetHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: spText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            icon: Icon(Icons.close_rounded, color: spMuted),
          ),
        ],
      ),
    );
  }
}

/// 金色の主ボタンと、枠だけの副ボタン(シートの中の操作)。
class SpPrimaryButton extends StatelessWidget {
  const SpPrimaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.starGold,
      foregroundColor: const Color(0xFF241A00),
      disabledBackgroundColor: AppColors.starGold.withValues(alpha: .3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class SpSecondaryButton extends StatelessWidget {
  const SpSecondaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: spText,
      side: BorderSide(color: spMuted.withValues(alpha: .6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Text(label),
  );
}

/// 複数行の入力欄(シートの中)。
class SpTextField extends StatelessWidget {
  const SpTextField({
    super.key,
    required this.controller,
    this.hint,
    this.maxLines = 4,
    this.maxLength = 500,
    this.onChanged,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final int maxLength;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    minLines: maxLines > 2 ? 3 : 1,
    maxLines: maxLines,
    maxLength: maxLength,
    onChanged: onChanged,
    style: const TextStyle(color: spText, fontSize: 14.5, height: 1.5),
    cursorColor: AppColors.starGold,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: spMuted),
      filled: true,
      fillColor: Colors.white.withValues(alpha: .06),
      counterStyle: TextStyle(color: spMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.starGold, width: 1),
      ),
    ),
  );
}
