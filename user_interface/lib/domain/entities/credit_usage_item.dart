import 'package:intl/intl.dart';

/// GET /billing/history が返す1件の履歴アイテムモデル。
/// kind == transaction: 通常の付与/消費(1時間ごとにまとめた消費含む)。
/// kind == reset: プラン更新/切り替えで古いクレジットがリセットされた
/// 区切り。具体的な数字を見せると「クレジットを失った」という誤解を招く
/// ため、数字は持たず、resetReason("renewed" | "plan_changed")だけを持つ。
enum CreditUsageKind { transaction, reset }

class CreditUsageItem {
  const CreditUsageItem({
    required this.id,
    required this.kind,
    required this.dateLabel,
    required this.timeLabel,
    required this.timestamp,
    this.deltaCredits = 0,
    this.formattedDelta = '',
    this.isPositive = false,
    this.resetReason,
  });

  final String id;
  final CreditUsageKind kind;
  final String dateLabel;
  final String timeLabel;
  final DateTime timestamp;
  final int deltaCredits;
  final String formattedDelta;
  final bool isPositive;

  /// kind == resetの時だけ意味を持つ: "renewed"(同一プランの更新) または
  /// "plan_changed"(プラン切り替え/Freeへのフォールバック)。
  final String? resetReason;

  bool get isReset => kind == CreditUsageKind.reset;

  /// スマホ端末の現地時間に合わせた日付ラベル (例: "Today", "Yesterday", "Jul 23")
  String localDateLabel(
    String? locale, {
    String? todayLabel,
    String? yesterdayLabel,
  }) {
    final localDt = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(localDt.year, localDt.month, localDt.day);
    final differenceInDays = today.difference(itemDate).inDays;

    if (differenceInDays == 0) {
      return todayLabel ?? 'Today';
    } else if (differenceInDays == 1) {
      return yesterdayLabel ?? 'Yesterday';
    } else {
      return DateFormat.MMMd(locale).format(localDt);
    }
  }

  /// スマホ端末の現地時間に合わせた時間ラベル (例: "1 PM", "8 PM", "11 AM")
  String localTimeLabel([String? locale]) {
    final localDt = timestamp.toLocal();
    return DateFormat.j(locale).format(localDt);
  }

  factory CreditUsageItem.fromJson(Map<String, dynamic> json) {
    return CreditUsageItem(
      id: json['id'] as String,
      kind: json['kind'] == 'reset' ? CreditUsageKind.reset : CreditUsageKind.transaction,
      dateLabel: json['date_label'] as String? ?? '',
      timeLabel: json['time_label'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      deltaCredits: (json['delta_credits'] as num?)?.toInt() ?? 0,
      formattedDelta: json['formatted_delta'] as String? ?? '',
      isPositive: json['is_positive'] as bool? ?? false,
      resetReason: json['reset_reason'] as String?,
    );
  }
}
