import 'package:intl/intl.dart';

/// GET /billing/history が返す1時間ごとのクレジット利用履歴アイテムモデル。
class CreditUsageItem {
  const CreditUsageItem({
    required this.id,
    required this.dateLabel,
    required this.timeLabel,
    required this.timestamp,
    required this.deltaCredits,
    required this.formattedDelta,
    required this.isPositive,
    required this.reasonSummary,
  });

  final String id;
  final String dateLabel;
  final String timeLabel;
  final DateTime timestamp;
  final int deltaCredits;
  final String formattedDelta;
  final bool isPositive;
  final String reasonSummary;

  /// スマホ端末の現地時間に合わせた日付ラベル (例: "Today", "Yesterday", "Jul 23")
  String localDateLabel([String? locale]) {
    final localDt = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(localDt.year, localDt.month, localDt.day);
    final differenceInDays = today.difference(itemDate).inDays;

    if (differenceInDays == 0) {
      return 'Today';
    } else if (differenceInDays == 1) {
      return 'Yesterday';
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
      dateLabel: json['date_label'] as String? ?? '',
      timeLabel: json['time_label'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      deltaCredits: (json['delta_credits'] as num?)?.toInt() ?? 0,
      formattedDelta: json['formatted_delta'] as String? ?? '0',
      isPositive: json['is_positive'] as bool? ?? false,
      reasonSummary: json['reason_summary'] as String? ?? '',
    );
  }
}
