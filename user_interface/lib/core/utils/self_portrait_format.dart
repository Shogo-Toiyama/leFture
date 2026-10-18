// lib/core/utils/self_portrait_format.dart
import 'package:intl/intl.dart';

/// "2026-10-02" や ISO の日時を、表示用の「10/2」形式にする(年は今年なら省く)。
/// 読めない・空のときは空文字。webappの shortDate と同じ。
String shortDate(String? value, String locale, {DateTime? now}) {
  if (value == null || value.isEmpty) return '';
  final parsed = DateTime.tryParse(
    value.length == 10 ? '${value}T00:00:00' : value,
  );
  if (parsed == null) return '';
  final d = value.length == 10 ? parsed : parsed.toLocal();
  final sameYear = d.year == (now ?? DateTime.now()).year;
  return (sameYear ? DateFormat.Md(locale) : DateFormat.yMd(locale)).format(d);
}
