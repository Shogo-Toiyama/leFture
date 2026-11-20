import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('refresh failures do not become uncaught auth stream errors', () async {
    final source = StreamController<AuthState>.broadcast();
    final errors = <Object>[];
    final events = <AuthChangeEvent>[];
    final done = Completer<void>();
    runZonedGuarded(() {
      final stream = authStateEvents(source.stream);
      stream.listen(
        (state) => events.add(state.event),
        onDone: () => done.complete(),
      );
    }, (error, stack) => errors.add(error));

    source.add(AuthState(AuthChangeEvent.initialSession, null));
    source.addError(AuthRetryableFetchException(message: 'fixture'));
    source.add(AuthState(AuthChangeEvent.tokenRefreshed, null));
    source.add(AuthState(AuthChangeEvent.signedOut, null));
    source.addError(
      AuthApiException(
        'fixture',
        statusCode: '400',
        code: 'refresh_token_not_found',
      ),
    );
    await source.close();
    await done.future;

    expect(events, [
      AuthChangeEvent.initialSession,
      AuthChangeEvent.tokenRefreshed,
      AuthChangeEvent.signedOut,
    ]);
    expect(errors, isEmpty);
  });

  test('unexpected auth stream errors still reach the subscriber', () async {
    final source = StreamController<AuthState>();
    final unexpected = AuthApiException('fixture', code: 'unexpected');
    final errors = expectLater(
      authStateEvents(source.stream),
      emitsError(same(unexpected)),
    );
    source.addError(unexpected);
    await source.close();
    await errors;
  });
}
