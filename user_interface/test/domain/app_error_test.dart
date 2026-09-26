// AppErrorの指紋(fingerprint)まわりの検証。
//
// ここが壊れると、1つのバグが何百グループにも散ってダイジェストメールが
// 使い物にならなくなる(あるいは逆に、別のバグが同じグループに潰れて
// 見落とす)。正規化の意図をテストで固定しておく。
import 'package:flutter_test/flutter_test.dart';

import 'package:lefture/domain/errors/app_error.dart';
import 'package:lefture/domain/exceptions/account_suspended_exception.dart';
import 'package:lefture/domain/exceptions/insufficient_credits_exception.dart';

AppError _err(String raw, {String origin = 'upload_manager.chunk'}) =>
    AppError.from(Exception(raw), origin: origin);

void main() {
  group('fingerprint の正規化', () {
    test('UUID・連番・バイト数が違うだけなら同じグループになる', () {
      final a = _err('Failed to upload chunk 17 of job '
          '3f2a9b1c-4d5e-6f70-8192-a3b4c5d6e7f8 (4823 bytes)');
      final b = _err('Failed to upload chunk 4 of job '
          '99887766-1122-3344-5566-778899aabbcc (162341 bytes)');

      expect(a.fingerprint, b.fingerprint);
    });

    test('署名付きURLのクエリが毎回変わっても同じグループになる', () {
      final a = _err('PUT failed https://r2.example.com/audio/x.m4a'
          '?X-Amz-Signature=aaaaaaaaaaaa&X-Amz-Expires=3600');
      final b = _err('PUT failed https://r2.example.com/audio/x.m4a'
          '?X-Amz-Signature=bbbbbbbbbbbb&X-Amz-Expires=7200');

      expect(a.fingerprint, b.fingerprint);
    });

    test('タイムスタンプが違うだけなら同じグループになる', () {
      final a = _err('Job expired at 2026-09-25T10:14:02.123Z');
      final b = _err('Job expired at 2026-09-26T22:41:55.900Z');

      expect(a.fingerprint, b.fingerprint);
    });

    test('メッセージの中身が本当に違えば別グループになる', () {
      final a = _err('Failed to upload chunk');
      final b = _err('Failed to finalize job');

      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('origin が違えば別グループになる（同じ文面でも発生地点で分ける）', () {
      final a = _err('Connection reset', origin: 'upload_manager.chunk');
      final b = _err('Connection reset', origin: 'job_repository.startAnalysis');

      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('code が違えば別グループになる', () {
      final offline = _err('SocketException: Failed host lookup');
      final unknown = _err('Null check operator used on a null value');

      expect(offline.code, AppErrorCode.offline);
      expect(unknown.code, AppErrorCode.unknown);
      expect(offline.fingerprint, isNot(unknown.fingerprint));
    });
  });

  group('refCode', () {
    test('同じ指紋・同じ分なら同じコードになる（嵐でコードが散らない）', () {
      final at = DateTime.utc(2026, 9, 25, 10, 14, 2);
      final base = AppError(
        code: AppErrorCode.unknown,
        origin: 'x.y',
        raw: 'boom',
        at: at,
      );
      final same = AppError(
        code: AppErrorCode.unknown,
        origin: 'x.y',
        raw: 'boom',
        at: at.add(const Duration(seconds: 30)),
      );

      expect(base.refCode, same.refCode);
    });

    test('ERR- 接頭辞 + 6文字、紛らわしい文字を含まない', () {
      final code = _err('anything').refCode;

      expect(code, startsWith('ERR-'));
      expect(code.length, 10);
      expect(code.substring(4), matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{6}$')));
      expect(code, isNot(contains('I')));
      expect(code, isNot(contains('L')));
      expect(code, isNot(contains('O')));
      expect(code, isNot(contains('U')));
    });
  });

  group('分類と報告方針', () {
    test('待っても直らない/ユーザー起因のコードは報告しない', () {
      expect(_err('SocketException: Failed host lookup').shouldReport, isFalse);
      expect(_err('TimeoutException after 0:00:30').shouldReport, isFalse);
      expect(_err('Invalid login credentials').shouldReport, isFalse);
    });

    test('未知のエラーは報告する（これが本命）', () {
      expect(_err('Null check operator used on a null value').shouldReport, isTrue);
    });

    test('型付き例外は code に昇格する', () {
      final credits = AppError.from(
        const InsufficientCreditsException(
          errorCode: 'NO_CREDIT_ALLOCATION',
          message: 'plan required',
        ),
        origin: 'upload_manager.start_analysis',
      );
      expect(credits.code, AppErrorCode.noCreditAllocation);
      expect(credits.httpStatus, 402);

      final suspended = AppError.from(
        const AccountSuspendedException(),
        origin: 'upload_manager.chunk',
      );
      expect(suspended.code, AppErrorCode.accountSuspended);
      expect(suspended.httpStatus, 403);
    });

    test('バックエンドの構造化レスポンスから code を読む', () {
      final known = AppError.fromResponse(
        origin: 'job_repository.startAnalysis',
        statusCode: 402,
        body: '{"detail":{"error_code":"INSUFFICIENT_CREDITS","message":"out of credits"}}',
      );
      expect(known.code, AppErrorCode.insufficientCredits);

      final unknownCode = AppError.fromResponse(
        origin: 'job_repository.startAnalysis',
        statusCode: 422,
        body: '{"detail":{"error_code":"SOMETHING_NEW","message":"nope"}}',
      );
      expect(unknownCode.code, AppErrorCode.backendRejected);
      expect(unknownCode.backendCode, 'SOMETHING_NEW');

      final notJson = AppError.fromResponse(
        origin: 'job_repository.startAnalysis',
        statusCode: 502,
        body: '<html>Bad Gateway</html>',
      );
      expect(notJson.code, AppErrorCode.backendRejected);
      expect(notJson.httpStatus, 502);
    });
  });

  group('DBラウンドトリップ', () {
    test('encode → tryDecode で内容が保たれる', () {
      final original = AppError.from(
        const InsufficientCreditsException(
          errorCode: 'INSUFFICIENT_CREDITS',
          message: 'out of credits',
        ),
        origin: 'upload_manager.start_analysis',
      );

      final restored = AppError.tryDecode(original.encode())!;

      expect(restored.code, original.code);
      expect(restored.origin, original.origin);
      expect(restored.raw, original.raw);
      expect(restored.backendCode, original.backendCode);
      expect(restored.fingerprint, original.fingerprint);
    });

    test('旧バージョンが書いた生の toString() も読める（レガシー行の救済）', () {
      // アプリを更新しても、更新前に失敗して残っているジョブ行は
      // 生文字列のまま残っている。それを落とさずに分類できること。
      final legacy = AppError.tryDecode(
        'InsufficientCreditsException(NO_CREDIT_ALLOCATION): plan required',
      )!;
      expect(legacy.raw, contains('NO_CREDIT_ALLOCATION'));

      final legacyOffline =
          AppError.tryDecode('SocketException: Failed host lookup (os error 8)')!;
      expect(legacyOffline.code, AppErrorCode.offline);
    });

    test('null / 空文字は null を返す', () {
      expect(AppError.tryDecode(null), isNull);
      expect(AppError.tryDecode('   '), isNull);
    });
  });

  test('二重に封筒へ入れても origin が上書きされない', () {
    final inner = AppError.from(Exception('boom'), origin: 'deep.layer');
    final outer = AppError.from(inner, origin: 'shallow.layer');

    expect(outer.origin, 'deep.layer');
    expect(outer.fingerprint, inner.fingerprint);
  });
}
