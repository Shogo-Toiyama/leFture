// AIへのデータ送信の同意は、版番号つきでアカウントに残る。送り先を増やして版を上げたとき、
// 前の版に同意した人にもう一度聞けるかは、この読み取りで決まる。
import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';

void main() {
  const at = 'ai_recording_profile_share_consent_at';
  const version = 'ai_recording_share_consent_version';

  int read(Map<String, dynamic> m, {int? legacy}) => aiConsentVersionOf(
    m,
    atKey: at,
    versionKey: version,
    legacyVersion: legacy,
  );

  test('同意していなければ0', () {
    expect(read({}), 0);
    expect(read({'onboarding_completed_at': 'x'}), 0);
  });

  test('版番号が無く日時だけあれば、古い同意(第1版)として読む', () {
    expect(read({at: '2026-09-01T00:00:00Z'}), 1);
  });

  test('版番号があればそれを使う', () {
    expect(read({at: 'x', version: 2}), 2);
    expect(read({version: 3}), 3);
    expect(read({at: 'x', version: 2.0}), 2);
  });

  test('第1版に同意した人は、第2版が要るときは同意済みにならない', () {
    expect(
      read({at: '2026-09-01T00:00:00Z'}) >=
          UserProfileRepositorySupabase.aiRecordingConsentVersion,
      isFalse,
    );
    expect(
      read({at: 'x', version: 2}) >=
          UserProfileRepositorySupabase.aiRecordingConsentVersion,
      isTrue,
    );
  });
}
