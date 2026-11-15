import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/application/device/device_identity_service.dart';
import 'package:lefture/application/errors/error_reporter.dart';
import 'package:lefture/domain/errors/app_error.dart';
import 'package:lefture/infrastructure/local_db/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('four same-outcome traces retain four independent payloads', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final supabase = SupabaseClient('https://example.invalid', 'test-key');
    final reporter = ErrorReporter(
      db: db,
      deviceIdentity: DeviceIdentityService(),
      supabase: supabase,
    );
    addTearDown(() async {
      reporter.dispose();
      await db.close();
      await supabase.dispose();
    });
    for (var i = 0; i < 4; i++) {
      await reporter.report(AppError(
        code: AppErrorCode.uploadTrace,
        origin: 'upload_trace.realtime',
        raw: 'Realtime upload trace: completed (lecture abcdef12, 10 lines, 0m1s since stop)',
        at: DateTime.now(),
      ), traceLines: ['trace-$i']);
    }
    final rows = await db.dequeuePendingErrorReports();
    expect(rows, hasLength(4));
    expect(rows.map((r) => jsonDecode(r.payloadJson)['breadcrumbs'].single),
        ['trace-0', 'trace-1', 'trace-2', 'trace-3']);
  });
}
