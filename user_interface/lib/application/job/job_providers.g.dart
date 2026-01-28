// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(jobRepository)
final jobRepositoryProvider = JobRepositoryProvider._();

final class JobRepositoryProvider
    extends $FunctionalProvider<JobRepository, JobRepository, JobRepository>
    with $Provider<JobRepository> {
  JobRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'jobRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$jobRepositoryHash();

  @$internal
  @override
  $ProviderElement<JobRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  JobRepository create(Ref ref) {
    return jobRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(JobRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<JobRepository>(value),
    );
  }
}

String _$jobRepositoryHash() => r'66a276349fe305a9c5dd34a83e786951f47ded2f';

@ProviderFor(jobStream)
final jobStreamProvider = JobStreamFamily._();

final class JobStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<ProcessingJobs?>,
          ProcessingJobs?,
          Stream<ProcessingJobs?>
        >
    with $FutureModifier<ProcessingJobs?>, $StreamProvider<ProcessingJobs?> {
  JobStreamProvider._({
    required JobStreamFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'jobStreamProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$jobStreamHash();

  @override
  String toString() {
    return r'jobStreamProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<ProcessingJobs?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ProcessingJobs?> create(Ref ref) {
    final argument = this.argument as String;
    return jobStream(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is JobStreamProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$jobStreamHash() => r'859e14aa75dd9153a209f1365ccc61510bafc5e6';

final class JobStreamFamily extends $Family
    with $FunctionalFamilyOverride<Stream<ProcessingJobs?>, String> {
  JobStreamFamily._()
    : super(
        retry: null,
        name: r'jobStreamProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  JobStreamProvider call(String lectureId) =>
      JobStreamProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'jobStreamProvider';
}
