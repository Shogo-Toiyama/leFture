// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'deep_note_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deepNoteRepository)
final deepNoteRepositoryProvider = DeepNoteRepositoryProvider._();

final class DeepNoteRepositoryProvider
    extends
        $FunctionalProvider<
          DeepNoteRepositorySupabase,
          DeepNoteRepositorySupabase,
          DeepNoteRepositorySupabase
        >
    with $Provider<DeepNoteRepositorySupabase> {
  DeepNoteRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deepNoteRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deepNoteRepositoryHash();

  @$internal
  @override
  $ProviderElement<DeepNoteRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DeepNoteRepositorySupabase create(Ref ref) {
    return deepNoteRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeepNoteRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeepNoteRepositorySupabase>(value),
    );
  }
}

String _$deepNoteRepositoryHash() =>
    r'0bb3cdaa9934a074c3e998fa93e91f66a4de5e74';
