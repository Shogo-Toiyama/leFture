import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lefture/core/utils/self_portrait_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ja');
  });

  final now = DateTime(2026, 10, 18);

  test('今年の日付は年を省く', () {
    expect(shortDate('2026-10-02', 'en', now: now), '10/2');
    expect(shortDate('2026-10-02', 'ja', now: now), '10/2');
  });

  test('今年でなければ年をつける', () {
    expect(shortDate('2025-03-04', 'en', now: now), '3/4/2025');
  });

  test('日付だけの文字列は、時差でずれない', () {
    expect(shortDate('2026-01-01', 'en', now: now), '1/1');
  });

  test('空・読めない値は空文字', () {
    expect(shortDate(null, 'en', now: now), '');
    expect(shortDate('', 'en', now: now), '');
    expect(shortDate('not a date', 'en', now: now), '');
  });
}
