// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_attribute_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(courseAttributeRepository)
final courseAttributeRepositoryProvider = CourseAttributeRepositoryProvider._();

final class CourseAttributeRepositoryProvider
    extends
        $FunctionalProvider<
          CourseAttributeRepositorySupabase,
          CourseAttributeRepositorySupabase,
          CourseAttributeRepositorySupabase
        >
    with $Provider<CourseAttributeRepositorySupabase> {
  CourseAttributeRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'courseAttributeRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$courseAttributeRepositoryHash();

  @$internal
  @override
  $ProviderElement<CourseAttributeRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CourseAttributeRepositorySupabase create(Ref ref) {
    return courseAttributeRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CourseAttributeRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CourseAttributeRepositorySupabase>(
        value,
      ),
    );
  }
}

String _$courseAttributeRepositoryHash() =>
    r'b3faf19d25170cd0c35b547410f5a68738681571';
