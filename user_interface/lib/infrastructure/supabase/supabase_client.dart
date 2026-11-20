import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

/// Keeps auth-state observers active across refresh failures logged by GoTrue.
/// The SDK still retries transient failures and emits signedOut for a lost session.
Stream<AuthState> authStateEvents(Stream<AuthState> source) =>
    source.handleError(
      (Object _, StackTrace _) {},
      test: (error) =>
          error is AuthRetryableFetchException ||
          (error is AuthApiException &&
              error.code == 'refresh_token_not_found'),
    );
