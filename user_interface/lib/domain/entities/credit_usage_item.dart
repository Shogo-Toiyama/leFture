// lib/domain/entities/credit_usage_item.dart

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
