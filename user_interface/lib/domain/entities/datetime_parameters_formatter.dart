import 'package:intl/intl.dart';

/// `datetime_parameters` (announcements テーブルの生JSON) を整形済み文言に変換する。
/// パース不能な形はすべて null を返し、呼び出し側でフォールバック表示させる。
String? formatDatetimeParameters(
  Map<String, dynamic>? params, {
  required DateTime anchor,
}) {
  if (params == null) return null;

  final timeType = params['time_type'] as String?;
  final extractedDate = params['extracted_date'] as Map<String, dynamic>?;
  final extractedTime = params['extracted_time'] as Map<String, dynamic>?;
  final rawTimeText = params['raw_time_text'] as String?;

  if (timeType == 'recurring') {
    return _formatRecurring(params['recurring_rule'] as Map<String, dynamic>?) ?? rawTimeText;
  }

  final date = extractedDate == null
      ? null
      : _resolveDate(extractedDate, anchor: anchor, rawTimeText: rawTimeText);

  final dateStr = date == null ? null : DateFormat('EEE, MMM d').format(date);
  final timeStr = _formatTimeRange(extractedTime, timeType);

  if (dateStr == null && timeStr == null) return rawTimeText;

  final prefix = timeType == 'deadline' ? 'Due ' : '';
  if (dateStr != null && timeStr != null) {
    return '$prefix$dateStr · $timeStr';
  }
  return '$prefix${dateStr ?? timeStr}';
}

DateTime? _resolveDate(
  Map<String, dynamic> extractedDate, {
  required DateTime anchor,
  String? rawTimeText,
}) {
  final type = extractedDate['type'] as String?;
  final anchorDate = DateTime(anchor.year, anchor.month, anchor.day);

  switch (type) {
    case 'absolute':
      final month = extractedDate['month'] as int?;
      final day = extractedDate['day'] as int?;
      if (month == null || day == null) return null;
      var year = anchorDate.year;
      var candidate = DateTime(year, month, day);
      // アンカーより過去なら翌年の日付とみなす
      if (candidate.isBefore(anchorDate)) {
        candidate = DateTime(year + 1, month, day);
      }
      return candidate;

    case 'relative_weekday':
      final weekday = extractedDate['weekday'] as String?;
      final modifier = extractedDate['modifier'] as String?;
      final targetWeekday = _weekdayFromName(weekday);
      if (targetWeekday == null) return null;
      var delta = (targetWeekday - anchorDate.weekday) % 7;
      if (delta == 0) delta = 7; // 同じ曜日なら次週扱い
      if (delta < 0) delta += 7;
      if (modifier == 'next') delta += 7;
      return anchorDate.add(Duration(days: delta));

    case 'relative_offset':
      final offsetDays = extractedDate['offset_days'] as int?;
      if (offsetDays == null) return null;
      return anchorDate.add(Duration(days: offsetDays));

    case 'relative_day':
      final text = rawTimeText?.toLowerCase() ?? '';
      if (text.contains('tomorrow')) {
        return anchorDate.add(const Duration(days: 1));
      }
      if (text.contains('today')) {
        return anchorDate;
      }
      return null;

    default:
      return null;
  }
}

int? _weekdayFromName(String? name) {
  const names = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  ];
  final idx = names.indexOf(name?.toLowerCase() ?? '');
  return idx == -1 ? null : idx + 1; // DateTime.weekday: Monday=1..Sunday=7
}

String? _formatTimeRange(Map<String, dynamic>? extractedTime, String? timeType) {
  if (extractedTime == null) return null;
  final start = _formatClock(extractedTime['start_24h'] as String?);
  final end = _formatClock(extractedTime['end_24h'] as String?);

  if (start != null && end != null) return '$start – $end';
  if (timeType == 'deadline') return end;
  return start ?? end;
}

String? _formatClock(String? hhmmss) {
  if (hhmmss == null) return null;
  final parts = hhmmss.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  final dummy = DateTime(2000, 1, 1, hour, minute);
  return DateFormat('h:mm a').format(dummy);
}

String? _formatRecurring(Map<String, dynamic>? rule) {
  if (rule == null) return null;
  final frequency = rule['frequency'] as String?;
  final interval = rule['interval'] as int? ?? 1;
  final daysOfWeek = (rule['days_of_week'] as List?)?.cast<String>();
  final datesOfMonth = (rule['dates_of_month'] as List?)?.cast<int>();
  final nthWeekday = rule['nth_weekday'] as int?;

  switch (frequency) {
    case 'daily':
      return interval <= 1 ? 'Every day' : 'Every $interval days';
    case 'weekly':
      if (daysOfWeek != null && daysOfWeek.isNotEmpty) {
        final days = daysOfWeek.join(', ');
        return interval <= 1 ? 'Every $days' : 'Every $interval weeks on $days';
      }
      return interval <= 1 ? 'Weekly' : 'Every $interval weeks';
    case 'monthly':
      if (datesOfMonth != null && datesOfMonth.isNotEmpty) {
        return 'Monthly on the ${datesOfMonth.join(", ")}';
      }
      if (nthWeekday != null && daysOfWeek != null && daysOfWeek.isNotEmpty) {
        return 'Monthly on the ${_ordinal(nthWeekday)} ${daysOfWeek.first}';
      }
      return 'Monthly';
    default:
      return null;
  }
}

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}
