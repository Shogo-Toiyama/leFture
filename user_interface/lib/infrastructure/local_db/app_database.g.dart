// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalOutboxTable extends LocalOutbox
    with TableInfo<$LocalOutboxTable, LocalOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enqueuedAtMeta = const VerificationMeta(
    'enqueuedAt',
  );
  @override
  late final GeneratedColumn<DateTime> enqueuedAt = GeneratedColumn<DateTime>(
    'enqueued_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextRetryAtMeta = const VerificationMeta(
    'nextRetryAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
    'next_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _givenUpMeta = const VerificationMeta(
    'givenUp',
  );
  @override
  late final GeneratedColumn<bool> givenUp = GeneratedColumn<bool>(
    'given_up',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("given_up" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    op,
    payloadJson,
    enqueuedAt,
    attemptCount,
    lastError,
    nextRetryAt,
    givenUp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('enqueued_at')) {
      context.handle(
        _enqueuedAtMeta,
        enqueuedAt.isAcceptableOrUnknown(data['enqueued_at']!, _enqueuedAtMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
        _nextRetryAtMeta,
        nextRetryAt.isAcceptableOrUnknown(
          data['next_retry_at']!,
          _nextRetryAtMeta,
        ),
      );
    }
    if (data.containsKey('given_up')) {
      context.handle(
        _givenUpMeta,
        givenUp.isAcceptableOrUnknown(data['given_up']!, _givenUpMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalOutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      op: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      ),
      enqueuedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}enqueued_at'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      nextRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_retry_at'],
      ),
      givenUp: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}given_up'],
      )!,
    );
  }

  @override
  $LocalOutboxTable createAlias(String alias) {
    return $LocalOutboxTable(attachedDatabase, alias);
  }
}

class LocalOutboxData extends DataClass implements Insertable<LocalOutboxData> {
  final int id;
  final String entityType;
  final String entityId;
  final String op;
  final String? payloadJson;
  final DateTime enqueuedAt;
  final int attemptCount;
  final String? lastError;
  final DateTime? nextRetryAt;
  final bool givenUp;
  const LocalOutboxData({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.op,
    this.payloadJson,
    required this.enqueuedAt,
    required this.attemptCount,
    this.lastError,
    this.nextRetryAt,
    required this.givenUp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['op'] = Variable<String>(op);
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    map['enqueued_at'] = Variable<DateTime>(enqueuedAt);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    map['given_up'] = Variable<bool>(givenUp);
    return map;
  }

  LocalOutboxCompanion toCompanion(bool nullToAbsent) {
    return LocalOutboxCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      op: Value(op),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
      enqueuedAt: Value(enqueuedAt),
      attemptCount: Value(attemptCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      givenUp: Value(givenUp),
    );
  }

  factory LocalOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalOutboxData(
      id: serializer.fromJson<int>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      op: serializer.fromJson<String>(json['op']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
      enqueuedAt: serializer.fromJson<DateTime>(json['enqueuedAt']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      givenUp: serializer.fromJson<bool>(json['givenUp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'op': serializer.toJson<String>(op),
      'payloadJson': serializer.toJson<String?>(payloadJson),
      'enqueuedAt': serializer.toJson<DateTime>(enqueuedAt),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastError': serializer.toJson<String?>(lastError),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'givenUp': serializer.toJson<bool>(givenUp),
    };
  }

  LocalOutboxData copyWith({
    int? id,
    String? entityType,
    String? entityId,
    String? op,
    Value<String?> payloadJson = const Value.absent(),
    DateTime? enqueuedAt,
    int? attemptCount,
    Value<String?> lastError = const Value.absent(),
    Value<DateTime?> nextRetryAt = const Value.absent(),
    bool? givenUp,
  }) => LocalOutboxData(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    op: op ?? this.op,
    payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
    enqueuedAt: enqueuedAt ?? this.enqueuedAt,
    attemptCount: attemptCount ?? this.attemptCount,
    lastError: lastError.present ? lastError.value : this.lastError,
    nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
    givenUp: givenUp ?? this.givenUp,
  );
  LocalOutboxData copyWithCompanion(LocalOutboxCompanion data) {
    return LocalOutboxData(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      op: data.op.present ? data.op.value : this.op,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      enqueuedAt: data.enqueuedAt.present
          ? data.enqueuedAt.value
          : this.enqueuedAt,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      nextRetryAt: data.nextRetryAt.present
          ? data.nextRetryAt.value
          : this.nextRetryAt,
      givenUp: data.givenUp.present ? data.givenUp.value : this.givenUp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalOutboxData(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('givenUp: $givenUp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    op,
    payloadJson,
    enqueuedAt,
    attemptCount,
    lastError,
    nextRetryAt,
    givenUp,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalOutboxData &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.op == this.op &&
          other.payloadJson == this.payloadJson &&
          other.enqueuedAt == this.enqueuedAt &&
          other.attemptCount == this.attemptCount &&
          other.lastError == this.lastError &&
          other.nextRetryAt == this.nextRetryAt &&
          other.givenUp == this.givenUp);
}

class LocalOutboxCompanion extends UpdateCompanion<LocalOutboxData> {
  final Value<int> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> op;
  final Value<String?> payloadJson;
  final Value<DateTime> enqueuedAt;
  final Value<int> attemptCount;
  final Value<String?> lastError;
  final Value<DateTime?> nextRetryAt;
  final Value<bool> givenUp;
  const LocalOutboxCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.op = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.enqueuedAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.givenUp = const Value.absent(),
  });
  LocalOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required String op,
    this.payloadJson = const Value.absent(),
    this.enqueuedAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.givenUp = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       op = Value(op);
  static Insertable<LocalOutboxData> custom({
    Expression<int>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? op,
    Expression<String>? payloadJson,
    Expression<DateTime>? enqueuedAt,
    Expression<int>? attemptCount,
    Expression<String>? lastError,
    Expression<DateTime>? nextRetryAt,
    Expression<bool>? givenUp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (op != null) 'op': op,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (enqueuedAt != null) 'enqueued_at': enqueuedAt,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastError != null) 'last_error': lastError,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (givenUp != null) 'given_up': givenUp,
    });
  }

  LocalOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? op,
    Value<String?>? payloadJson,
    Value<DateTime>? enqueuedAt,
    Value<int>? attemptCount,
    Value<String?>? lastError,
    Value<DateTime?>? nextRetryAt,
    Value<bool>? givenUp,
  }) {
    return LocalOutboxCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      op: op ?? this.op,
      payloadJson: payloadJson ?? this.payloadJson,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      givenUp: givenUp ?? this.givenUp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (enqueuedAt.present) {
      map['enqueued_at'] = Variable<DateTime>(enqueuedAt.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (givenUp.present) {
      map['given_up'] = Variable<bool>(givenUp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalOutboxCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('givenUp: $givenUp')
          ..write(')'))
        .toString();
  }
}

class $LocalLecturesTable extends LocalLectures
    with TableInfo<$LocalLecturesTable, LocalLecture> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalLecturesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courseIdMeta = const VerificationMeta(
    'courseId',
  );
  @override
  late final GeneratedColumn<String> courseId = GeneratedColumn<String>(
    'course_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleGeneratedMeta = const VerificationMeta(
    'titleGenerated',
  );
  @override
  late final GeneratedColumn<String> titleGenerated = GeneratedColumn<String>(
    'title_generated',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expectedChunksMeta = const VerificationMeta(
    'expectedChunks',
  );
  @override
  late final GeneratedColumn<int> expectedChunks = GeneratedColumn<int>(
    'expected_chunks',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lectureDatetimeMeta = const VerificationMeta(
    'lectureDatetime',
  );
  @override
  late final GeneratedColumn<DateTime> lectureDatetime =
      GeneratedColumn<DateTime>(
        'lecture_datetime',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _whisperContextMeta = const VerificationMeta(
    'whisperContext',
  );
  @override
  late final GeneratedColumn<String> whisperContext = GeneratedColumn<String>(
    'whisper_context',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioPathMeta = const VerificationMeta(
    'audioPath',
  );
  @override
  late final GeneratedColumn<String> audioPath = GeneratedColumn<String>(
    'audio_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local_only'),
  );
  static const VerificationMeta _lastAccessedAtMeta = const VerificationMeta(
    'lastAccessedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAccessedAt =
      GeneratedColumn<DateTime>(
        'last_accessed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _topicMapMovePendingMeta =
      const VerificationMeta('topicMapMovePending');
  @override
  late final GeneratedColumn<bool> topicMapMovePending = GeneratedColumn<bool>(
    'topic_map_move_pending',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("topic_map_move_pending" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pendingTopicMapStaleCourseIdMeta =
      const VerificationMeta('pendingTopicMapStaleCourseId');
  @override
  late final GeneratedColumn<String> pendingTopicMapStaleCourseId =
      GeneratedColumn<String>(
        'pending_topic_map_stale_course_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _autoStartAnalysisMeta = const VerificationMeta(
    'autoStartAnalysis',
  );
  @override
  late final GeneratedColumn<bool> autoStartAnalysis = GeneratedColumn<bool>(
    'auto_start_analysis',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_start_analysis" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isRealtimeMeta = const VerificationMeta(
    'isRealtime',
  );
  @override
  late final GeneratedColumn<bool> isRealtime = GeneratedColumn<bool>(
    'is_realtime',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_realtime" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    courseId,
    title,
    titleGenerated,
    expectedChunks,
    lectureDatetime,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
    whisperContext,
    summary,
    audioPath,
    metadataJson,
    syncStatus,
    lastAccessedAt,
    isPinned,
    topicMapMovePending,
    pendingTopicMapStaleCourseId,
    autoStartAnalysis,
    isRealtime,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_lectures';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalLecture> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('course_id')) {
      context.handle(
        _courseIdMeta,
        courseId.isAcceptableOrUnknown(data['course_id']!, _courseIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('title_generated')) {
      context.handle(
        _titleGeneratedMeta,
        titleGenerated.isAcceptableOrUnknown(
          data['title_generated']!,
          _titleGeneratedMeta,
        ),
      );
    }
    if (data.containsKey('expected_chunks')) {
      context.handle(
        _expectedChunksMeta,
        expectedChunks.isAcceptableOrUnknown(
          data['expected_chunks']!,
          _expectedChunksMeta,
        ),
      );
    }
    if (data.containsKey('lecture_datetime')) {
      context.handle(
        _lectureDatetimeMeta,
        lectureDatetime.isAcceptableOrUnknown(
          data['lecture_datetime']!,
          _lectureDatetimeMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('whisper_context')) {
      context.handle(
        _whisperContextMeta,
        whisperContext.isAcceptableOrUnknown(
          data['whisper_context']!,
          _whisperContextMeta,
        ),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('audio_path')) {
      context.handle(
        _audioPathMeta,
        audioPath.isAcceptableOrUnknown(data['audio_path']!, _audioPathMeta),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('last_accessed_at')) {
      context.handle(
        _lastAccessedAtMeta,
        lastAccessedAt.isAcceptableOrUnknown(
          data['last_accessed_at']!,
          _lastAccessedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('topic_map_move_pending')) {
      context.handle(
        _topicMapMovePendingMeta,
        topicMapMovePending.isAcceptableOrUnknown(
          data['topic_map_move_pending']!,
          _topicMapMovePendingMeta,
        ),
      );
    }
    if (data.containsKey('pending_topic_map_stale_course_id')) {
      context.handle(
        _pendingTopicMapStaleCourseIdMeta,
        pendingTopicMapStaleCourseId.isAcceptableOrUnknown(
          data['pending_topic_map_stale_course_id']!,
          _pendingTopicMapStaleCourseIdMeta,
        ),
      );
    }
    if (data.containsKey('auto_start_analysis')) {
      context.handle(
        _autoStartAnalysisMeta,
        autoStartAnalysis.isAcceptableOrUnknown(
          data['auto_start_analysis']!,
          _autoStartAnalysisMeta,
        ),
      );
    }
    if (data.containsKey('is_realtime')) {
      context.handle(
        _isRealtimeMeta,
        isRealtime.isAcceptableOrUnknown(data['is_realtime']!, _isRealtimeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalLecture map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalLecture(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      courseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}course_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      titleGenerated: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_generated'],
      ),
      expectedChunks: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_chunks'],
      ),
      lectureDatetime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}lecture_datetime'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      whisperContext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}whisper_context'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      audioPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_path'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      lastAccessedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_accessed_at'],
      ),
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      topicMapMovePending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}topic_map_move_pending'],
      )!,
      pendingTopicMapStaleCourseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_topic_map_stale_course_id'],
      ),
      autoStartAnalysis: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_start_analysis'],
      )!,
      isRealtime: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_realtime'],
      )!,
    );
  }

  @override
  $LocalLecturesTable createAlias(String alias) {
    return $LocalLecturesTable(attachedDatabase, alias);
  }
}

class LocalLecture extends DataClass implements Insertable<LocalLecture> {
  final String id;
  final String userId;
  final String? courseId;
  final String? title;
  final String? titleGenerated;
  final int? expectedChunks;
  final DateTime? lectureDatetime;
  final int? sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? whisperContext;
  final String? summary;
  final String? audioPath;
  final String? metadataJson;
  final String syncStatus;
  final DateTime? lastAccessedAt;
  final bool isPinned;
  final bool topicMapMovePending;
  final String? pendingTopicMapStaleCourseId;
  final bool autoStartAnalysis;
  final bool isRealtime;
  const LocalLecture({
    required this.id,
    required this.userId,
    this.courseId,
    this.title,
    this.titleGenerated,
    this.expectedChunks,
    this.lectureDatetime,
    this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.whisperContext,
    this.summary,
    this.audioPath,
    this.metadataJson,
    required this.syncStatus,
    this.lastAccessedAt,
    required this.isPinned,
    required this.topicMapMovePending,
    this.pendingTopicMapStaleCourseId,
    required this.autoStartAnalysis,
    required this.isRealtime,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    if (!nullToAbsent || courseId != null) {
      map['course_id'] = Variable<String>(courseId);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || titleGenerated != null) {
      map['title_generated'] = Variable<String>(titleGenerated);
    }
    if (!nullToAbsent || expectedChunks != null) {
      map['expected_chunks'] = Variable<int>(expectedChunks);
    }
    if (!nullToAbsent || lectureDatetime != null) {
      map['lecture_datetime'] = Variable<DateTime>(lectureDatetime);
    }
    if (!nullToAbsent || sortOrder != null) {
      map['sort_order'] = Variable<int>(sortOrder);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || whisperContext != null) {
      map['whisper_context'] = Variable<String>(whisperContext);
    }
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    if (!nullToAbsent || audioPath != null) {
      map['audio_path'] = Variable<String>(audioPath);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || lastAccessedAt != null) {
      map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt);
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    map['topic_map_move_pending'] = Variable<bool>(topicMapMovePending);
    if (!nullToAbsent || pendingTopicMapStaleCourseId != null) {
      map['pending_topic_map_stale_course_id'] = Variable<String>(
        pendingTopicMapStaleCourseId,
      );
    }
    map['auto_start_analysis'] = Variable<bool>(autoStartAnalysis);
    map['is_realtime'] = Variable<bool>(isRealtime);
    return map;
  }

  LocalLecturesCompanion toCompanion(bool nullToAbsent) {
    return LocalLecturesCompanion(
      id: Value(id),
      userId: Value(userId),
      courseId: courseId == null && nullToAbsent
          ? const Value.absent()
          : Value(courseId),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      titleGenerated: titleGenerated == null && nullToAbsent
          ? const Value.absent()
          : Value(titleGenerated),
      expectedChunks: expectedChunks == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedChunks),
      lectureDatetime: lectureDatetime == null && nullToAbsent
          ? const Value.absent()
          : Value(lectureDatetime),
      sortOrder: sortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      whisperContext: whisperContext == null && nullToAbsent
          ? const Value.absent()
          : Value(whisperContext),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      audioPath: audioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioPath),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      syncStatus: Value(syncStatus),
      lastAccessedAt: lastAccessedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAccessedAt),
      isPinned: Value(isPinned),
      topicMapMovePending: Value(topicMapMovePending),
      pendingTopicMapStaleCourseId:
          pendingTopicMapStaleCourseId == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingTopicMapStaleCourseId),
      autoStartAnalysis: Value(autoStartAnalysis),
      isRealtime: Value(isRealtime),
    );
  }

  factory LocalLecture.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalLecture(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      courseId: serializer.fromJson<String?>(json['courseId']),
      title: serializer.fromJson<String?>(json['title']),
      titleGenerated: serializer.fromJson<String?>(json['titleGenerated']),
      expectedChunks: serializer.fromJson<int?>(json['expectedChunks']),
      lectureDatetime: serializer.fromJson<DateTime?>(json['lectureDatetime']),
      sortOrder: serializer.fromJson<int?>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      whisperContext: serializer.fromJson<String?>(json['whisperContext']),
      summary: serializer.fromJson<String?>(json['summary']),
      audioPath: serializer.fromJson<String?>(json['audioPath']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      lastAccessedAt: serializer.fromJson<DateTime?>(json['lastAccessedAt']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      topicMapMovePending: serializer.fromJson<bool>(
        json['topicMapMovePending'],
      ),
      pendingTopicMapStaleCourseId: serializer.fromJson<String?>(
        json['pendingTopicMapStaleCourseId'],
      ),
      autoStartAnalysis: serializer.fromJson<bool>(json['autoStartAnalysis']),
      isRealtime: serializer.fromJson<bool>(json['isRealtime']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'courseId': serializer.toJson<String?>(courseId),
      'title': serializer.toJson<String?>(title),
      'titleGenerated': serializer.toJson<String?>(titleGenerated),
      'expectedChunks': serializer.toJson<int?>(expectedChunks),
      'lectureDatetime': serializer.toJson<DateTime?>(lectureDatetime),
      'sortOrder': serializer.toJson<int?>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'whisperContext': serializer.toJson<String?>(whisperContext),
      'summary': serializer.toJson<String?>(summary),
      'audioPath': serializer.toJson<String?>(audioPath),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'lastAccessedAt': serializer.toJson<DateTime?>(lastAccessedAt),
      'isPinned': serializer.toJson<bool>(isPinned),
      'topicMapMovePending': serializer.toJson<bool>(topicMapMovePending),
      'pendingTopicMapStaleCourseId': serializer.toJson<String?>(
        pendingTopicMapStaleCourseId,
      ),
      'autoStartAnalysis': serializer.toJson<bool>(autoStartAnalysis),
      'isRealtime': serializer.toJson<bool>(isRealtime),
    };
  }

  LocalLecture copyWith({
    String? id,
    String? userId,
    Value<String?> courseId = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> titleGenerated = const Value.absent(),
    Value<int?> expectedChunks = const Value.absent(),
    Value<DateTime?> lectureDatetime = const Value.absent(),
    Value<int?> sortOrder = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    Value<String?> whisperContext = const Value.absent(),
    Value<String?> summary = const Value.absent(),
    Value<String?> audioPath = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
    String? syncStatus,
    Value<DateTime?> lastAccessedAt = const Value.absent(),
    bool? isPinned,
    bool? topicMapMovePending,
    Value<String?> pendingTopicMapStaleCourseId = const Value.absent(),
    bool? autoStartAnalysis,
    bool? isRealtime,
  }) => LocalLecture(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    courseId: courseId.present ? courseId.value : this.courseId,
    title: title.present ? title.value : this.title,
    titleGenerated: titleGenerated.present
        ? titleGenerated.value
        : this.titleGenerated,
    expectedChunks: expectedChunks.present
        ? expectedChunks.value
        : this.expectedChunks,
    lectureDatetime: lectureDatetime.present
        ? lectureDatetime.value
        : this.lectureDatetime,
    sortOrder: sortOrder.present ? sortOrder.value : this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    whisperContext: whisperContext.present
        ? whisperContext.value
        : this.whisperContext,
    summary: summary.present ? summary.value : this.summary,
    audioPath: audioPath.present ? audioPath.value : this.audioPath,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    syncStatus: syncStatus ?? this.syncStatus,
    lastAccessedAt: lastAccessedAt.present
        ? lastAccessedAt.value
        : this.lastAccessedAt,
    isPinned: isPinned ?? this.isPinned,
    topicMapMovePending: topicMapMovePending ?? this.topicMapMovePending,
    pendingTopicMapStaleCourseId: pendingTopicMapStaleCourseId.present
        ? pendingTopicMapStaleCourseId.value
        : this.pendingTopicMapStaleCourseId,
    autoStartAnalysis: autoStartAnalysis ?? this.autoStartAnalysis,
    isRealtime: isRealtime ?? this.isRealtime,
  );
  LocalLecture copyWithCompanion(LocalLecturesCompanion data) {
    return LocalLecture(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      courseId: data.courseId.present ? data.courseId.value : this.courseId,
      title: data.title.present ? data.title.value : this.title,
      titleGenerated: data.titleGenerated.present
          ? data.titleGenerated.value
          : this.titleGenerated,
      expectedChunks: data.expectedChunks.present
          ? data.expectedChunks.value
          : this.expectedChunks,
      lectureDatetime: data.lectureDatetime.present
          ? data.lectureDatetime.value
          : this.lectureDatetime,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      whisperContext: data.whisperContext.present
          ? data.whisperContext.value
          : this.whisperContext,
      summary: data.summary.present ? data.summary.value : this.summary,
      audioPath: data.audioPath.present ? data.audioPath.value : this.audioPath,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      lastAccessedAt: data.lastAccessedAt.present
          ? data.lastAccessedAt.value
          : this.lastAccessedAt,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      topicMapMovePending: data.topicMapMovePending.present
          ? data.topicMapMovePending.value
          : this.topicMapMovePending,
      pendingTopicMapStaleCourseId: data.pendingTopicMapStaleCourseId.present
          ? data.pendingTopicMapStaleCourseId.value
          : this.pendingTopicMapStaleCourseId,
      autoStartAnalysis: data.autoStartAnalysis.present
          ? data.autoStartAnalysis.value
          : this.autoStartAnalysis,
      isRealtime: data.isRealtime.present
          ? data.isRealtime.value
          : this.isRealtime,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalLecture(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('courseId: $courseId, ')
          ..write('title: $title, ')
          ..write('titleGenerated: $titleGenerated, ')
          ..write('expectedChunks: $expectedChunks, ')
          ..write('lectureDatetime: $lectureDatetime, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('whisperContext: $whisperContext, ')
          ..write('summary: $summary, ')
          ..write('audioPath: $audioPath, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('isPinned: $isPinned, ')
          ..write('topicMapMovePending: $topicMapMovePending, ')
          ..write(
            'pendingTopicMapStaleCourseId: $pendingTopicMapStaleCourseId, ',
          )
          ..write('autoStartAnalysis: $autoStartAnalysis, ')
          ..write('isRealtime: $isRealtime')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    userId,
    courseId,
    title,
    titleGenerated,
    expectedChunks,
    lectureDatetime,
    sortOrder,
    createdAt,
    updatedAt,
    deletedAt,
    whisperContext,
    summary,
    audioPath,
    metadataJson,
    syncStatus,
    lastAccessedAt,
    isPinned,
    topicMapMovePending,
    pendingTopicMapStaleCourseId,
    autoStartAnalysis,
    isRealtime,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalLecture &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.courseId == this.courseId &&
          other.title == this.title &&
          other.titleGenerated == this.titleGenerated &&
          other.expectedChunks == this.expectedChunks &&
          other.lectureDatetime == this.lectureDatetime &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.whisperContext == this.whisperContext &&
          other.summary == this.summary &&
          other.audioPath == this.audioPath &&
          other.metadataJson == this.metadataJson &&
          other.syncStatus == this.syncStatus &&
          other.lastAccessedAt == this.lastAccessedAt &&
          other.isPinned == this.isPinned &&
          other.topicMapMovePending == this.topicMapMovePending &&
          other.pendingTopicMapStaleCourseId ==
              this.pendingTopicMapStaleCourseId &&
          other.autoStartAnalysis == this.autoStartAnalysis &&
          other.isRealtime == this.isRealtime);
}

class LocalLecturesCompanion extends UpdateCompanion<LocalLecture> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String?> courseId;
  final Value<String?> title;
  final Value<String?> titleGenerated;
  final Value<int?> expectedChunks;
  final Value<DateTime?> lectureDatetime;
  final Value<int?> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String?> whisperContext;
  final Value<String?> summary;
  final Value<String?> audioPath;
  final Value<String?> metadataJson;
  final Value<String> syncStatus;
  final Value<DateTime?> lastAccessedAt;
  final Value<bool> isPinned;
  final Value<bool> topicMapMovePending;
  final Value<String?> pendingTopicMapStaleCourseId;
  final Value<bool> autoStartAnalysis;
  final Value<bool> isRealtime;
  final Value<int> rowid;
  const LocalLecturesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.courseId = const Value.absent(),
    this.title = const Value.absent(),
    this.titleGenerated = const Value.absent(),
    this.expectedChunks = const Value.absent(),
    this.lectureDatetime = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.whisperContext = const Value.absent(),
    this.summary = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.topicMapMovePending = const Value.absent(),
    this.pendingTopicMapStaleCourseId = const Value.absent(),
    this.autoStartAnalysis = const Value.absent(),
    this.isRealtime = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalLecturesCompanion.insert({
    required String id,
    required String userId,
    this.courseId = const Value.absent(),
    this.title = const Value.absent(),
    this.titleGenerated = const Value.absent(),
    this.expectedChunks = const Value.absent(),
    this.lectureDatetime = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.whisperContext = const Value.absent(),
    this.summary = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.topicMapMovePending = const Value.absent(),
    this.pendingTopicMapStaleCourseId = const Value.absent(),
    this.autoStartAnalysis = const Value.absent(),
    this.isRealtime = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId);
  static Insertable<LocalLecture> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? courseId,
    Expression<String>? title,
    Expression<String>? titleGenerated,
    Expression<int>? expectedChunks,
    Expression<DateTime>? lectureDatetime,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? whisperContext,
    Expression<String>? summary,
    Expression<String>? audioPath,
    Expression<String>? metadataJson,
    Expression<String>? syncStatus,
    Expression<DateTime>? lastAccessedAt,
    Expression<bool>? isPinned,
    Expression<bool>? topicMapMovePending,
    Expression<String>? pendingTopicMapStaleCourseId,
    Expression<bool>? autoStartAnalysis,
    Expression<bool>? isRealtime,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (courseId != null) 'course_id': courseId,
      if (title != null) 'title': title,
      if (titleGenerated != null) 'title_generated': titleGenerated,
      if (expectedChunks != null) 'expected_chunks': expectedChunks,
      if (lectureDatetime != null) 'lecture_datetime': lectureDatetime,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (whisperContext != null) 'whisper_context': whisperContext,
      if (summary != null) 'summary': summary,
      if (audioPath != null) 'audio_path': audioPath,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (lastAccessedAt != null) 'last_accessed_at': lastAccessedAt,
      if (isPinned != null) 'is_pinned': isPinned,
      if (topicMapMovePending != null)
        'topic_map_move_pending': topicMapMovePending,
      if (pendingTopicMapStaleCourseId != null)
        'pending_topic_map_stale_course_id': pendingTopicMapStaleCourseId,
      if (autoStartAnalysis != null) 'auto_start_analysis': autoStartAnalysis,
      if (isRealtime != null) 'is_realtime': isRealtime,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalLecturesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String?>? courseId,
    Value<String?>? title,
    Value<String?>? titleGenerated,
    Value<int?>? expectedChunks,
    Value<DateTime?>? lectureDatetime,
    Value<int?>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String?>? whisperContext,
    Value<String?>? summary,
    Value<String?>? audioPath,
    Value<String?>? metadataJson,
    Value<String>? syncStatus,
    Value<DateTime?>? lastAccessedAt,
    Value<bool>? isPinned,
    Value<bool>? topicMapMovePending,
    Value<String?>? pendingTopicMapStaleCourseId,
    Value<bool>? autoStartAnalysis,
    Value<bool>? isRealtime,
    Value<int>? rowid,
  }) {
    return LocalLecturesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      courseId: courseId ?? this.courseId,
      title: title ?? this.title,
      titleGenerated: titleGenerated ?? this.titleGenerated,
      expectedChunks: expectedChunks ?? this.expectedChunks,
      lectureDatetime: lectureDatetime ?? this.lectureDatetime,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      whisperContext: whisperContext ?? this.whisperContext,
      summary: summary ?? this.summary,
      audioPath: audioPath ?? this.audioPath,
      metadataJson: metadataJson ?? this.metadataJson,
      syncStatus: syncStatus ?? this.syncStatus,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      isPinned: isPinned ?? this.isPinned,
      topicMapMovePending: topicMapMovePending ?? this.topicMapMovePending,
      pendingTopicMapStaleCourseId:
          pendingTopicMapStaleCourseId ?? this.pendingTopicMapStaleCourseId,
      autoStartAnalysis: autoStartAnalysis ?? this.autoStartAnalysis,
      isRealtime: isRealtime ?? this.isRealtime,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (courseId.present) {
      map['course_id'] = Variable<String>(courseId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleGenerated.present) {
      map['title_generated'] = Variable<String>(titleGenerated.value);
    }
    if (expectedChunks.present) {
      map['expected_chunks'] = Variable<int>(expectedChunks.value);
    }
    if (lectureDatetime.present) {
      map['lecture_datetime'] = Variable<DateTime>(lectureDatetime.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (whisperContext.present) {
      map['whisper_context'] = Variable<String>(whisperContext.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (audioPath.present) {
      map['audio_path'] = Variable<String>(audioPath.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (lastAccessedAt.present) {
      map['last_accessed_at'] = Variable<DateTime>(lastAccessedAt.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (topicMapMovePending.present) {
      map['topic_map_move_pending'] = Variable<bool>(topicMapMovePending.value);
    }
    if (pendingTopicMapStaleCourseId.present) {
      map['pending_topic_map_stale_course_id'] = Variable<String>(
        pendingTopicMapStaleCourseId.value,
      );
    }
    if (autoStartAnalysis.present) {
      map['auto_start_analysis'] = Variable<bool>(autoStartAnalysis.value);
    }
    if (isRealtime.present) {
      map['is_realtime'] = Variable<bool>(isRealtime.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalLecturesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('courseId: $courseId, ')
          ..write('title: $title, ')
          ..write('titleGenerated: $titleGenerated, ')
          ..write('expectedChunks: $expectedChunks, ')
          ..write('lectureDatetime: $lectureDatetime, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('whisperContext: $whisperContext, ')
          ..write('summary: $summary, ')
          ..write('audioPath: $audioPath, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('isPinned: $isPinned, ')
          ..write('topicMapMovePending: $topicMapMovePending, ')
          ..write(
            'pendingTopicMapStaleCourseId: $pendingTopicMapStaleCourseId, ',
          )
          ..write('autoStartAnalysis: $autoStartAnalysis, ')
          ..write('isRealtime: $isRealtime, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalLectureAssetsTable extends LocalLectureAssets
    with TableInfo<$LocalLectureAssetsTable, LocalLectureAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalLectureAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startTimeMeta = const VerificationMeta(
    'startTime',
  );
  @override
  late final GeneratedColumn<double> startTime = GeneratedColumn<double>(
    'start_time',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _sequenceIndexMeta = const VerificationMeta(
    'sequenceIndex',
  );
  @override
  late final GeneratedColumn<int> sequenceIndex = GeneratedColumn<int>(
    'sequence_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storageBucketMeta = const VerificationMeta(
    'storageBucket',
  );
  @override
  late final GeneratedColumn<String> storageBucket = GeneratedColumn<String>(
    'storage_bucket',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storagePathMeta = const VerificationMeta(
    'storagePath',
  );
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
    'storage_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uploadStatusMeta = const VerificationMeta(
    'uploadStatus',
  );
  @override
  late final GeneratedColumn<String> uploadStatus = GeneratedColumn<String>(
    'upload_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextRetryAtMeta = const VerificationMeta(
    'nextRetryAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
    'next_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    type,
    startTime,
    sequenceIndex,
    localPath,
    storageBucket,
    storagePath,
    uploadStatus,
    attemptCount,
    nextRetryAt,
    lastError,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_lecture_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalLectureAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('start_time')) {
      context.handle(
        _startTimeMeta,
        startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta),
      );
    }
    if (data.containsKey('sequence_index')) {
      context.handle(
        _sequenceIndexMeta,
        sequenceIndex.isAcceptableOrUnknown(
          data['sequence_index']!,
          _sequenceIndexMeta,
        ),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('storage_bucket')) {
      context.handle(
        _storageBucketMeta,
        storageBucket.isAcceptableOrUnknown(
          data['storage_bucket']!,
          _storageBucketMeta,
        ),
      );
    }
    if (data.containsKey('storage_path')) {
      context.handle(
        _storagePathMeta,
        storagePath.isAcceptableOrUnknown(
          data['storage_path']!,
          _storagePathMeta,
        ),
      );
    }
    if (data.containsKey('upload_status')) {
      context.handle(
        _uploadStatusMeta,
        uploadStatus.isAcceptableOrUnknown(
          data['upload_status']!,
          _uploadStatusMeta,
        ),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
        _nextRetryAtMeta,
        nextRetryAt.isAcceptableOrUnknown(
          data['next_retry_at']!,
          _nextRetryAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalLectureAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalLectureAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      startTime: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}start_time'],
      )!,
      sequenceIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence_index'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      storageBucket: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_bucket'],
      ),
      storagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_path'],
      ),
      uploadStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}upload_status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_retry_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalLectureAssetsTable createAlias(String alias) {
    return $LocalLectureAssetsTable(attachedDatabase, alias);
  }
}

class LocalLectureAsset extends DataClass
    implements Insertable<LocalLectureAsset> {
  final String id;
  final String userId;
  final String lectureId;
  final String type;
  final double startTime;
  final int sequenceIndex;
  final String? localPath;
  final String? storageBucket;
  final String? storagePath;
  final String uploadStatus;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalLectureAsset({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.type,
    required this.startTime,
    required this.sequenceIndex,
    this.localPath,
    this.storageBucket,
    this.storagePath,
    required this.uploadStatus,
    required this.attemptCount,
    this.nextRetryAt,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    map['type'] = Variable<String>(type);
    map['start_time'] = Variable<double>(startTime);
    map['sequence_index'] = Variable<int>(sequenceIndex);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    if (!nullToAbsent || storageBucket != null) {
      map['storage_bucket'] = Variable<String>(storageBucket);
    }
    if (!nullToAbsent || storagePath != null) {
      map['storage_path'] = Variable<String>(storagePath);
    }
    map['upload_status'] = Variable<String>(uploadStatus);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalLectureAssetsCompanion toCompanion(bool nullToAbsent) {
    return LocalLectureAssetsCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      type: Value(type),
      startTime: Value(startTime),
      sequenceIndex: Value(sequenceIndex),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      storageBucket: storageBucket == null && nullToAbsent
          ? const Value.absent()
          : Value(storageBucket),
      storagePath: storagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(storagePath),
      uploadStatus: Value(uploadStatus),
      attemptCount: Value(attemptCount),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalLectureAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalLectureAsset(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      type: serializer.fromJson<String>(json['type']),
      startTime: serializer.fromJson<double>(json['startTime']),
      sequenceIndex: serializer.fromJson<int>(json['sequenceIndex']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      storageBucket: serializer.fromJson<String?>(json['storageBucket']),
      storagePath: serializer.fromJson<String?>(json['storagePath']),
      uploadStatus: serializer.fromJson<String>(json['uploadStatus']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'type': serializer.toJson<String>(type),
      'startTime': serializer.toJson<double>(startTime),
      'sequenceIndex': serializer.toJson<int>(sequenceIndex),
      'localPath': serializer.toJson<String?>(localPath),
      'storageBucket': serializer.toJson<String?>(storageBucket),
      'storagePath': serializer.toJson<String?>(storagePath),
      'uploadStatus': serializer.toJson<String>(uploadStatus),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalLectureAsset copyWith({
    String? id,
    String? userId,
    String? lectureId,
    String? type,
    double? startTime,
    int? sequenceIndex,
    Value<String?> localPath = const Value.absent(),
    Value<String?> storageBucket = const Value.absent(),
    Value<String?> storagePath = const Value.absent(),
    String? uploadStatus,
    int? attemptCount,
    Value<DateTime?> nextRetryAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LocalLectureAsset(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    type: type ?? this.type,
    startTime: startTime ?? this.startTime,
    sequenceIndex: sequenceIndex ?? this.sequenceIndex,
    localPath: localPath.present ? localPath.value : this.localPath,
    storageBucket: storageBucket.present
        ? storageBucket.value
        : this.storageBucket,
    storagePath: storagePath.present ? storagePath.value : this.storagePath,
    uploadStatus: uploadStatus ?? this.uploadStatus,
    attemptCount: attemptCount ?? this.attemptCount,
    nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalLectureAsset copyWithCompanion(LocalLectureAssetsCompanion data) {
    return LocalLectureAsset(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      type: data.type.present ? data.type.value : this.type,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      sequenceIndex: data.sequenceIndex.present
          ? data.sequenceIndex.value
          : this.sequenceIndex,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      storageBucket: data.storageBucket.present
          ? data.storageBucket.value
          : this.storageBucket,
      storagePath: data.storagePath.present
          ? data.storagePath.value
          : this.storagePath,
      uploadStatus: data.uploadStatus.present
          ? data.uploadStatus.value
          : this.uploadStatus,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextRetryAt: data.nextRetryAt.present
          ? data.nextRetryAt.value
          : this.nextRetryAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalLectureAsset(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('type: $type, ')
          ..write('startTime: $startTime, ')
          ..write('sequenceIndex: $sequenceIndex, ')
          ..write('localPath: $localPath, ')
          ..write('storageBucket: $storageBucket, ')
          ..write('storagePath: $storagePath, ')
          ..write('uploadStatus: $uploadStatus, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    lectureId,
    type,
    startTime,
    sequenceIndex,
    localPath,
    storageBucket,
    storagePath,
    uploadStatus,
    attemptCount,
    nextRetryAt,
    lastError,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalLectureAsset &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.type == this.type &&
          other.startTime == this.startTime &&
          other.sequenceIndex == this.sequenceIndex &&
          other.localPath == this.localPath &&
          other.storageBucket == this.storageBucket &&
          other.storagePath == this.storagePath &&
          other.uploadStatus == this.uploadStatus &&
          other.attemptCount == this.attemptCount &&
          other.nextRetryAt == this.nextRetryAt &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalLectureAssetsCompanion extends UpdateCompanion<LocalLectureAsset> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<String> type;
  final Value<double> startTime;
  final Value<int> sequenceIndex;
  final Value<String?> localPath;
  final Value<String?> storageBucket;
  final Value<String?> storagePath;
  final Value<String> uploadStatus;
  final Value<int> attemptCount;
  final Value<DateTime?> nextRetryAt;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalLectureAssetsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.type = const Value.absent(),
    this.startTime = const Value.absent(),
    this.sequenceIndex = const Value.absent(),
    this.localPath = const Value.absent(),
    this.storageBucket = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.uploadStatus = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalLectureAssetsCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    required String type,
    this.startTime = const Value.absent(),
    this.sequenceIndex = const Value.absent(),
    this.localPath = const Value.absent(),
    this.storageBucket = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.uploadStatus = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       type = Value(type);
  static Insertable<LocalLectureAsset> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<String>? type,
    Expression<double>? startTime,
    Expression<int>? sequenceIndex,
    Expression<String>? localPath,
    Expression<String>? storageBucket,
    Expression<String>? storagePath,
    Expression<String>? uploadStatus,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextRetryAt,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (type != null) 'type': type,
      if (startTime != null) 'start_time': startTime,
      if (sequenceIndex != null) 'sequence_index': sequenceIndex,
      if (localPath != null) 'local_path': localPath,
      if (storageBucket != null) 'storage_bucket': storageBucket,
      if (storagePath != null) 'storage_path': storagePath,
      if (uploadStatus != null) 'upload_status': uploadStatus,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalLectureAssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<String>? type,
    Value<double>? startTime,
    Value<int>? sequenceIndex,
    Value<String?>? localPath,
    Value<String?>? storageBucket,
    Value<String?>? storagePath,
    Value<String>? uploadStatus,
    Value<int>? attemptCount,
    Value<DateTime?>? nextRetryAt,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalLectureAssetsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      type: type ?? this.type,
      startTime: startTime ?? this.startTime,
      sequenceIndex: sequenceIndex ?? this.sequenceIndex,
      localPath: localPath ?? this.localPath,
      storageBucket: storageBucket ?? this.storageBucket,
      storagePath: storagePath ?? this.storagePath,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      attemptCount: attemptCount ?? this.attemptCount,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<double>(startTime.value);
    }
    if (sequenceIndex.present) {
      map['sequence_index'] = Variable<int>(sequenceIndex.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (storageBucket.present) {
      map['storage_bucket'] = Variable<String>(storageBucket.value);
    }
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (uploadStatus.present) {
      map['upload_status'] = Variable<String>(uploadStatus.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalLectureAssetsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('type: $type, ')
          ..write('startTime: $startTime, ')
          ..write('sequenceIndex: $sequenceIndex, ')
          ..write('localPath: $localPath, ')
          ..write('storageBucket: $storageBucket, ')
          ..write('storagePath: $storagePath, ')
          ..write('uploadStatus: $uploadStatus, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalUploadJobsTable extends LocalUploadJobs
    with TableInfo<$LocalUploadJobsTable, LocalUploadJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalUploadJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('audio_upload'),
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextRetryAtMeta = const VerificationMeta(
    'nextRetryAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
    'next_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    kind,
    lectureId,
    assetId,
    status,
    attemptCount,
    nextRetryAt,
    lastError,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_upload_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalUploadJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
        _nextRetryAtMeta,
        nextRetryAt.isAcceptableOrUnknown(
          data['next_retry_at']!,
          _nextRetryAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalUploadJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalUploadJob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_retry_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalUploadJobsTable createAlias(String alias) {
    return $LocalUploadJobsTable(attachedDatabase, alias);
  }
}

class LocalUploadJob extends DataClass implements Insertable<LocalUploadJob> {
  final String id;
  final String userId;
  final String kind;
  final String lectureId;
  final String assetId;
  final String status;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalUploadJob({
    required this.id,
    required this.userId,
    required this.kind,
    required this.lectureId,
    required this.assetId,
    required this.status,
    required this.attemptCount,
    this.nextRetryAt,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['kind'] = Variable<String>(kind);
    map['lecture_id'] = Variable<String>(lectureId);
    map['asset_id'] = Variable<String>(assetId);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalUploadJobsCompanion toCompanion(bool nullToAbsent) {
    return LocalUploadJobsCompanion(
      id: Value(id),
      userId: Value(userId),
      kind: Value(kind),
      lectureId: Value(lectureId),
      assetId: Value(assetId),
      status: Value(status),
      attemptCount: Value(attemptCount),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalUploadJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalUploadJob(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      kind: serializer.fromJson<String>(json['kind']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      assetId: serializer.fromJson<String>(json['assetId']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'kind': serializer.toJson<String>(kind),
      'lectureId': serializer.toJson<String>(lectureId),
      'assetId': serializer.toJson<String>(assetId),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalUploadJob copyWith({
    String? id,
    String? userId,
    String? kind,
    String? lectureId,
    String? assetId,
    String? status,
    int? attemptCount,
    Value<DateTime?> nextRetryAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LocalUploadJob(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    kind: kind ?? this.kind,
    lectureId: lectureId ?? this.lectureId,
    assetId: assetId ?? this.assetId,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalUploadJob copyWithCompanion(LocalUploadJobsCompanion data) {
    return LocalUploadJob(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      kind: data.kind.present ? data.kind.value : this.kind,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextRetryAt: data.nextRetryAt.present
          ? data.nextRetryAt.value
          : this.nextRetryAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalUploadJob(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('lectureId: $lectureId, ')
          ..write('assetId: $assetId, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    kind,
    lectureId,
    assetId,
    status,
    attemptCount,
    nextRetryAt,
    lastError,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalUploadJob &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.kind == this.kind &&
          other.lectureId == this.lectureId &&
          other.assetId == this.assetId &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.nextRetryAt == this.nextRetryAt &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalUploadJobsCompanion extends UpdateCompanion<LocalUploadJob> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> kind;
  final Value<String> lectureId;
  final Value<String> assetId;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<DateTime?> nextRetryAt;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalUploadJobsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.kind = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalUploadJobsCompanion.insert({
    required String id,
    required String userId,
    this.kind = const Value.absent(),
    required String lectureId,
    required String assetId,
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       assetId = Value(assetId);
  static Insertable<LocalUploadJob> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? kind,
    Expression<String>? lectureId,
    Expression<String>? assetId,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextRetryAt,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (kind != null) 'kind': kind,
      if (lectureId != null) 'lecture_id': lectureId,
      if (assetId != null) 'asset_id': assetId,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalUploadJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? kind,
    Value<String>? lectureId,
    Value<String>? assetId,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<DateTime?>? nextRetryAt,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalUploadJobsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      lectureId: lectureId ?? this.lectureId,
      assetId: assetId ?? this.assetId,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalUploadJobsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('kind: $kind, ')
          ..write('lectureId: $lectureId, ')
          ..write('assetId: $assetId, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCoursesTable extends LocalCourses
    with TableInfo<$LocalCoursesTable, LocalCourse> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCoursesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courseTitleMeta = const VerificationMeta(
    'courseTitle',
  );
  @override
  late final GeneratedColumn<String> courseTitle = GeneratedColumn<String>(
    'course_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courseCodeMeta = const VerificationMeta(
    'courseCode',
  );
  @override
  late final GeneratedColumn<String> courseCode = GeneratedColumn<String>(
    'course_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _schoolIdMeta = const VerificationMeta(
    'schoolId',
  );
  @override
  late final GeneratedColumn<String> schoolId = GeneratedColumn<String>(
    'school_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearIdMeta = const VerificationMeta('yearId');
  @override
  late final GeneratedColumn<String> yearId = GeneratedColumn<String>(
    'year_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _termIdMeta = const VerificationMeta('termId');
  @override
  late final GeneratedColumn<String> termId = GeneratedColumn<String>(
    'term_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _professorIdMeta = const VerificationMeta(
    'professorId',
  );
  @override
  late final GeneratedColumn<String> professorId = GeneratedColumn<String>(
    'professor_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local_only'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    courseTitle,
    courseCode,
    summary,
    schoolId,
    yearId,
    termId,
    subjectId,
    professorId,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_courses';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCourse> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('course_title')) {
      context.handle(
        _courseTitleMeta,
        courseTitle.isAcceptableOrUnknown(
          data['course_title']!,
          _courseTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_courseTitleMeta);
    }
    if (data.containsKey('course_code')) {
      context.handle(
        _courseCodeMeta,
        courseCode.isAcceptableOrUnknown(data['course_code']!, _courseCodeMeta),
      );
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('school_id')) {
      context.handle(
        _schoolIdMeta,
        schoolId.isAcceptableOrUnknown(data['school_id']!, _schoolIdMeta),
      );
    }
    if (data.containsKey('year_id')) {
      context.handle(
        _yearIdMeta,
        yearId.isAcceptableOrUnknown(data['year_id']!, _yearIdMeta),
      );
    }
    if (data.containsKey('term_id')) {
      context.handle(
        _termIdMeta,
        termId.isAcceptableOrUnknown(data['term_id']!, _termIdMeta),
      );
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    }
    if (data.containsKey('professor_id')) {
      context.handle(
        _professorIdMeta,
        professorId.isAcceptableOrUnknown(
          data['professor_id']!,
          _professorIdMeta,
        ),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalCourse map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCourse(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      courseTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}course_title'],
      )!,
      courseCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}course_code'],
      ),
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      schoolId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}school_id'],
      ),
      yearId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}year_id'],
      ),
      termId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}term_id'],
      ),
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      ),
      professorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}professor_id'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $LocalCoursesTable createAlias(String alias) {
    return $LocalCoursesTable(attachedDatabase, alias);
  }
}

class LocalCourse extends DataClass implements Insertable<LocalCourse> {
  final String id;
  final String userId;
  final String courseTitle;
  final String? courseCode;
  final String? summary;
  final String? schoolId;
  final String? yearId;
  final String? termId;
  final String? subjectId;
  final String? professorId;
  final String? metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String syncStatus;
  const LocalCourse({
    required this.id,
    required this.userId,
    required this.courseTitle,
    this.courseCode,
    this.summary,
    this.schoolId,
    this.yearId,
    this.termId,
    this.subjectId,
    this.professorId,
    this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['course_title'] = Variable<String>(courseTitle);
    if (!nullToAbsent || courseCode != null) {
      map['course_code'] = Variable<String>(courseCode);
    }
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    if (!nullToAbsent || schoolId != null) {
      map['school_id'] = Variable<String>(schoolId);
    }
    if (!nullToAbsent || yearId != null) {
      map['year_id'] = Variable<String>(yearId);
    }
    if (!nullToAbsent || termId != null) {
      map['term_id'] = Variable<String>(termId);
    }
    if (!nullToAbsent || subjectId != null) {
      map['subject_id'] = Variable<String>(subjectId);
    }
    if (!nullToAbsent || professorId != null) {
      map['professor_id'] = Variable<String>(professorId);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalCoursesCompanion toCompanion(bool nullToAbsent) {
    return LocalCoursesCompanion(
      id: Value(id),
      userId: Value(userId),
      courseTitle: Value(courseTitle),
      courseCode: courseCode == null && nullToAbsent
          ? const Value.absent()
          : Value(courseCode),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      schoolId: schoolId == null && nullToAbsent
          ? const Value.absent()
          : Value(schoolId),
      yearId: yearId == null && nullToAbsent
          ? const Value.absent()
          : Value(yearId),
      termId: termId == null && nullToAbsent
          ? const Value.absent()
          : Value(termId),
      subjectId: subjectId == null && nullToAbsent
          ? const Value.absent()
          : Value(subjectId),
      professorId: professorId == null && nullToAbsent
          ? const Value.absent()
          : Value(professorId),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalCourse.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCourse(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      courseTitle: serializer.fromJson<String>(json['courseTitle']),
      courseCode: serializer.fromJson<String?>(json['courseCode']),
      summary: serializer.fromJson<String?>(json['summary']),
      schoolId: serializer.fromJson<String?>(json['schoolId']),
      yearId: serializer.fromJson<String?>(json['yearId']),
      termId: serializer.fromJson<String?>(json['termId']),
      subjectId: serializer.fromJson<String?>(json['subjectId']),
      professorId: serializer.fromJson<String?>(json['professorId']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'courseTitle': serializer.toJson<String>(courseTitle),
      'courseCode': serializer.toJson<String?>(courseCode),
      'summary': serializer.toJson<String?>(summary),
      'schoolId': serializer.toJson<String?>(schoolId),
      'yearId': serializer.toJson<String?>(yearId),
      'termId': serializer.toJson<String?>(termId),
      'subjectId': serializer.toJson<String?>(subjectId),
      'professorId': serializer.toJson<String?>(professorId),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalCourse copyWith({
    String? id,
    String? userId,
    String? courseTitle,
    Value<String?> courseCode = const Value.absent(),
    Value<String?> summary = const Value.absent(),
    Value<String?> schoolId = const Value.absent(),
    Value<String?> yearId = const Value.absent(),
    Value<String?> termId = const Value.absent(),
    Value<String?> subjectId = const Value.absent(),
    Value<String?> professorId = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? syncStatus,
  }) => LocalCourse(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    courseTitle: courseTitle ?? this.courseTitle,
    courseCode: courseCode.present ? courseCode.value : this.courseCode,
    summary: summary.present ? summary.value : this.summary,
    schoolId: schoolId.present ? schoolId.value : this.schoolId,
    yearId: yearId.present ? yearId.value : this.yearId,
    termId: termId.present ? termId.value : this.termId,
    subjectId: subjectId.present ? subjectId.value : this.subjectId,
    professorId: professorId.present ? professorId.value : this.professorId,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  LocalCourse copyWithCompanion(LocalCoursesCompanion data) {
    return LocalCourse(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      courseTitle: data.courseTitle.present
          ? data.courseTitle.value
          : this.courseTitle,
      courseCode: data.courseCode.present
          ? data.courseCode.value
          : this.courseCode,
      summary: data.summary.present ? data.summary.value : this.summary,
      schoolId: data.schoolId.present ? data.schoolId.value : this.schoolId,
      yearId: data.yearId.present ? data.yearId.value : this.yearId,
      termId: data.termId.present ? data.termId.value : this.termId,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      professorId: data.professorId.present
          ? data.professorId.value
          : this.professorId,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCourse(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('courseTitle: $courseTitle, ')
          ..write('courseCode: $courseCode, ')
          ..write('summary: $summary, ')
          ..write('schoolId: $schoolId, ')
          ..write('yearId: $yearId, ')
          ..write('termId: $termId, ')
          ..write('subjectId: $subjectId, ')
          ..write('professorId: $professorId, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    courseTitle,
    courseCode,
    summary,
    schoolId,
    yearId,
    termId,
    subjectId,
    professorId,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCourse &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.courseTitle == this.courseTitle &&
          other.courseCode == this.courseCode &&
          other.summary == this.summary &&
          other.schoolId == this.schoolId &&
          other.yearId == this.yearId &&
          other.termId == this.termId &&
          other.subjectId == this.subjectId &&
          other.professorId == this.professorId &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus);
}

class LocalCoursesCompanion extends UpdateCompanion<LocalCourse> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> courseTitle;
  final Value<String?> courseCode;
  final Value<String?> summary;
  final Value<String?> schoolId;
  final Value<String?> yearId;
  final Value<String?> termId;
  final Value<String?> subjectId;
  final Value<String?> professorId;
  final Value<String?> metadataJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const LocalCoursesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.courseTitle = const Value.absent(),
    this.courseCode = const Value.absent(),
    this.summary = const Value.absent(),
    this.schoolId = const Value.absent(),
    this.yearId = const Value.absent(),
    this.termId = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.professorId = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCoursesCompanion.insert({
    required String id,
    required String userId,
    required String courseTitle,
    this.courseCode = const Value.absent(),
    this.summary = const Value.absent(),
    this.schoolId = const Value.absent(),
    this.yearId = const Value.absent(),
    this.termId = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.professorId = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       courseTitle = Value(courseTitle);
  static Insertable<LocalCourse> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? courseTitle,
    Expression<String>? courseCode,
    Expression<String>? summary,
    Expression<String>? schoolId,
    Expression<String>? yearId,
    Expression<String>? termId,
    Expression<String>? subjectId,
    Expression<String>? professorId,
    Expression<String>? metadataJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (courseTitle != null) 'course_title': courseTitle,
      if (courseCode != null) 'course_code': courseCode,
      if (summary != null) 'summary': summary,
      if (schoolId != null) 'school_id': schoolId,
      if (yearId != null) 'year_id': yearId,
      if (termId != null) 'term_id': termId,
      if (subjectId != null) 'subject_id': subjectId,
      if (professorId != null) 'professor_id': professorId,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCoursesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? courseTitle,
    Value<String?>? courseCode,
    Value<String?>? summary,
    Value<String?>? schoolId,
    Value<String?>? yearId,
    Value<String?>? termId,
    Value<String?>? subjectId,
    Value<String?>? professorId,
    Value<String?>? metadataJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return LocalCoursesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      courseTitle: courseTitle ?? this.courseTitle,
      courseCode: courseCode ?? this.courseCode,
      summary: summary ?? this.summary,
      schoolId: schoolId ?? this.schoolId,
      yearId: yearId ?? this.yearId,
      termId: termId ?? this.termId,
      subjectId: subjectId ?? this.subjectId,
      professorId: professorId ?? this.professorId,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (courseTitle.present) {
      map['course_title'] = Variable<String>(courseTitle.value);
    }
    if (courseCode.present) {
      map['course_code'] = Variable<String>(courseCode.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (schoolId.present) {
      map['school_id'] = Variable<String>(schoolId.value);
    }
    if (yearId.present) {
      map['year_id'] = Variable<String>(yearId.value);
    }
    if (termId.present) {
      map['term_id'] = Variable<String>(termId.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (professorId.present) {
      map['professor_id'] = Variable<String>(professorId.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCoursesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('courseTitle: $courseTitle, ')
          ..write('courseCode: $courseCode, ')
          ..write('summary: $summary, ')
          ..write('schoolId: $schoolId, ')
          ..write('yearId: $yearId, ')
          ..write('termId: $termId, ')
          ..write('subjectId: $subjectId, ')
          ..write('professorId: $professorId, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCourseAttributesTable extends LocalCourseAttributes
    with TableInfo<$LocalCourseAttributesTable, LocalCourseAttribute> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCourseAttributesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attributeTypeMeta = const VerificationMeta(
    'attributeType',
  );
  @override
  late final GeneratedColumn<String> attributeType = GeneratedColumn<String>(
    'attribute_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attributeNameMeta = const VerificationMeta(
    'attributeName',
  );
  @override
  late final GeneratedColumn<String> attributeName = GeneratedColumn<String>(
    'attribute_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local_only'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    attributeType,
    attributeName,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_course_attributes';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCourseAttribute> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('attribute_type')) {
      context.handle(
        _attributeTypeMeta,
        attributeType.isAcceptableOrUnknown(
          data['attribute_type']!,
          _attributeTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attributeTypeMeta);
    }
    if (data.containsKey('attribute_name')) {
      context.handle(
        _attributeNameMeta,
        attributeName.isAcceptableOrUnknown(
          data['attribute_name']!,
          _attributeNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attributeNameMeta);
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalCourseAttribute map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCourseAttribute(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      attributeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attribute_type'],
      )!,
      attributeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attribute_name'],
      )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $LocalCourseAttributesTable createAlias(String alias) {
    return $LocalCourseAttributesTable(attachedDatabase, alias);
  }
}

class LocalCourseAttribute extends DataClass
    implements Insertable<LocalCourseAttribute> {
  final String id;
  final String userId;
  final String attributeType;
  final String attributeName;
  final String? metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String syncStatus;
  const LocalCourseAttribute({
    required this.id,
    required this.userId,
    required this.attributeType,
    required this.attributeName,
    this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['attribute_type'] = Variable<String>(attributeType);
    map['attribute_name'] = Variable<String>(attributeName);
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalCourseAttributesCompanion toCompanion(bool nullToAbsent) {
    return LocalCourseAttributesCompanion(
      id: Value(id),
      userId: Value(userId),
      attributeType: Value(attributeType),
      attributeName: Value(attributeName),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalCourseAttribute.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCourseAttribute(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      attributeType: serializer.fromJson<String>(json['attributeType']),
      attributeName: serializer.fromJson<String>(json['attributeName']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'attributeType': serializer.toJson<String>(attributeType),
      'attributeName': serializer.toJson<String>(attributeName),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalCourseAttribute copyWith({
    String? id,
    String? userId,
    String? attributeType,
    String? attributeName,
    Value<String?> metadataJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? syncStatus,
  }) => LocalCourseAttribute(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    attributeType: attributeType ?? this.attributeType,
    attributeName: attributeName ?? this.attributeName,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  LocalCourseAttribute copyWithCompanion(LocalCourseAttributesCompanion data) {
    return LocalCourseAttribute(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      attributeType: data.attributeType.present
          ? data.attributeType.value
          : this.attributeType,
      attributeName: data.attributeName.present
          ? data.attributeName.value
          : this.attributeName,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCourseAttribute(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('attributeType: $attributeType, ')
          ..write('attributeName: $attributeName, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    attributeType,
    attributeName,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCourseAttribute &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.attributeType == this.attributeType &&
          other.attributeName == this.attributeName &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus);
}

class LocalCourseAttributesCompanion
    extends UpdateCompanion<LocalCourseAttribute> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> attributeType;
  final Value<String> attributeName;
  final Value<String?> metadataJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const LocalCourseAttributesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.attributeType = const Value.absent(),
    this.attributeName = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCourseAttributesCompanion.insert({
    required String id,
    required String userId,
    required String attributeType,
    required String attributeName,
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       attributeType = Value(attributeType),
       attributeName = Value(attributeName);
  static Insertable<LocalCourseAttribute> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? attributeType,
    Expression<String>? attributeName,
    Expression<String>? metadataJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (attributeType != null) 'attribute_type': attributeType,
      if (attributeName != null) 'attribute_name': attributeName,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCourseAttributesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? attributeType,
    Value<String>? attributeName,
    Value<String?>? metadataJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return LocalCourseAttributesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      attributeType: attributeType ?? this.attributeType,
      attributeName: attributeName ?? this.attributeName,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (attributeType.present) {
      map['attribute_type'] = Variable<String>(attributeType.value);
    }
    if (attributeName.present) {
      map['attribute_name'] = Variable<String>(attributeName.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCourseAttributesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('attributeType: $attributeType, ')
          ..write('attributeName: $attributeName, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalAnnouncementsTable extends LocalAnnouncements
    with TableInfo<$LocalAnnouncementsTable, LocalAnnouncement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAnnouncementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startSidMeta = const VerificationMeta(
    'startSid',
  );
  @override
  late final GeneratedColumn<String> startSid = GeneratedColumn<String>(
    'start_sid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endSidMeta = const VerificationMeta('endSid');
  @override
  late final GeneratedColumn<String> endSid = GeneratedColumn<String>(
    'end_sid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relatedTopicTitleMeta = const VerificationMeta(
    'relatedTopicTitle',
  );
  @override
  late final GeneratedColumn<String> relatedTopicTitle =
      GeneratedColumn<String>(
        'related_topic_title',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _datetimeParametersJsonMeta =
      const VerificationMeta('datetimeParametersJson');
  @override
  late final GeneratedColumn<String> datetimeParametersJson =
      GeneratedColumn<String>(
        'datetime_parameters_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local_only'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    type,
    title,
    description,
    location,
    startSid,
    endSid,
    relatedTopicTitle,
    datetimeParametersJson,
    completedAt,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_announcements';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAnnouncement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('start_sid')) {
      context.handle(
        _startSidMeta,
        startSid.isAcceptableOrUnknown(data['start_sid']!, _startSidMeta),
      );
    }
    if (data.containsKey('end_sid')) {
      context.handle(
        _endSidMeta,
        endSid.isAcceptableOrUnknown(data['end_sid']!, _endSidMeta),
      );
    }
    if (data.containsKey('related_topic_title')) {
      context.handle(
        _relatedTopicTitleMeta,
        relatedTopicTitle.isAcceptableOrUnknown(
          data['related_topic_title']!,
          _relatedTopicTitleMeta,
        ),
      );
    }
    if (data.containsKey('datetime_parameters_json')) {
      context.handle(
        _datetimeParametersJsonMeta,
        datetimeParametersJson.isAcceptableOrUnknown(
          data['datetime_parameters_json']!,
          _datetimeParametersJsonMeta,
        ),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalAnnouncement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAnnouncement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      startSid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_sid'],
      ),
      endSid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_sid'],
      ),
      relatedTopicTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}related_topic_title'],
      ),
      datetimeParametersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}datetime_parameters_json'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $LocalAnnouncementsTable createAlias(String alias) {
    return $LocalAnnouncementsTable(attachedDatabase, alias);
  }
}

class LocalAnnouncement extends DataClass
    implements Insertable<LocalAnnouncement> {
  final String id;
  final String userId;
  final String lectureId;
  final String type;
  final String title;
  final String? description;
  final String? location;
  final String? startSid;
  final String? endSid;
  final String? relatedTopicTitle;
  final String? datetimeParametersJson;
  final DateTime? completedAt;
  final String? metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String syncStatus;
  const LocalAnnouncement({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.type,
    required this.title,
    this.description,
    this.location,
    this.startSid,
    this.endSid,
    this.relatedTopicTitle,
    this.datetimeParametersJson,
    this.completedAt,
    this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || startSid != null) {
      map['start_sid'] = Variable<String>(startSid);
    }
    if (!nullToAbsent || endSid != null) {
      map['end_sid'] = Variable<String>(endSid);
    }
    if (!nullToAbsent || relatedTopicTitle != null) {
      map['related_topic_title'] = Variable<String>(relatedTopicTitle);
    }
    if (!nullToAbsent || datetimeParametersJson != null) {
      map['datetime_parameters_json'] = Variable<String>(
        datetimeParametersJson,
      );
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  LocalAnnouncementsCompanion toCompanion(bool nullToAbsent) {
    return LocalAnnouncementsCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      type: Value(type),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      startSid: startSid == null && nullToAbsent
          ? const Value.absent()
          : Value(startSid),
      endSid: endSid == null && nullToAbsent
          ? const Value.absent()
          : Value(endSid),
      relatedTopicTitle: relatedTopicTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(relatedTopicTitle),
      datetimeParametersJson: datetimeParametersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(datetimeParametersJson),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalAnnouncement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAnnouncement(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      location: serializer.fromJson<String?>(json['location']),
      startSid: serializer.fromJson<String?>(json['startSid']),
      endSid: serializer.fromJson<String?>(json['endSid']),
      relatedTopicTitle: serializer.fromJson<String?>(
        json['relatedTopicTitle'],
      ),
      datetimeParametersJson: serializer.fromJson<String?>(
        json['datetimeParametersJson'],
      ),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'location': serializer.toJson<String?>(location),
      'startSid': serializer.toJson<String?>(startSid),
      'endSid': serializer.toJson<String?>(endSid),
      'relatedTopicTitle': serializer.toJson<String?>(relatedTopicTitle),
      'datetimeParametersJson': serializer.toJson<String?>(
        datetimeParametersJson,
      ),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalAnnouncement copyWith({
    String? id,
    String? userId,
    String? lectureId,
    String? type,
    String? title,
    Value<String?> description = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> startSid = const Value.absent(),
    Value<String?> endSid = const Value.absent(),
    Value<String?> relatedTopicTitle = const Value.absent(),
    Value<String?> datetimeParametersJson = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? syncStatus,
  }) => LocalAnnouncement(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    type: type ?? this.type,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    location: location.present ? location.value : this.location,
    startSid: startSid.present ? startSid.value : this.startSid,
    endSid: endSid.present ? endSid.value : this.endSid,
    relatedTopicTitle: relatedTopicTitle.present
        ? relatedTopicTitle.value
        : this.relatedTopicTitle,
    datetimeParametersJson: datetimeParametersJson.present
        ? datetimeParametersJson.value
        : this.datetimeParametersJson,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  LocalAnnouncement copyWithCompanion(LocalAnnouncementsCompanion data) {
    return LocalAnnouncement(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      location: data.location.present ? data.location.value : this.location,
      startSid: data.startSid.present ? data.startSid.value : this.startSid,
      endSid: data.endSid.present ? data.endSid.value : this.endSid,
      relatedTopicTitle: data.relatedTopicTitle.present
          ? data.relatedTopicTitle.value
          : this.relatedTopicTitle,
      datetimeParametersJson: data.datetimeParametersJson.present
          ? data.datetimeParametersJson.value
          : this.datetimeParametersJson,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAnnouncement(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('location: $location, ')
          ..write('startSid: $startSid, ')
          ..write('endSid: $endSid, ')
          ..write('relatedTopicTitle: $relatedTopicTitle, ')
          ..write('datetimeParametersJson: $datetimeParametersJson, ')
          ..write('completedAt: $completedAt, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    lectureId,
    type,
    title,
    description,
    location,
    startSid,
    endSid,
    relatedTopicTitle,
    datetimeParametersJson,
    completedAt,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAnnouncement &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.type == this.type &&
          other.title == this.title &&
          other.description == this.description &&
          other.location == this.location &&
          other.startSid == this.startSid &&
          other.endSid == this.endSid &&
          other.relatedTopicTitle == this.relatedTopicTitle &&
          other.datetimeParametersJson == this.datetimeParametersJson &&
          other.completedAt == this.completedAt &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus);
}

class LocalAnnouncementsCompanion extends UpdateCompanion<LocalAnnouncement> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<String> type;
  final Value<String> title;
  final Value<String?> description;
  final Value<String?> location;
  final Value<String?> startSid;
  final Value<String?> endSid;
  final Value<String?> relatedTopicTitle;
  final Value<String?> datetimeParametersJson;
  final Value<DateTime?> completedAt;
  final Value<String?> metadataJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const LocalAnnouncementsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.location = const Value.absent(),
    this.startSid = const Value.absent(),
    this.endSid = const Value.absent(),
    this.relatedTopicTitle = const Value.absent(),
    this.datetimeParametersJson = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAnnouncementsCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    required String type,
    required String title,
    this.description = const Value.absent(),
    this.location = const Value.absent(),
    this.startSid = const Value.absent(),
    this.endSid = const Value.absent(),
    this.relatedTopicTitle = const Value.absent(),
    this.datetimeParametersJson = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       type = Value(type),
       title = Value(title);
  static Insertable<LocalAnnouncement> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? location,
    Expression<String>? startSid,
    Expression<String>? endSid,
    Expression<String>? relatedTopicTitle,
    Expression<String>? datetimeParametersJson,
    Expression<DateTime>? completedAt,
    Expression<String>? metadataJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      if (startSid != null) 'start_sid': startSid,
      if (endSid != null) 'end_sid': endSid,
      if (relatedTopicTitle != null) 'related_topic_title': relatedTopicTitle,
      if (datetimeParametersJson != null)
        'datetime_parameters_json': datetimeParametersJson,
      if (completedAt != null) 'completed_at': completedAt,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAnnouncementsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<String>? type,
    Value<String>? title,
    Value<String?>? description,
    Value<String?>? location,
    Value<String?>? startSid,
    Value<String?>? endSid,
    Value<String?>? relatedTopicTitle,
    Value<String?>? datetimeParametersJson,
    Value<DateTime?>? completedAt,
    Value<String?>? metadataJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return LocalAnnouncementsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startSid: startSid ?? this.startSid,
      endSid: endSid ?? this.endSid,
      relatedTopicTitle: relatedTopicTitle ?? this.relatedTopicTitle,
      datetimeParametersJson:
          datetimeParametersJson ?? this.datetimeParametersJson,
      completedAt: completedAt ?? this.completedAt,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (startSid.present) {
      map['start_sid'] = Variable<String>(startSid.value);
    }
    if (endSid.present) {
      map['end_sid'] = Variable<String>(endSid.value);
    }
    if (relatedTopicTitle.present) {
      map['related_topic_title'] = Variable<String>(relatedTopicTitle.value);
    }
    if (datetimeParametersJson.present) {
      map['datetime_parameters_json'] = Variable<String>(
        datetimeParametersJson.value,
      );
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAnnouncementsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('location: $location, ')
          ..write('startSid: $startSid, ')
          ..write('endSid: $endSid, ')
          ..write('relatedTopicTitle: $relatedTopicTitle, ')
          ..write('datetimeParametersJson: $datetimeParametersJson, ')
          ..write('completedAt: $completedAt, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalLectureMomentsTable extends LocalLectureMoments
    with TableInfo<$LocalLectureMomentsTable, LocalLectureMoment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalLectureMomentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _momentTypeMeta = const VerificationMeta(
    'momentType',
  );
  @override
  late final GeneratedColumn<String> momentType = GeneratedColumn<String>(
    'moment_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteTextMeta = const VerificationMeta(
    'noteText',
  );
  @override
  late final GeneratedColumn<String> noteText = GeneratedColumn<String>(
    'note_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampSecMeta = const VerificationMeta(
    'timestampSec',
  );
  @override
  late final GeneratedColumn<int> timestampSec = GeneratedColumn<int>(
    'timestamp_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    momentType,
    noteText,
    timestampSec,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_lecture_moments';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalLectureMoment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('moment_type')) {
      context.handle(
        _momentTypeMeta,
        momentType.isAcceptableOrUnknown(data['moment_type']!, _momentTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_momentTypeMeta);
    }
    if (data.containsKey('note_text')) {
      context.handle(
        _noteTextMeta,
        noteText.isAcceptableOrUnknown(data['note_text']!, _noteTextMeta),
      );
    }
    if (data.containsKey('timestamp_sec')) {
      context.handle(
        _timestampSecMeta,
        timestampSec.isAcceptableOrUnknown(
          data['timestamp_sec']!,
          _timestampSecMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampSecMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalLectureMoment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalLectureMoment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      momentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}moment_type'],
      )!,
      noteText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_text'],
      ),
      timestampSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_sec'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      )!,
    );
  }

  @override
  $LocalLectureMomentsTable createAlias(String alias) {
    return $LocalLectureMomentsTable(attachedDatabase, alias);
  }
}

class LocalLectureMoment extends DataClass
    implements Insertable<LocalLectureMoment> {
  final String id;
  final String userId;
  final String lectureId;
  final String momentType;
  final String? noteText;
  final int timestampSec;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime lastSyncedAt;
  const LocalLectureMoment({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.momentType,
    this.noteText,
    required this.timestampSec,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    map['moment_type'] = Variable<String>(momentType);
    if (!nullToAbsent || noteText != null) {
      map['note_text'] = Variable<String>(noteText);
    }
    map['timestamp_sec'] = Variable<int>(timestampSec);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  LocalLectureMomentsCompanion toCompanion(bool nullToAbsent) {
    return LocalLectureMomentsCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      momentType: Value(momentType),
      noteText: noteText == null && nullToAbsent
          ? const Value.absent()
          : Value(noteText),
      timestampSec: Value(timestampSec),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory LocalLectureMoment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalLectureMoment(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      momentType: serializer.fromJson<String>(json['momentType']),
      noteText: serializer.fromJson<String?>(json['noteText']),
      timestampSec: serializer.fromJson<int>(json['timestampSec']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'momentType': serializer.toJson<String>(momentType),
      'noteText': serializer.toJson<String?>(noteText),
      'timestampSec': serializer.toJson<int>(timestampSec),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  LocalLectureMoment copyWith({
    String? id,
    String? userId,
    String? lectureId,
    String? momentType,
    Value<String?> noteText = const Value.absent(),
    int? timestampSec,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? lastSyncedAt,
  }) => LocalLectureMoment(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    momentType: momentType ?? this.momentType,
    noteText: noteText.present ? noteText.value : this.noteText,
    timestampSec: timestampSec ?? this.timestampSec,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
  LocalLectureMoment copyWithCompanion(LocalLectureMomentsCompanion data) {
    return LocalLectureMoment(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      momentType: data.momentType.present
          ? data.momentType.value
          : this.momentType,
      noteText: data.noteText.present ? data.noteText.value : this.noteText,
      timestampSec: data.timestampSec.present
          ? data.timestampSec.value
          : this.timestampSec,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalLectureMoment(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('momentType: $momentType, ')
          ..write('noteText: $noteText, ')
          ..write('timestampSec: $timestampSec, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    lectureId,
    momentType,
    noteText,
    timestampSec,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalLectureMoment &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.momentType == this.momentType &&
          other.noteText == this.noteText &&
          other.timestampSec == this.timestampSec &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class LocalLectureMomentsCompanion extends UpdateCompanion<LocalLectureMoment> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<String> momentType;
  final Value<String?> noteText;
  final Value<int> timestampSec;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const LocalLectureMomentsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.momentType = const Value.absent(),
    this.noteText = const Value.absent(),
    this.timestampSec = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalLectureMomentsCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    required String momentType,
    this.noteText = const Value.absent(),
    required int timestampSec,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       momentType = Value(momentType),
       timestampSec = Value(timestampSec);
  static Insertable<LocalLectureMoment> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<String>? momentType,
    Expression<String>? noteText,
    Expression<int>? timestampSec,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (momentType != null) 'moment_type': momentType,
      if (noteText != null) 'note_text': noteText,
      if (timestampSec != null) 'timestamp_sec': timestampSec,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalLectureMomentsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<String>? momentType,
    Value<String?>? noteText,
    Value<int>? timestampSec,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return LocalLectureMomentsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      momentType: momentType ?? this.momentType,
      noteText: noteText ?? this.noteText,
      timestampSec: timestampSec ?? this.timestampSec,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (momentType.present) {
      map['moment_type'] = Variable<String>(momentType.value);
    }
    if (noteText.present) {
      map['note_text'] = Variable<String>(noteText.value);
    }
    if (timestampSec.present) {
      map['timestamp_sec'] = Variable<int>(timestampSec.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalLectureMomentsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('momentType: $momentType, ')
          ..write('noteText: $noteText, ')
          ..write('timestampSec: $timestampSec, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalAsrModelsTable extends LocalAsrModels
    with TableInfo<$LocalAsrModelsTable, LocalAsrModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalAsrModelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupKeyMeta = const VerificationMeta(
    'groupKey',
  );
  @override
  late final GeneratedColumn<String> groupKey = GeneratedColumn<String>(
    'group_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _engineCompatVersionMeta =
      const VerificationMeta('engineCompatVersion');
  @override
  late final GeneratedColumn<int> engineCompatVersion = GeneratedColumn<int>(
    'engine_compat_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelVersionMeta = const VerificationMeta(
    'modelVersion',
  );
  @override
  late final GeneratedColumn<int> modelVersion = GeneratedColumn<int>(
    'model_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadedAtMeta = const VerificationMeta(
    'downloadedAt',
  );
  @override
  late final GeneratedColumn<DateTime> downloadedAt = GeneratedColumn<DateTime>(
    'downloaded_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupKey,
    modelId,
    engineCompatVersion,
    modelVersion,
    localPath,
    sizeBytes,
    status,
    downloadedAt,
    lastUsedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_asr_models';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalAsrModel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_key')) {
      context.handle(
        _groupKeyMeta,
        groupKey.isAcceptableOrUnknown(data['group_key']!, _groupKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_groupKeyMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('engine_compat_version')) {
      context.handle(
        _engineCompatVersionMeta,
        engineCompatVersion.isAcceptableOrUnknown(
          data['engine_compat_version']!,
          _engineCompatVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_engineCompatVersionMeta);
    }
    if (data.containsKey('model_version')) {
      context.handle(
        _modelVersionMeta,
        modelVersion.isAcceptableOrUnknown(
          data['model_version']!,
          _modelVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_modelVersionMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('downloaded_at')) {
      context.handle(
        _downloadedAtMeta,
        downloadedAt.isAcceptableOrUnknown(
          data['downloaded_at']!,
          _downloadedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupKey};
  @override
  LocalAsrModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalAsrModel(
      groupKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_key'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      engineCompatVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}engine_compat_version'],
      )!,
      modelVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}model_version'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      downloadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}downloaded_at'],
      ),
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
    );
  }

  @override
  $LocalAsrModelsTable createAlias(String alias) {
    return $LocalAsrModelsTable(attachedDatabase, alias);
  }
}

class LocalAsrModel extends DataClass implements Insertable<LocalAsrModel> {
  final String groupKey;
  final String modelId;
  final int engineCompatVersion;
  final int modelVersion;
  final String localPath;
  final int sizeBytes;
  final String status;
  final DateTime? downloadedAt;
  final DateTime? lastUsedAt;
  const LocalAsrModel({
    required this.groupKey,
    required this.modelId,
    required this.engineCompatVersion,
    required this.modelVersion,
    required this.localPath,
    required this.sizeBytes,
    required this.status,
    this.downloadedAt,
    this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_key'] = Variable<String>(groupKey);
    map['model_id'] = Variable<String>(modelId);
    map['engine_compat_version'] = Variable<int>(engineCompatVersion);
    map['model_version'] = Variable<int>(modelVersion);
    map['local_path'] = Variable<String>(localPath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || downloadedAt != null) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt);
    }
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    return map;
  }

  LocalAsrModelsCompanion toCompanion(bool nullToAbsent) {
    return LocalAsrModelsCompanion(
      groupKey: Value(groupKey),
      modelId: Value(modelId),
      engineCompatVersion: Value(engineCompatVersion),
      modelVersion: Value(modelVersion),
      localPath: Value(localPath),
      sizeBytes: Value(sizeBytes),
      status: Value(status),
      downloadedAt: downloadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(downloadedAt),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
    );
  }

  factory LocalAsrModel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalAsrModel(
      groupKey: serializer.fromJson<String>(json['groupKey']),
      modelId: serializer.fromJson<String>(json['modelId']),
      engineCompatVersion: serializer.fromJson<int>(
        json['engineCompatVersion'],
      ),
      modelVersion: serializer.fromJson<int>(json['modelVersion']),
      localPath: serializer.fromJson<String>(json['localPath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      status: serializer.fromJson<String>(json['status']),
      downloadedAt: serializer.fromJson<DateTime?>(json['downloadedAt']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupKey': serializer.toJson<String>(groupKey),
      'modelId': serializer.toJson<String>(modelId),
      'engineCompatVersion': serializer.toJson<int>(engineCompatVersion),
      'modelVersion': serializer.toJson<int>(modelVersion),
      'localPath': serializer.toJson<String>(localPath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'status': serializer.toJson<String>(status),
      'downloadedAt': serializer.toJson<DateTime?>(downloadedAt),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
    };
  }

  LocalAsrModel copyWith({
    String? groupKey,
    String? modelId,
    int? engineCompatVersion,
    int? modelVersion,
    String? localPath,
    int? sizeBytes,
    String? status,
    Value<DateTime?> downloadedAt = const Value.absent(),
    Value<DateTime?> lastUsedAt = const Value.absent(),
  }) => LocalAsrModel(
    groupKey: groupKey ?? this.groupKey,
    modelId: modelId ?? this.modelId,
    engineCompatVersion: engineCompatVersion ?? this.engineCompatVersion,
    modelVersion: modelVersion ?? this.modelVersion,
    localPath: localPath ?? this.localPath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    status: status ?? this.status,
    downloadedAt: downloadedAt.present ? downloadedAt.value : this.downloadedAt,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
  );
  LocalAsrModel copyWithCompanion(LocalAsrModelsCompanion data) {
    return LocalAsrModel(
      groupKey: data.groupKey.present ? data.groupKey.value : this.groupKey,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      engineCompatVersion: data.engineCompatVersion.present
          ? data.engineCompatVersion.value
          : this.engineCompatVersion,
      modelVersion: data.modelVersion.present
          ? data.modelVersion.value
          : this.modelVersion,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      status: data.status.present ? data.status.value : this.status,
      downloadedAt: data.downloadedAt.present
          ? data.downloadedAt.value
          : this.downloadedAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalAsrModel(')
          ..write('groupKey: $groupKey, ')
          ..write('modelId: $modelId, ')
          ..write('engineCompatVersion: $engineCompatVersion, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('status: $status, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupKey,
    modelId,
    engineCompatVersion,
    modelVersion,
    localPath,
    sizeBytes,
    status,
    downloadedAt,
    lastUsedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalAsrModel &&
          other.groupKey == this.groupKey &&
          other.modelId == this.modelId &&
          other.engineCompatVersion == this.engineCompatVersion &&
          other.modelVersion == this.modelVersion &&
          other.localPath == this.localPath &&
          other.sizeBytes == this.sizeBytes &&
          other.status == this.status &&
          other.downloadedAt == this.downloadedAt &&
          other.lastUsedAt == this.lastUsedAt);
}

class LocalAsrModelsCompanion extends UpdateCompanion<LocalAsrModel> {
  final Value<String> groupKey;
  final Value<String> modelId;
  final Value<int> engineCompatVersion;
  final Value<int> modelVersion;
  final Value<String> localPath;
  final Value<int> sizeBytes;
  final Value<String> status;
  final Value<DateTime?> downloadedAt;
  final Value<DateTime?> lastUsedAt;
  final Value<int> rowid;
  const LocalAsrModelsCompanion({
    this.groupKey = const Value.absent(),
    this.modelId = const Value.absent(),
    this.engineCompatVersion = const Value.absent(),
    this.modelVersion = const Value.absent(),
    this.localPath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.status = const Value.absent(),
    this.downloadedAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalAsrModelsCompanion.insert({
    required String groupKey,
    required String modelId,
    required int engineCompatVersion,
    required int modelVersion,
    required String localPath,
    required int sizeBytes,
    required String status,
    this.downloadedAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupKey = Value(groupKey),
       modelId = Value(modelId),
       engineCompatVersion = Value(engineCompatVersion),
       modelVersion = Value(modelVersion),
       localPath = Value(localPath),
       sizeBytes = Value(sizeBytes),
       status = Value(status);
  static Insertable<LocalAsrModel> custom({
    Expression<String>? groupKey,
    Expression<String>? modelId,
    Expression<int>? engineCompatVersion,
    Expression<int>? modelVersion,
    Expression<String>? localPath,
    Expression<int>? sizeBytes,
    Expression<String>? status,
    Expression<DateTime>? downloadedAt,
    Expression<DateTime>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupKey != null) 'group_key': groupKey,
      if (modelId != null) 'model_id': modelId,
      if (engineCompatVersion != null)
        'engine_compat_version': engineCompatVersion,
      if (modelVersion != null) 'model_version': modelVersion,
      if (localPath != null) 'local_path': localPath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (status != null) 'status': status,
      if (downloadedAt != null) 'downloaded_at': downloadedAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalAsrModelsCompanion copyWith({
    Value<String>? groupKey,
    Value<String>? modelId,
    Value<int>? engineCompatVersion,
    Value<int>? modelVersion,
    Value<String>? localPath,
    Value<int>? sizeBytes,
    Value<String>? status,
    Value<DateTime?>? downloadedAt,
    Value<DateTime?>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return LocalAsrModelsCompanion(
      groupKey: groupKey ?? this.groupKey,
      modelId: modelId ?? this.modelId,
      engineCompatVersion: engineCompatVersion ?? this.engineCompatVersion,
      modelVersion: modelVersion ?? this.modelVersion,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      status: status ?? this.status,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupKey.present) {
      map['group_key'] = Variable<String>(groupKey.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (engineCompatVersion.present) {
      map['engine_compat_version'] = Variable<int>(engineCompatVersion.value);
    }
    if (modelVersion.present) {
      map['model_version'] = Variable<int>(modelVersion.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (downloadedAt.present) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalAsrModelsCompanion(')
          ..write('groupKey: $groupKey, ')
          ..write('modelId: $modelId, ')
          ..write('engineCompatVersion: $engineCompatVersion, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('status: $status, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalFunFactsTable extends LocalFunFacts
    with TableInfo<$LocalFunFactsTable, LocalFunFact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFunFactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hookMeta = const VerificationMeta('hook');
  @override
  late final GeneratedColumn<String> hook = GeneratedColumn<String>(
    'hook',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reactionMeta = const VerificationMeta(
    'reaction',
  );
  @override
  late final GeneratedColumn<String> reaction = GeneratedColumn<String>(
    'reaction',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    title,
    hook,
    body,
    metadataJson,
    reaction,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_fun_facts';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFunFact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('hook')) {
      context.handle(
        _hookMeta,
        hook.isAcceptableOrUnknown(data['hook']!, _hookMeta),
      );
    } else if (isInserting) {
      context.missing(_hookMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('reaction')) {
      context.handle(
        _reactionMeta,
        reaction.isAcceptableOrUnknown(data['reaction']!, _reactionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalFunFact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFunFact(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      hook: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hook'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      reaction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reaction'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      )!,
    );
  }

  @override
  $LocalFunFactsTable createAlias(String alias) {
    return $LocalFunFactsTable(attachedDatabase, alias);
  }
}

class LocalFunFact extends DataClass implements Insertable<LocalFunFact> {
  final String id;
  final String userId;
  final String lectureId;
  final String? title;
  final String hook;
  final String body;
  final String? metadataJson;
  final String? reaction;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime lastSyncedAt;
  const LocalFunFact({
    required this.id,
    required this.userId,
    required this.lectureId,
    this.title,
    required this.hook,
    required this.body,
    this.metadataJson,
    this.reaction,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['hook'] = Variable<String>(hook);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    if (!nullToAbsent || reaction != null) {
      map['reaction'] = Variable<String>(reaction);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  LocalFunFactsCompanion toCompanion(bool nullToAbsent) {
    return LocalFunFactsCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      hook: Value(hook),
      body: Value(body),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      reaction: reaction == null && nullToAbsent
          ? const Value.absent()
          : Value(reaction),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory LocalFunFact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFunFact(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      title: serializer.fromJson<String?>(json['title']),
      hook: serializer.fromJson<String>(json['hook']),
      body: serializer.fromJson<String>(json['body']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      reaction: serializer.fromJson<String?>(json['reaction']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'title': serializer.toJson<String?>(title),
      'hook': serializer.toJson<String>(hook),
      'body': serializer.toJson<String>(body),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'reaction': serializer.toJson<String?>(reaction),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  LocalFunFact copyWith({
    String? id,
    String? userId,
    String? lectureId,
    Value<String?> title = const Value.absent(),
    String? hook,
    String? body,
    Value<String?> metadataJson = const Value.absent(),
    Value<String?> reaction = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? lastSyncedAt,
  }) => LocalFunFact(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    title: title.present ? title.value : this.title,
    hook: hook ?? this.hook,
    body: body ?? this.body,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    reaction: reaction.present ? reaction.value : this.reaction,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
  LocalFunFact copyWithCompanion(LocalFunFactsCompanion data) {
    return LocalFunFact(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      title: data.title.present ? data.title.value : this.title,
      hook: data.hook.present ? data.hook.value : this.hook,
      body: data.body.present ? data.body.value : this.body,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      reaction: data.reaction.present ? data.reaction.value : this.reaction,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFunFact(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('title: $title, ')
          ..write('hook: $hook, ')
          ..write('body: $body, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('reaction: $reaction, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    lectureId,
    title,
    hook,
    body,
    metadataJson,
    reaction,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFunFact &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.title == this.title &&
          other.hook == this.hook &&
          other.body == this.body &&
          other.metadataJson == this.metadataJson &&
          other.reaction == this.reaction &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class LocalFunFactsCompanion extends UpdateCompanion<LocalFunFact> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<String?> title;
  final Value<String> hook;
  final Value<String> body;
  final Value<String?> metadataJson;
  final Value<String?> reaction;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const LocalFunFactsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.title = const Value.absent(),
    this.hook = const Value.absent(),
    this.body = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.reaction = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFunFactsCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    this.title = const Value.absent(),
    required String hook,
    required String body,
    this.metadataJson = const Value.absent(),
    this.reaction = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       hook = Value(hook),
       body = Value(body),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalFunFact> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<String>? title,
    Expression<String>? hook,
    Expression<String>? body,
    Expression<String>? metadataJson,
    Expression<String>? reaction,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (title != null) 'title': title,
      if (hook != null) 'hook': hook,
      if (body != null) 'body': body,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (reaction != null) 'reaction': reaction,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFunFactsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<String?>? title,
    Value<String>? hook,
    Value<String>? body,
    Value<String?>? metadataJson,
    Value<String?>? reaction,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return LocalFunFactsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      title: title ?? this.title,
      hook: hook ?? this.hook,
      body: body ?? this.body,
      metadataJson: metadataJson ?? this.metadataJson,
      reaction: reaction ?? this.reaction,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (hook.present) {
      map['hook'] = Variable<String>(hook.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (reaction.present) {
      map['reaction'] = Variable<String>(reaction.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFunFactsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('title: $title, ')
          ..write('hook: $hook, ')
          ..write('body: $body, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('reaction: $reaction, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalReviewCardsTable extends LocalReviewCards
    with TableInfo<$LocalReviewCardsTable, LocalReviewCard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalReviewCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicNumberMeta = const VerificationMeta(
    'topicNumber',
  );
  @override
  late final GeneratedColumn<int> topicNumber = GeneratedColumn<int>(
    'topic_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardContentJsonMeta = const VerificationMeta(
    'cardContentJson',
  );
  @override
  late final GeneratedColumn<String> cardContentJson = GeneratedColumn<String>(
    'card_content_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardTypeMeta = const VerificationMeta(
    'cardType',
  );
  @override
  late final GeneratedColumn<String> cardType = GeneratedColumn<String>(
    'card_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heroEmojiMeta = const VerificationMeta(
    'heroEmoji',
  );
  @override
  late final GeneratedColumn<String> heroEmoji = GeneratedColumn<String>(
    'hero_emoji',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    topicNumber,
    cardContentJson,
    cardType,
    title,
    heroEmoji,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_review_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalReviewCard> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('topic_number')) {
      context.handle(
        _topicNumberMeta,
        topicNumber.isAcceptableOrUnknown(
          data['topic_number']!,
          _topicNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_topicNumberMeta);
    }
    if (data.containsKey('card_content_json')) {
      context.handle(
        _cardContentJsonMeta,
        cardContentJson.isAcceptableOrUnknown(
          data['card_content_json']!,
          _cardContentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cardContentJsonMeta);
    }
    if (data.containsKey('card_type')) {
      context.handle(
        _cardTypeMeta,
        cardType.isAcceptableOrUnknown(data['card_type']!, _cardTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_cardTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('hero_emoji')) {
      context.handle(
        _heroEmojiMeta,
        heroEmoji.isAcceptableOrUnknown(data['hero_emoji']!, _heroEmojiMeta),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalReviewCard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalReviewCard(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      topicNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}topic_number'],
      )!,
      cardContentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_content_json'],
      )!,
      cardType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      heroEmoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hero_emoji'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      )!,
    );
  }

  @override
  $LocalReviewCardsTable createAlias(String alias) {
    return $LocalReviewCardsTable(attachedDatabase, alias);
  }
}

class LocalReviewCard extends DataClass implements Insertable<LocalReviewCard> {
  final String id;
  final String userId;
  final String lectureId;
  final int topicNumber;
  final String cardContentJson;
  final String cardType;
  final String? title;
  final String? heroEmoji;
  final String? metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime lastSyncedAt;
  const LocalReviewCard({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.topicNumber,
    required this.cardContentJson,
    required this.cardType,
    this.title,
    this.heroEmoji,
    this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    map['topic_number'] = Variable<int>(topicNumber);
    map['card_content_json'] = Variable<String>(cardContentJson);
    map['card_type'] = Variable<String>(cardType);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || heroEmoji != null) {
      map['hero_emoji'] = Variable<String>(heroEmoji);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  LocalReviewCardsCompanion toCompanion(bool nullToAbsent) {
    return LocalReviewCardsCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      topicNumber: Value(topicNumber),
      cardContentJson: Value(cardContentJson),
      cardType: Value(cardType),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      heroEmoji: heroEmoji == null && nullToAbsent
          ? const Value.absent()
          : Value(heroEmoji),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory LocalReviewCard.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalReviewCard(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      topicNumber: serializer.fromJson<int>(json['topicNumber']),
      cardContentJson: serializer.fromJson<String>(json['cardContentJson']),
      cardType: serializer.fromJson<String>(json['cardType']),
      title: serializer.fromJson<String?>(json['title']),
      heroEmoji: serializer.fromJson<String?>(json['heroEmoji']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'topicNumber': serializer.toJson<int>(topicNumber),
      'cardContentJson': serializer.toJson<String>(cardContentJson),
      'cardType': serializer.toJson<String>(cardType),
      'title': serializer.toJson<String?>(title),
      'heroEmoji': serializer.toJson<String?>(heroEmoji),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  LocalReviewCard copyWith({
    String? id,
    String? userId,
    String? lectureId,
    int? topicNumber,
    String? cardContentJson,
    String? cardType,
    Value<String?> title = const Value.absent(),
    Value<String?> heroEmoji = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? lastSyncedAt,
  }) => LocalReviewCard(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    topicNumber: topicNumber ?? this.topicNumber,
    cardContentJson: cardContentJson ?? this.cardContentJson,
    cardType: cardType ?? this.cardType,
    title: title.present ? title.value : this.title,
    heroEmoji: heroEmoji.present ? heroEmoji.value : this.heroEmoji,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
  LocalReviewCard copyWithCompanion(LocalReviewCardsCompanion data) {
    return LocalReviewCard(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      topicNumber: data.topicNumber.present
          ? data.topicNumber.value
          : this.topicNumber,
      cardContentJson: data.cardContentJson.present
          ? data.cardContentJson.value
          : this.cardContentJson,
      cardType: data.cardType.present ? data.cardType.value : this.cardType,
      title: data.title.present ? data.title.value : this.title,
      heroEmoji: data.heroEmoji.present ? data.heroEmoji.value : this.heroEmoji,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalReviewCard(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('topicNumber: $topicNumber, ')
          ..write('cardContentJson: $cardContentJson, ')
          ..write('cardType: $cardType, ')
          ..write('title: $title, ')
          ..write('heroEmoji: $heroEmoji, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    lectureId,
    topicNumber,
    cardContentJson,
    cardType,
    title,
    heroEmoji,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalReviewCard &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.topicNumber == this.topicNumber &&
          other.cardContentJson == this.cardContentJson &&
          other.cardType == this.cardType &&
          other.title == this.title &&
          other.heroEmoji == this.heroEmoji &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class LocalReviewCardsCompanion extends UpdateCompanion<LocalReviewCard> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<int> topicNumber;
  final Value<String> cardContentJson;
  final Value<String> cardType;
  final Value<String?> title;
  final Value<String?> heroEmoji;
  final Value<String?> metadataJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const LocalReviewCardsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.topicNumber = const Value.absent(),
    this.cardContentJson = const Value.absent(),
    this.cardType = const Value.absent(),
    this.title = const Value.absent(),
    this.heroEmoji = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalReviewCardsCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    required int topicNumber,
    required String cardContentJson,
    required String cardType,
    this.title = const Value.absent(),
    this.heroEmoji = const Value.absent(),
    this.metadataJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       topicNumber = Value(topicNumber),
       cardContentJson = Value(cardContentJson),
       cardType = Value(cardType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalReviewCard> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<int>? topicNumber,
    Expression<String>? cardContentJson,
    Expression<String>? cardType,
    Expression<String>? title,
    Expression<String>? heroEmoji,
    Expression<String>? metadataJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (topicNumber != null) 'topic_number': topicNumber,
      if (cardContentJson != null) 'card_content_json': cardContentJson,
      if (cardType != null) 'card_type': cardType,
      if (title != null) 'title': title,
      if (heroEmoji != null) 'hero_emoji': heroEmoji,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalReviewCardsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<int>? topicNumber,
    Value<String>? cardContentJson,
    Value<String>? cardType,
    Value<String?>? title,
    Value<String?>? heroEmoji,
    Value<String?>? metadataJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return LocalReviewCardsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      topicNumber: topicNumber ?? this.topicNumber,
      cardContentJson: cardContentJson ?? this.cardContentJson,
      cardType: cardType ?? this.cardType,
      title: title ?? this.title,
      heroEmoji: heroEmoji ?? this.heroEmoji,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (topicNumber.present) {
      map['topic_number'] = Variable<int>(topicNumber.value);
    }
    if (cardContentJson.present) {
      map['card_content_json'] = Variable<String>(cardContentJson.value);
    }
    if (cardType.present) {
      map['card_type'] = Variable<String>(cardType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (heroEmoji.present) {
      map['hero_emoji'] = Variable<String>(heroEmoji.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalReviewCardsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('topicNumber: $topicNumber, ')
          ..write('cardContentJson: $cardContentJson, ')
          ..write('cardType: $cardType, ')
          ..write('title: $title, ')
          ..write('heroEmoji: $heroEmoji, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalDeepNotesTable extends LocalDeepNotes
    with TableInfo<$LocalDeepNotesTable, LocalDeepNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalDeepNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicNumberMeta = const VerificationMeta(
    'topicNumber',
  );
  @override
  late final GeneratedColumn<int> topicNumber = GeneratedColumn<int>(
    'topic_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteContentsMeta = const VerificationMeta(
    'noteContents',
  );
  @override
  late final GeneratedColumn<String> noteContents = GeneratedColumn<String>(
    'note_contents',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    topicNumber,
    noteContents,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_deep_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalDeepNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('topic_number')) {
      context.handle(
        _topicNumberMeta,
        topicNumber.isAcceptableOrUnknown(
          data['topic_number']!,
          _topicNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_topicNumberMeta);
    }
    if (data.containsKey('note_contents')) {
      context.handle(
        _noteContentsMeta,
        noteContents.isAcceptableOrUnknown(
          data['note_contents']!,
          _noteContentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_noteContentsMeta);
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalDeepNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalDeepNote(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      topicNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}topic_number'],
      )!,
      noteContents: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_contents'],
      )!,
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      )!,
    );
  }

  @override
  $LocalDeepNotesTable createAlias(String alias) {
    return $LocalDeepNotesTable(attachedDatabase, alias);
  }
}

class LocalDeepNote extends DataClass implements Insertable<LocalDeepNote> {
  final String id;
  final String userId;
  final String lectureId;
  final int topicNumber;
  final String noteContents;
  final String? metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime lastSyncedAt;
  const LocalDeepNote({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.topicNumber,
    required this.noteContents,
    this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    map['topic_number'] = Variable<int>(topicNumber);
    map['note_contents'] = Variable<String>(noteContents);
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  LocalDeepNotesCompanion toCompanion(bool nullToAbsent) {
    return LocalDeepNotesCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      topicNumber: Value(topicNumber),
      noteContents: Value(noteContents),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory LocalDeepNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalDeepNote(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      topicNumber: serializer.fromJson<int>(json['topicNumber']),
      noteContents: serializer.fromJson<String>(json['noteContents']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'topicNumber': serializer.toJson<int>(topicNumber),
      'noteContents': serializer.toJson<String>(noteContents),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  LocalDeepNote copyWith({
    String? id,
    String? userId,
    String? lectureId,
    int? topicNumber,
    String? noteContents,
    Value<String?> metadataJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? lastSyncedAt,
  }) => LocalDeepNote(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    topicNumber: topicNumber ?? this.topicNumber,
    noteContents: noteContents ?? this.noteContents,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
  LocalDeepNote copyWithCompanion(LocalDeepNotesCompanion data) {
    return LocalDeepNote(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      topicNumber: data.topicNumber.present
          ? data.topicNumber.value
          : this.topicNumber,
      noteContents: data.noteContents.present
          ? data.noteContents.value
          : this.noteContents,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalDeepNote(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('topicNumber: $topicNumber, ')
          ..write('noteContents: $noteContents, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    lectureId,
    topicNumber,
    noteContents,
    metadataJson,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDeepNote &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.topicNumber == this.topicNumber &&
          other.noteContents == this.noteContents &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class LocalDeepNotesCompanion extends UpdateCompanion<LocalDeepNote> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<int> topicNumber;
  final Value<String> noteContents;
  final Value<String?> metadataJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const LocalDeepNotesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.topicNumber = const Value.absent(),
    this.noteContents = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalDeepNotesCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    required int topicNumber,
    required String noteContents,
    this.metadataJson = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       topicNumber = Value(topicNumber),
       noteContents = Value(noteContents),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalDeepNote> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<int>? topicNumber,
    Expression<String>? noteContents,
    Expression<String>? metadataJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (topicNumber != null) 'topic_number': topicNumber,
      if (noteContents != null) 'note_contents': noteContents,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalDeepNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<int>? topicNumber,
    Value<String>? noteContents,
    Value<String?>? metadataJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return LocalDeepNotesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      topicNumber: topicNumber ?? this.topicNumber,
      noteContents: noteContents ?? this.noteContents,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (topicNumber.present) {
      map['topic_number'] = Variable<int>(topicNumber.value);
    }
    if (noteContents.present) {
      map['note_contents'] = Variable<String>(noteContents.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalDeepNotesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('topicNumber: $topicNumber, ')
          ..write('noteContents: $noteContents, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalKeywordsTable extends LocalKeywords
    with TableInfo<$LocalKeywordsTable, LocalKeyword> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalKeywordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicNumberMeta = const VerificationMeta(
    'topicNumber',
  );
  @override
  late final GeneratedColumn<int> topicNumber = GeneratedColumn<int>(
    'topic_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keywordMeta = const VerificationMeta(
    'keyword',
  );
  @override
  late final GeneratedColumn<String> keyword = GeneratedColumn<String>(
    'keyword',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _definitionMeta = const VerificationMeta(
    'definition',
  );
  @override
  late final GeneratedColumn<String> definition = GeneratedColumn<String>(
    'definition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    topicNumber,
    keyword,
    definition,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_keywords';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalKeyword> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('topic_number')) {
      context.handle(
        _topicNumberMeta,
        topicNumber.isAcceptableOrUnknown(
          data['topic_number']!,
          _topicNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_topicNumberMeta);
    }
    if (data.containsKey('keyword')) {
      context.handle(
        _keywordMeta,
        keyword.isAcceptableOrUnknown(data['keyword']!, _keywordMeta),
      );
    } else if (isInserting) {
      context.missing(_keywordMeta);
    }
    if (data.containsKey('definition')) {
      context.handle(
        _definitionMeta,
        definition.isAcceptableOrUnknown(data['definition']!, _definitionMeta),
      );
    } else if (isInserting) {
      context.missing(_definitionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalKeyword map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalKeyword(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      topicNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}topic_number'],
      )!,
      keyword: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}keyword'],
      )!,
      definition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}definition'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      )!,
    );
  }

  @override
  $LocalKeywordsTable createAlias(String alias) {
    return $LocalKeywordsTable(attachedDatabase, alias);
  }
}

class LocalKeyword extends DataClass implements Insertable<LocalKeyword> {
  final String id;
  final String userId;
  final String lectureId;
  final int topicNumber;
  final String keyword;
  final String definition;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime lastSyncedAt;
  const LocalKeyword({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.topicNumber,
    required this.keyword,
    required this.definition,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    map['topic_number'] = Variable<int>(topicNumber);
    map['keyword'] = Variable<String>(keyword);
    map['definition'] = Variable<String>(definition);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  LocalKeywordsCompanion toCompanion(bool nullToAbsent) {
    return LocalKeywordsCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      topicNumber: Value(topicNumber),
      keyword: Value(keyword),
      definition: Value(definition),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory LocalKeyword.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalKeyword(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      topicNumber: serializer.fromJson<int>(json['topicNumber']),
      keyword: serializer.fromJson<String>(json['keyword']),
      definition: serializer.fromJson<String>(json['definition']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'topicNumber': serializer.toJson<int>(topicNumber),
      'keyword': serializer.toJson<String>(keyword),
      'definition': serializer.toJson<String>(definition),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  LocalKeyword copyWith({
    String? id,
    String? userId,
    String? lectureId,
    int? topicNumber,
    String? keyword,
    String? definition,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? lastSyncedAt,
  }) => LocalKeyword(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    topicNumber: topicNumber ?? this.topicNumber,
    keyword: keyword ?? this.keyword,
    definition: definition ?? this.definition,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
  LocalKeyword copyWithCompanion(LocalKeywordsCompanion data) {
    return LocalKeyword(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      topicNumber: data.topicNumber.present
          ? data.topicNumber.value
          : this.topicNumber,
      keyword: data.keyword.present ? data.keyword.value : this.keyword,
      definition: data.definition.present
          ? data.definition.value
          : this.definition,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalKeyword(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('topicNumber: $topicNumber, ')
          ..write('keyword: $keyword, ')
          ..write('definition: $definition, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    lectureId,
    topicNumber,
    keyword,
    definition,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalKeyword &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.topicNumber == this.topicNumber &&
          other.keyword == this.keyword &&
          other.definition == this.definition &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class LocalKeywordsCompanion extends UpdateCompanion<LocalKeyword> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<int> topicNumber;
  final Value<String> keyword;
  final Value<String> definition;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const LocalKeywordsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.topicNumber = const Value.absent(),
    this.keyword = const Value.absent(),
    this.definition = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalKeywordsCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    required int topicNumber,
    required String keyword,
    required String definition,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       topicNumber = Value(topicNumber),
       keyword = Value(keyword),
       definition = Value(definition),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalKeyword> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<int>? topicNumber,
    Expression<String>? keyword,
    Expression<String>? definition,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (topicNumber != null) 'topic_number': topicNumber,
      if (keyword != null) 'keyword': keyword,
      if (definition != null) 'definition': definition,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalKeywordsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<int>? topicNumber,
    Value<String>? keyword,
    Value<String>? definition,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return LocalKeywordsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      topicNumber: topicNumber ?? this.topicNumber,
      keyword: keyword ?? this.keyword,
      definition: definition ?? this.definition,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (topicNumber.present) {
      map['topic_number'] = Variable<int>(topicNumber.value);
    }
    if (keyword.present) {
      map['keyword'] = Variable<String>(keyword.value);
    }
    if (definition.present) {
      map['definition'] = Variable<String>(definition.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalKeywordsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('topicNumber: $topicNumber, ')
          ..write('keyword: $keyword, ')
          ..write('definition: $definition, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalLectureTopicsTable extends LocalLectureTopics
    with TableInfo<$LocalLectureTopicsTable, LocalLectureTopic> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalLectureTopicsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicIndexMeta = const VerificationMeta(
    'topicIndex',
  );
  @override
  late final GeneratedColumn<int> topicIndex = GeneratedColumn<int>(
    'topic_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicTitleMeta = const VerificationMeta(
    'topicTitle',
  );
  @override
  late final GeneratedColumn<String> topicTitle = GeneratedColumn<String>(
    'topic_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _topicTypeMeta = const VerificationMeta(
    'topicType',
  );
  @override
  late final GeneratedColumn<String> topicType = GeneratedColumn<String>(
    'topic_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta(
    'summary',
  );
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startSidMeta = const VerificationMeta(
    'startSid',
  );
  @override
  late final GeneratedColumn<String> startSid = GeneratedColumn<String>(
    'start_sid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endSidMeta = const VerificationMeta('endSid');
  @override
  late final GeneratedColumn<String> endSid = GeneratedColumn<String>(
    'end_sid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    topicIndex,
    topicTitle,
    topicType,
    summary,
    startSid,
    endSid,
    imagePath,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_lecture_topics';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalLectureTopic> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('topic_index')) {
      context.handle(
        _topicIndexMeta,
        topicIndex.isAcceptableOrUnknown(data['topic_index']!, _topicIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_topicIndexMeta);
    }
    if (data.containsKey('topic_title')) {
      context.handle(
        _topicTitleMeta,
        topicTitle.isAcceptableOrUnknown(data['topic_title']!, _topicTitleMeta),
      );
    } else if (isInserting) {
      context.missing(_topicTitleMeta);
    }
    if (data.containsKey('topic_type')) {
      context.handle(
        _topicTypeMeta,
        topicType.isAcceptableOrUnknown(data['topic_type']!, _topicTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_topicTypeMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(
        _summaryMeta,
        summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta),
      );
    }
    if (data.containsKey('start_sid')) {
      context.handle(
        _startSidMeta,
        startSid.isAcceptableOrUnknown(data['start_sid']!, _startSidMeta),
      );
    }
    if (data.containsKey('end_sid')) {
      context.handle(
        _endSidMeta,
        endSid.isAcceptableOrUnknown(data['end_sid']!, _endSidMeta),
      );
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalLectureTopic map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalLectureTopic(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      topicIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}topic_index'],
      )!,
      topicTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_title'],
      )!,
      topicType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}topic_type'],
      )!,
      summary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}summary'],
      ),
      startSid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_sid'],
      ),
      endSid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_sid'],
      ),
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      )!,
    );
  }

  @override
  $LocalLectureTopicsTable createAlias(String alias) {
    return $LocalLectureTopicsTable(attachedDatabase, alias);
  }
}

class LocalLectureTopic extends DataClass
    implements Insertable<LocalLectureTopic> {
  final String id;
  final String userId;
  final String lectureId;
  final int topicIndex;
  final String topicTitle;
  final String topicType;
  final String? summary;
  final String? startSid;
  final String? endSid;
  final String? imagePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime lastSyncedAt;
  const LocalLectureTopic({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.topicIndex,
    required this.topicTitle,
    required this.topicType,
    this.summary,
    this.startSid,
    this.endSid,
    this.imagePath,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    map['topic_index'] = Variable<int>(topicIndex);
    map['topic_title'] = Variable<String>(topicTitle);
    map['topic_type'] = Variable<String>(topicType);
    if (!nullToAbsent || summary != null) {
      map['summary'] = Variable<String>(summary);
    }
    if (!nullToAbsent || startSid != null) {
      map['start_sid'] = Variable<String>(startSid);
    }
    if (!nullToAbsent || endSid != null) {
      map['end_sid'] = Variable<String>(endSid);
    }
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  LocalLectureTopicsCompanion toCompanion(bool nullToAbsent) {
    return LocalLectureTopicsCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      topicIndex: Value(topicIndex),
      topicTitle: Value(topicTitle),
      topicType: Value(topicType),
      summary: summary == null && nullToAbsent
          ? const Value.absent()
          : Value(summary),
      startSid: startSid == null && nullToAbsent
          ? const Value.absent()
          : Value(startSid),
      endSid: endSid == null && nullToAbsent
          ? const Value.absent()
          : Value(endSid),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory LocalLectureTopic.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalLectureTopic(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      topicIndex: serializer.fromJson<int>(json['topicIndex']),
      topicTitle: serializer.fromJson<String>(json['topicTitle']),
      topicType: serializer.fromJson<String>(json['topicType']),
      summary: serializer.fromJson<String?>(json['summary']),
      startSid: serializer.fromJson<String?>(json['startSid']),
      endSid: serializer.fromJson<String?>(json['endSid']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'topicIndex': serializer.toJson<int>(topicIndex),
      'topicTitle': serializer.toJson<String>(topicTitle),
      'topicType': serializer.toJson<String>(topicType),
      'summary': serializer.toJson<String?>(summary),
      'startSid': serializer.toJson<String?>(startSid),
      'endSid': serializer.toJson<String?>(endSid),
      'imagePath': serializer.toJson<String?>(imagePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  LocalLectureTopic copyWith({
    String? id,
    String? userId,
    String? lectureId,
    int? topicIndex,
    String? topicTitle,
    String? topicType,
    Value<String?> summary = const Value.absent(),
    Value<String?> startSid = const Value.absent(),
    Value<String?> endSid = const Value.absent(),
    Value<String?> imagePath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    DateTime? lastSyncedAt,
  }) => LocalLectureTopic(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    topicIndex: topicIndex ?? this.topicIndex,
    topicTitle: topicTitle ?? this.topicTitle,
    topicType: topicType ?? this.topicType,
    summary: summary.present ? summary.value : this.summary,
    startSid: startSid.present ? startSid.value : this.startSid,
    endSid: endSid.present ? endSid.value : this.endSid,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
  LocalLectureTopic copyWithCompanion(LocalLectureTopicsCompanion data) {
    return LocalLectureTopic(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      topicIndex: data.topicIndex.present
          ? data.topicIndex.value
          : this.topicIndex,
      topicTitle: data.topicTitle.present
          ? data.topicTitle.value
          : this.topicTitle,
      topicType: data.topicType.present ? data.topicType.value : this.topicType,
      summary: data.summary.present ? data.summary.value : this.summary,
      startSid: data.startSid.present ? data.startSid.value : this.startSid,
      endSid: data.endSid.present ? data.endSid.value : this.endSid,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalLectureTopic(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('topicIndex: $topicIndex, ')
          ..write('topicTitle: $topicTitle, ')
          ..write('topicType: $topicType, ')
          ..write('summary: $summary, ')
          ..write('startSid: $startSid, ')
          ..write('endSid: $endSid, ')
          ..write('imagePath: $imagePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    lectureId,
    topicIndex,
    topicTitle,
    topicType,
    summary,
    startSid,
    endSid,
    imagePath,
    createdAt,
    updatedAt,
    deletedAt,
    lastSyncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalLectureTopic &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.topicIndex == this.topicIndex &&
          other.topicTitle == this.topicTitle &&
          other.topicType == this.topicType &&
          other.summary == this.summary &&
          other.startSid == this.startSid &&
          other.endSid == this.endSid &&
          other.imagePath == this.imagePath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class LocalLectureTopicsCompanion extends UpdateCompanion<LocalLectureTopic> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<int> topicIndex;
  final Value<String> topicTitle;
  final Value<String> topicType;
  final Value<String?> summary;
  final Value<String?> startSid;
  final Value<String?> endSid;
  final Value<String?> imagePath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const LocalLectureTopicsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.topicIndex = const Value.absent(),
    this.topicTitle = const Value.absent(),
    this.topicType = const Value.absent(),
    this.summary = const Value.absent(),
    this.startSid = const Value.absent(),
    this.endSid = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalLectureTopicsCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    required int topicIndex,
    required String topicTitle,
    required String topicType,
    this.summary = const Value.absent(),
    this.startSid = const Value.absent(),
    this.endSid = const Value.absent(),
    this.imagePath = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       topicIndex = Value(topicIndex),
       topicTitle = Value(topicTitle),
       topicType = Value(topicType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LocalLectureTopic> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<int>? topicIndex,
    Expression<String>? topicTitle,
    Expression<String>? topicType,
    Expression<String>? summary,
    Expression<String>? startSid,
    Expression<String>? endSid,
    Expression<String>? imagePath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (topicIndex != null) 'topic_index': topicIndex,
      if (topicTitle != null) 'topic_title': topicTitle,
      if (topicType != null) 'topic_type': topicType,
      if (summary != null) 'summary': summary,
      if (startSid != null) 'start_sid': startSid,
      if (endSid != null) 'end_sid': endSid,
      if (imagePath != null) 'image_path': imagePath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalLectureTopicsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<int>? topicIndex,
    Value<String>? topicTitle,
    Value<String>? topicType,
    Value<String?>? summary,
    Value<String?>? startSid,
    Value<String?>? endSid,
    Value<String?>? imagePath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<DateTime>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return LocalLectureTopicsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      topicIndex: topicIndex ?? this.topicIndex,
      topicTitle: topicTitle ?? this.topicTitle,
      topicType: topicType ?? this.topicType,
      summary: summary ?? this.summary,
      startSid: startSid ?? this.startSid,
      endSid: endSid ?? this.endSid,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (topicIndex.present) {
      map['topic_index'] = Variable<int>(topicIndex.value);
    }
    if (topicTitle.present) {
      map['topic_title'] = Variable<String>(topicTitle.value);
    }
    if (topicType.present) {
      map['topic_type'] = Variable<String>(topicType.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (startSid.present) {
      map['start_sid'] = Variable<String>(startSid.value);
    }
    if (endSid.present) {
      map['end_sid'] = Variable<String>(endSid.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalLectureTopicsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('topicIndex: $topicIndex, ')
          ..write('topicTitle: $topicTitle, ')
          ..write('topicType: $topicType, ')
          ..write('summary: $summary, ')
          ..write('startSid: $startSid, ')
          ..write('endSid: $endSid, ')
          ..write('imagePath: $imagePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalTopicMapsTable extends LocalTopicMaps
    with TableInfo<$LocalTopicMapsTable, LocalTopicMap> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalTopicMapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _courseIdMeta = const VerificationMeta(
    'courseId',
  );
  @override
  late final GeneratedColumn<String> courseId = GeneratedColumn<String>(
    'course_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mapJsonMeta = const VerificationMeta(
    'mapJson',
  );
  @override
  late final GeneratedColumn<String> mapJson = GeneratedColumn<String>(
    'map_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isStaleMeta = const VerificationMeta(
    'isStale',
  );
  @override
  late final GeneratedColumn<bool> isStale = GeneratedColumn<bool>(
    'is_stale',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_stale" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    courseId,
    userId,
    mapJson,
    isStale,
    updatedAt,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_topic_maps';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalTopicMap> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('course_id')) {
      context.handle(
        _courseIdMeta,
        courseId.isAcceptableOrUnknown(data['course_id']!, _courseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courseIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('map_json')) {
      context.handle(
        _mapJsonMeta,
        mapJson.isAcceptableOrUnknown(data['map_json']!, _mapJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_mapJsonMeta);
    }
    if (data.containsKey('is_stale')) {
      context.handle(
        _isStaleMeta,
        isStale.isAcceptableOrUnknown(data['is_stale']!, _isStaleMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {courseId, userId};
  @override
  LocalTopicMap map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalTopicMap(
      courseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}course_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      mapJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}map_json'],
      )!,
      isStale: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_stale'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      )!,
    );
  }

  @override
  $LocalTopicMapsTable createAlias(String alias) {
    return $LocalTopicMapsTable(attachedDatabase, alias);
  }
}

class LocalTopicMap extends DataClass implements Insertable<LocalTopicMap> {
  final String courseId;
  final String userId;
  final String mapJson;
  final bool isStale;
  final DateTime updatedAt;
  final DateTime lastSyncedAt;
  const LocalTopicMap({
    required this.courseId,
    required this.userId,
    required this.mapJson,
    required this.isStale,
    required this.updatedAt,
    required this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['course_id'] = Variable<String>(courseId);
    map['user_id'] = Variable<String>(userId);
    map['map_json'] = Variable<String>(mapJson);
    map['is_stale'] = Variable<bool>(isStale);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  LocalTopicMapsCompanion toCompanion(bool nullToAbsent) {
    return LocalTopicMapsCompanion(
      courseId: Value(courseId),
      userId: Value(userId),
      mapJson: Value(mapJson),
      isStale: Value(isStale),
      updatedAt: Value(updatedAt),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory LocalTopicMap.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalTopicMap(
      courseId: serializer.fromJson<String>(json['courseId']),
      userId: serializer.fromJson<String>(json['userId']),
      mapJson: serializer.fromJson<String>(json['mapJson']),
      isStale: serializer.fromJson<bool>(json['isStale']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'courseId': serializer.toJson<String>(courseId),
      'userId': serializer.toJson<String>(userId),
      'mapJson': serializer.toJson<String>(mapJson),
      'isStale': serializer.toJson<bool>(isStale),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  LocalTopicMap copyWith({
    String? courseId,
    String? userId,
    String? mapJson,
    bool? isStale,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) => LocalTopicMap(
    courseId: courseId ?? this.courseId,
    userId: userId ?? this.userId,
    mapJson: mapJson ?? this.mapJson,
    isStale: isStale ?? this.isStale,
    updatedAt: updatedAt ?? this.updatedAt,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
  LocalTopicMap copyWithCompanion(LocalTopicMapsCompanion data) {
    return LocalTopicMap(
      courseId: data.courseId.present ? data.courseId.value : this.courseId,
      userId: data.userId.present ? data.userId.value : this.userId,
      mapJson: data.mapJson.present ? data.mapJson.value : this.mapJson,
      isStale: data.isStale.present ? data.isStale.value : this.isStale,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalTopicMap(')
          ..write('courseId: $courseId, ')
          ..write('userId: $userId, ')
          ..write('mapJson: $mapJson, ')
          ..write('isStale: $isStale, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(courseId, userId, mapJson, isStale, updatedAt, lastSyncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalTopicMap &&
          other.courseId == this.courseId &&
          other.userId == this.userId &&
          other.mapJson == this.mapJson &&
          other.isStale == this.isStale &&
          other.updatedAt == this.updatedAt &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class LocalTopicMapsCompanion extends UpdateCompanion<LocalTopicMap> {
  final Value<String> courseId;
  final Value<String> userId;
  final Value<String> mapJson;
  final Value<bool> isStale;
  final Value<DateTime> updatedAt;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const LocalTopicMapsCompanion({
    this.courseId = const Value.absent(),
    this.userId = const Value.absent(),
    this.mapJson = const Value.absent(),
    this.isStale = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalTopicMapsCompanion.insert({
    required String courseId,
    required String userId,
    required String mapJson,
    this.isStale = const Value.absent(),
    required DateTime updatedAt,
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : courseId = Value(courseId),
       userId = Value(userId),
       mapJson = Value(mapJson),
       updatedAt = Value(updatedAt);
  static Insertable<LocalTopicMap> custom({
    Expression<String>? courseId,
    Expression<String>? userId,
    Expression<String>? mapJson,
    Expression<bool>? isStale,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (courseId != null) 'course_id': courseId,
      if (userId != null) 'user_id': userId,
      if (mapJson != null) 'map_json': mapJson,
      if (isStale != null) 'is_stale': isStale,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalTopicMapsCompanion copyWith({
    Value<String>? courseId,
    Value<String>? userId,
    Value<String>? mapJson,
    Value<bool>? isStale,
    Value<DateTime>? updatedAt,
    Value<DateTime>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return LocalTopicMapsCompanion(
      courseId: courseId ?? this.courseId,
      userId: userId ?? this.userId,
      mapJson: mapJson ?? this.mapJson,
      isStale: isStale ?? this.isStale,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (courseId.present) {
      map['course_id'] = Variable<String>(courseId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (mapJson.present) {
      map['map_json'] = Variable<String>(mapJson.value);
    }
    if (isStale.present) {
      map['is_stale'] = Variable<bool>(isStale.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalTopicMapsCompanion(')
          ..write('courseId: $courseId, ')
          ..write('userId: $userId, ')
          ..write('mapJson: $mapJson, ')
          ..write('isStale: $isStale, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSyncCursorsTable extends LocalSyncCursors
    with TableInfo<$LocalSyncCursorsTable, LocalSyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastPulledAtMeta = const VerificationMeta(
    'lastPulledAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPulledAt = GeneratedColumn<DateTime>(
    'last_pulled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastFullPulledAtMeta = const VerificationMeta(
    'lastFullPulledAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastFullPulledAt =
      GeneratedColumn<DateTime>(
        'last_full_pulled_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    entityType,
    lastPulledAt,
    lastFullPulledAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalSyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('last_pulled_at')) {
      context.handle(
        _lastPulledAtMeta,
        lastPulledAt.isAcceptableOrUnknown(
          data['last_pulled_at']!,
          _lastPulledAtMeta,
        ),
      );
    }
    if (data.containsKey('last_full_pulled_at')) {
      context.handle(
        _lastFullPulledAtMeta,
        lastFullPulledAt.isAcceptableOrUnknown(
          data['last_full_pulled_at']!,
          _lastFullPulledAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, entityType};
  @override
  LocalSyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSyncCursor(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      lastPulledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_pulled_at'],
      ),
      lastFullPulledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_full_pulled_at'],
      ),
    );
  }

  @override
  $LocalSyncCursorsTable createAlias(String alias) {
    return $LocalSyncCursorsTable(attachedDatabase, alias);
  }
}

class LocalSyncCursor extends DataClass implements Insertable<LocalSyncCursor> {
  final String userId;
  final String entityType;
  final DateTime? lastPulledAt;
  final DateTime? lastFullPulledAt;
  const LocalSyncCursor({
    required this.userId,
    required this.entityType,
    this.lastPulledAt,
    this.lastFullPulledAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['entity_type'] = Variable<String>(entityType);
    if (!nullToAbsent || lastPulledAt != null) {
      map['last_pulled_at'] = Variable<DateTime>(lastPulledAt);
    }
    if (!nullToAbsent || lastFullPulledAt != null) {
      map['last_full_pulled_at'] = Variable<DateTime>(lastFullPulledAt);
    }
    return map;
  }

  LocalSyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return LocalSyncCursorsCompanion(
      userId: Value(userId),
      entityType: Value(entityType),
      lastPulledAt: lastPulledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPulledAt),
      lastFullPulledAt: lastFullPulledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFullPulledAt),
    );
  }

  factory LocalSyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSyncCursor(
      userId: serializer.fromJson<String>(json['userId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      lastPulledAt: serializer.fromJson<DateTime?>(json['lastPulledAt']),
      lastFullPulledAt: serializer.fromJson<DateTime?>(
        json['lastFullPulledAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'entityType': serializer.toJson<String>(entityType),
      'lastPulledAt': serializer.toJson<DateTime?>(lastPulledAt),
      'lastFullPulledAt': serializer.toJson<DateTime?>(lastFullPulledAt),
    };
  }

  LocalSyncCursor copyWith({
    String? userId,
    String? entityType,
    Value<DateTime?> lastPulledAt = const Value.absent(),
    Value<DateTime?> lastFullPulledAt = const Value.absent(),
  }) => LocalSyncCursor(
    userId: userId ?? this.userId,
    entityType: entityType ?? this.entityType,
    lastPulledAt: lastPulledAt.present ? lastPulledAt.value : this.lastPulledAt,
    lastFullPulledAt: lastFullPulledAt.present
        ? lastFullPulledAt.value
        : this.lastFullPulledAt,
  );
  LocalSyncCursor copyWithCompanion(LocalSyncCursorsCompanion data) {
    return LocalSyncCursor(
      userId: data.userId.present ? data.userId.value : this.userId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      lastPulledAt: data.lastPulledAt.present
          ? data.lastPulledAt.value
          : this.lastPulledAt,
      lastFullPulledAt: data.lastFullPulledAt.present
          ? data.lastFullPulledAt.value
          : this.lastFullPulledAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncCursor(')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('lastFullPulledAt: $lastFullPulledAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, entityType, lastPulledAt, lastFullPulledAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSyncCursor &&
          other.userId == this.userId &&
          other.entityType == this.entityType &&
          other.lastPulledAt == this.lastPulledAt &&
          other.lastFullPulledAt == this.lastFullPulledAt);
}

class LocalSyncCursorsCompanion extends UpdateCompanion<LocalSyncCursor> {
  final Value<String> userId;
  final Value<String> entityType;
  final Value<DateTime?> lastPulledAt;
  final Value<DateTime?> lastFullPulledAt;
  final Value<int> rowid;
  const LocalSyncCursorsCompanion({
    this.userId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.lastPulledAt = const Value.absent(),
    this.lastFullPulledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSyncCursorsCompanion.insert({
    required String userId,
    required String entityType,
    this.lastPulledAt = const Value.absent(),
    this.lastFullPulledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       entityType = Value(entityType);
  static Insertable<LocalSyncCursor> custom({
    Expression<String>? userId,
    Expression<String>? entityType,
    Expression<DateTime>? lastPulledAt,
    Expression<DateTime>? lastFullPulledAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (entityType != null) 'entity_type': entityType,
      if (lastPulledAt != null) 'last_pulled_at': lastPulledAt,
      if (lastFullPulledAt != null) 'last_full_pulled_at': lastFullPulledAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSyncCursorsCompanion copyWith({
    Value<String>? userId,
    Value<String>? entityType,
    Value<DateTime?>? lastPulledAt,
    Value<DateTime?>? lastFullPulledAt,
    Value<int>? rowid,
  }) {
    return LocalSyncCursorsCompanion(
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
      lastFullPulledAt: lastFullPulledAt ?? this.lastFullPulledAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (lastPulledAt.present) {
      map['last_pulled_at'] = Variable<DateTime>(lastPulledAt.value);
    }
    if (lastFullPulledAt.present) {
      map['last_full_pulled_at'] = Variable<DateTime>(lastFullPulledAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncCursorsCompanion(')
          ..write('userId: $userId, ')
          ..write('entityType: $entityType, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('lastFullPulledAt: $lastFullPulledAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCacheEntriesTable extends LocalCacheEntries
    with TableInfo<$LocalCacheEntriesTable, LocalCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lectureIdMeta = const VerificationMeta(
    'lectureId',
  );
  @override
  late final GeneratedColumn<String> lectureId = GeneratedColumn<String>(
    'lecture_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    lectureId,
    localFilePath,
    sizeBytes,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('lecture_id')) {
      context.handle(
        _lectureIdMeta,
        lectureId.isAcceptableOrUnknown(data['lecture_id']!, _lectureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lectureIdMeta);
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localFilePathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, userId};
  @override
  LocalCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCacheEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lectureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lecture_id'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $LocalCacheEntriesTable createAlias(String alias) {
    return $LocalCacheEntriesTable(attachedDatabase, alias);
  }
}

class LocalCacheEntry extends DataClass implements Insertable<LocalCacheEntry> {
  final String id;
  final String userId;
  final String lectureId;
  final String localFilePath;
  final int sizeBytes;
  final DateTime cachedAt;
  const LocalCacheEntry({
    required this.id,
    required this.userId,
    required this.lectureId,
    required this.localFilePath,
    required this.sizeBytes,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['lecture_id'] = Variable<String>(lectureId);
    map['local_file_path'] = Variable<String>(localFilePath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  LocalCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return LocalCacheEntriesCompanion(
      id: Value(id),
      userId: Value(userId),
      lectureId: Value(lectureId),
      localFilePath: Value(localFilePath),
      sizeBytes: Value(sizeBytes),
      cachedAt: Value(cachedAt),
    );
  }

  factory LocalCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCacheEntry(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      lectureId: serializer.fromJson<String>(json['lectureId']),
      localFilePath: serializer.fromJson<String>(json['localFilePath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'lectureId': serializer.toJson<String>(lectureId),
      'localFilePath': serializer.toJson<String>(localFilePath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  LocalCacheEntry copyWith({
    String? id,
    String? userId,
    String? lectureId,
    String? localFilePath,
    int? sizeBytes,
    DateTime? cachedAt,
  }) => LocalCacheEntry(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    lectureId: lectureId ?? this.lectureId,
    localFilePath: localFilePath ?? this.localFilePath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  LocalCacheEntry copyWithCompanion(LocalCacheEntriesCompanion data) {
    return LocalCacheEntry(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      lectureId: data.lectureId.present ? data.lectureId.value : this.lectureId,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCacheEntry(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, userId, lectureId, localFilePath, sizeBytes, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCacheEntry &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.lectureId == this.lectureId &&
          other.localFilePath == this.localFilePath &&
          other.sizeBytes == this.sizeBytes &&
          other.cachedAt == this.cachedAt);
}

class LocalCacheEntriesCompanion extends UpdateCompanion<LocalCacheEntry> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> lectureId;
  final Value<String> localFilePath;
  final Value<int> sizeBytes;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const LocalCacheEntriesCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.lectureId = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCacheEntriesCompanion.insert({
    required String id,
    required String userId,
    required String lectureId,
    required String localFilePath,
    required int sizeBytes,
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       lectureId = Value(lectureId),
       localFilePath = Value(localFilePath),
       sizeBytes = Value(sizeBytes);
  static Insertable<LocalCacheEntry> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? lectureId,
    Expression<String>? localFilePath,
    Expression<int>? sizeBytes,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (lectureId != null) 'lecture_id': lectureId,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCacheEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? lectureId,
    Value<String>? localFilePath,
    Value<int>? sizeBytes,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return LocalCacheEntriesCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      lectureId: lectureId ?? this.lectureId,
      localFilePath: localFilePath ?? this.localFilePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lectureId.present) {
      map['lecture_id'] = Variable<String>(lectureId.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCacheEntriesCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('lectureId: $lectureId, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalUserProfilesTable extends LocalUserProfiles
    with TableInfo<$LocalUserProfilesTable, LocalUserProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalUserProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bioMeta = const VerificationMeta('bio');
  @override
  late final GeneratedColumn<String> bio = GeneratedColumn<String>(
    'bio',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _interestsMeta = const VerificationMeta(
    'interests',
  );
  @override
  late final GeneratedColumn<String> interests = GeneratedColumn<String>(
    'interests',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _futureGoalsMeta = const VerificationMeta(
    'futureGoals',
  );
  @override
  late final GeneratedColumn<String> futureGoals = GeneratedColumn<String>(
    'future_goals',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    username,
    avatarUrl,
    bio,
    interests,
    futureGoals,
    metadataJson,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_user_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalUserProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('bio')) {
      context.handle(
        _bioMeta,
        bio.isAcceptableOrUnknown(data['bio']!, _bioMeta),
      );
    }
    if (data.containsKey('interests')) {
      context.handle(
        _interestsMeta,
        interests.isAcceptableOrUnknown(data['interests']!, _interestsMeta),
      );
    }
    if (data.containsKey('future_goals')) {
      context.handle(
        _futureGoalsMeta,
        futureGoals.isAcceptableOrUnknown(
          data['future_goals']!,
          _futureGoalsMeta,
        ),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalUserProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalUserProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      bio: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bio'],
      ),
      interests: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}interests'],
      ),
      futureGoals: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}future_goals'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LocalUserProfilesTable createAlias(String alias) {
    return $LocalUserProfilesTable(attachedDatabase, alias);
  }
}

class LocalUserProfile extends DataClass
    implements Insertable<LocalUserProfile> {
  final String id;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final String? interests;
  final String? futureGoals;
  final String? metadataJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalUserProfile({
    required this.id,
    this.username,
    this.avatarUrl,
    this.bio,
    this.interests,
    this.futureGoals,
    this.metadataJson,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || bio != null) {
      map['bio'] = Variable<String>(bio);
    }
    if (!nullToAbsent || interests != null) {
      map['interests'] = Variable<String>(interests);
    }
    if (!nullToAbsent || futureGoals != null) {
      map['future_goals'] = Variable<String>(futureGoals);
    }
    if (!nullToAbsent || metadataJson != null) {
      map['metadata_json'] = Variable<String>(metadataJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalUserProfilesCompanion toCompanion(bool nullToAbsent) {
    return LocalUserProfilesCompanion(
      id: Value(id),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      bio: bio == null && nullToAbsent ? const Value.absent() : Value(bio),
      interests: interests == null && nullToAbsent
          ? const Value.absent()
          : Value(interests),
      futureGoals: futureGoals == null && nullToAbsent
          ? const Value.absent()
          : Value(futureGoals),
      metadataJson: metadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalUserProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalUserProfile(
      id: serializer.fromJson<String>(json['id']),
      username: serializer.fromJson<String?>(json['username']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      bio: serializer.fromJson<String?>(json['bio']),
      interests: serializer.fromJson<String?>(json['interests']),
      futureGoals: serializer.fromJson<String?>(json['futureGoals']),
      metadataJson: serializer.fromJson<String?>(json['metadataJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'username': serializer.toJson<String?>(username),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'bio': serializer.toJson<String?>(bio),
      'interests': serializer.toJson<String?>(interests),
      'futureGoals': serializer.toJson<String?>(futureGoals),
      'metadataJson': serializer.toJson<String?>(metadataJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalUserProfile copyWith({
    String? id,
    Value<String?> username = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> bio = const Value.absent(),
    Value<String?> interests = const Value.absent(),
    Value<String?> futureGoals = const Value.absent(),
    Value<String?> metadataJson = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LocalUserProfile(
    id: id ?? this.id,
    username: username.present ? username.value : this.username,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    bio: bio.present ? bio.value : this.bio,
    interests: interests.present ? interests.value : this.interests,
    futureGoals: futureGoals.present ? futureGoals.value : this.futureGoals,
    metadataJson: metadataJson.present ? metadataJson.value : this.metadataJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LocalUserProfile copyWithCompanion(LocalUserProfilesCompanion data) {
    return LocalUserProfile(
      id: data.id.present ? data.id.value : this.id,
      username: data.username.present ? data.username.value : this.username,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      bio: data.bio.present ? data.bio.value : this.bio,
      interests: data.interests.present ? data.interests.value : this.interests,
      futureGoals: data.futureGoals.present
          ? data.futureGoals.value
          : this.futureGoals,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalUserProfile(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('bio: $bio, ')
          ..write('interests: $interests, ')
          ..write('futureGoals: $futureGoals, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    username,
    avatarUrl,
    bio,
    interests,
    futureGoals,
    metadataJson,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalUserProfile &&
          other.id == this.id &&
          other.username == this.username &&
          other.avatarUrl == this.avatarUrl &&
          other.bio == this.bio &&
          other.interests == this.interests &&
          other.futureGoals == this.futureGoals &&
          other.metadataJson == this.metadataJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalUserProfilesCompanion extends UpdateCompanion<LocalUserProfile> {
  final Value<String> id;
  final Value<String?> username;
  final Value<String?> avatarUrl;
  final Value<String?> bio;
  final Value<String?> interests;
  final Value<String?> futureGoals;
  final Value<String?> metadataJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalUserProfilesCompanion({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.bio = const Value.absent(),
    this.interests = const Value.absent(),
    this.futureGoals = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalUserProfilesCompanion.insert({
    required String id,
    this.username = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.bio = const Value.absent(),
    this.interests = const Value.absent(),
    this.futureGoals = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<LocalUserProfile> custom({
    Expression<String>? id,
    Expression<String>? username,
    Expression<String>? avatarUrl,
    Expression<String>? bio,
    Expression<String>? interests,
    Expression<String>? futureGoals,
    Expression<String>? metadataJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (username != null) 'username': username,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (bio != null) 'bio': bio,
      if (interests != null) 'interests': interests,
      if (futureGoals != null) 'future_goals': futureGoals,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalUserProfilesCompanion copyWith({
    Value<String>? id,
    Value<String?>? username,
    Value<String?>? avatarUrl,
    Value<String?>? bio,
    Value<String?>? interests,
    Value<String?>? futureGoals,
    Value<String?>? metadataJson,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalUserProfilesCompanion(
      id: id ?? this.id,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      futureGoals: futureGoals ?? this.futureGoals,
      metadataJson: metadataJson ?? this.metadataJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (bio.present) {
      map['bio'] = Variable<String>(bio.value);
    }
    if (interests.present) {
      map['interests'] = Variable<String>(interests.value);
    }
    if (futureGoals.present) {
      map['future_goals'] = Variable<String>(futureGoals.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalUserProfilesCompanion(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('bio: $bio, ')
          ..write('interests: $interests, ')
          ..write('futureGoals: $futureGoals, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalOutboxTable localOutbox = $LocalOutboxTable(this);
  late final $LocalLecturesTable localLectures = $LocalLecturesTable(this);
  late final $LocalLectureAssetsTable localLectureAssets =
      $LocalLectureAssetsTable(this);
  late final $LocalUploadJobsTable localUploadJobs = $LocalUploadJobsTable(
    this,
  );
  late final $LocalCoursesTable localCourses = $LocalCoursesTable(this);
  late final $LocalCourseAttributesTable localCourseAttributes =
      $LocalCourseAttributesTable(this);
  late final $LocalAnnouncementsTable localAnnouncements =
      $LocalAnnouncementsTable(this);
  late final $LocalLectureMomentsTable localLectureMoments =
      $LocalLectureMomentsTable(this);
  late final $LocalAsrModelsTable localAsrModels = $LocalAsrModelsTable(this);
  late final $LocalFunFactsTable localFunFacts = $LocalFunFactsTable(this);
  late final $LocalReviewCardsTable localReviewCards = $LocalReviewCardsTable(
    this,
  );
  late final $LocalDeepNotesTable localDeepNotes = $LocalDeepNotesTable(this);
  late final $LocalKeywordsTable localKeywords = $LocalKeywordsTable(this);
  late final $LocalLectureTopicsTable localLectureTopics =
      $LocalLectureTopicsTable(this);
  late final $LocalTopicMapsTable localTopicMaps = $LocalTopicMapsTable(this);
  late final $LocalSyncCursorsTable localSyncCursors = $LocalSyncCursorsTable(
    this,
  );
  late final $LocalCacheEntriesTable localCacheEntries =
      $LocalCacheEntriesTable(this);
  late final $LocalUserProfilesTable localUserProfiles =
      $LocalUserProfilesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localOutbox,
    localLectures,
    localLectureAssets,
    localUploadJobs,
    localCourses,
    localCourseAttributes,
    localAnnouncements,
    localLectureMoments,
    localAsrModels,
    localFunFacts,
    localReviewCards,
    localDeepNotes,
    localKeywords,
    localLectureTopics,
    localTopicMaps,
    localSyncCursors,
    localCacheEntries,
    localUserProfiles,
  ];
}

typedef $$LocalOutboxTableCreateCompanionBuilder =
    LocalOutboxCompanion Function({
      Value<int> id,
      required String entityType,
      required String entityId,
      required String op,
      Value<String?> payloadJson,
      Value<DateTime> enqueuedAt,
      Value<int> attemptCount,
      Value<String?> lastError,
      Value<DateTime?> nextRetryAt,
      Value<bool> givenUp,
    });
typedef $$LocalOutboxTableUpdateCompanionBuilder =
    LocalOutboxCompanion Function({
      Value<int> id,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> op,
      Value<String?> payloadJson,
      Value<DateTime> enqueuedAt,
      Value<int> attemptCount,
      Value<String?> lastError,
      Value<DateTime?> nextRetryAt,
      Value<bool> givenUp,
    });

class $$LocalOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get enqueuedAt => $composableBuilder(
    column: $table.enqueuedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get givenUp => $composableBuilder(
    column: $table.givenUp,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get enqueuedAt => $composableBuilder(
    column: $table.enqueuedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get givenUp => $composableBuilder(
    column: $table.givenUp,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalOutboxTable> {
  $$LocalOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get enqueuedAt => $composableBuilder(
    column: $table.enqueuedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get givenUp =>
      $composableBuilder(column: $table.givenUp, builder: (column) => column);
}

class $$LocalOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalOutboxTable,
          LocalOutboxData,
          $$LocalOutboxTableFilterComposer,
          $$LocalOutboxTableOrderingComposer,
          $$LocalOutboxTableAnnotationComposer,
          $$LocalOutboxTableCreateCompanionBuilder,
          $$LocalOutboxTableUpdateCompanionBuilder,
          (
            LocalOutboxData,
            BaseReferences<_$AppDatabase, $LocalOutboxTable, LocalOutboxData>,
          ),
          LocalOutboxData,
          PrefetchHooks Function()
        > {
  $$LocalOutboxTableTableManager(_$AppDatabase db, $LocalOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> op = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<DateTime> enqueuedAt = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<bool> givenUp = const Value.absent(),
              }) => LocalOutboxCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                op: op,
                payloadJson: payloadJson,
                enqueuedAt: enqueuedAt,
                attemptCount: attemptCount,
                lastError: lastError,
                nextRetryAt: nextRetryAt,
                givenUp: givenUp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entityType,
                required String entityId,
                required String op,
                Value<String?> payloadJson = const Value.absent(),
                Value<DateTime> enqueuedAt = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<bool> givenUp = const Value.absent(),
              }) => LocalOutboxCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                op: op,
                payloadJson: payloadJson,
                enqueuedAt: enqueuedAt,
                attemptCount: attemptCount,
                lastError: lastError,
                nextRetryAt: nextRetryAt,
                givenUp: givenUp,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalOutboxTable,
      LocalOutboxData,
      $$LocalOutboxTableFilterComposer,
      $$LocalOutboxTableOrderingComposer,
      $$LocalOutboxTableAnnotationComposer,
      $$LocalOutboxTableCreateCompanionBuilder,
      $$LocalOutboxTableUpdateCompanionBuilder,
      (
        LocalOutboxData,
        BaseReferences<_$AppDatabase, $LocalOutboxTable, LocalOutboxData>,
      ),
      LocalOutboxData,
      PrefetchHooks Function()
    >;
typedef $$LocalLecturesTableCreateCompanionBuilder =
    LocalLecturesCompanion Function({
      required String id,
      required String userId,
      Value<String?> courseId,
      Value<String?> title,
      Value<String?> titleGenerated,
      Value<int?> expectedChunks,
      Value<DateTime?> lectureDatetime,
      Value<int?> sortOrder,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String?> whisperContext,
      Value<String?> summary,
      Value<String?> audioPath,
      Value<String?> metadataJson,
      Value<String> syncStatus,
      Value<DateTime?> lastAccessedAt,
      Value<bool> isPinned,
      Value<bool> topicMapMovePending,
      Value<String?> pendingTopicMapStaleCourseId,
      Value<bool> autoStartAnalysis,
      Value<bool> isRealtime,
      Value<int> rowid,
    });
typedef $$LocalLecturesTableUpdateCompanionBuilder =
    LocalLecturesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String?> courseId,
      Value<String?> title,
      Value<String?> titleGenerated,
      Value<int?> expectedChunks,
      Value<DateTime?> lectureDatetime,
      Value<int?> sortOrder,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String?> whisperContext,
      Value<String?> summary,
      Value<String?> audioPath,
      Value<String?> metadataJson,
      Value<String> syncStatus,
      Value<DateTime?> lastAccessedAt,
      Value<bool> isPinned,
      Value<bool> topicMapMovePending,
      Value<String?> pendingTopicMapStaleCourseId,
      Value<bool> autoStartAnalysis,
      Value<bool> isRealtime,
      Value<int> rowid,
    });

class $$LocalLecturesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalLecturesTable> {
  $$LocalLecturesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleGenerated => $composableBuilder(
    column: $table.titleGenerated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedChunks => $composableBuilder(
    column: $table.expectedChunks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lectureDatetime => $composableBuilder(
    column: $table.lectureDatetime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get whisperContext => $composableBuilder(
    column: $table.whisperContext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get topicMapMovePending => $composableBuilder(
    column: $table.topicMapMovePending,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingTopicMapStaleCourseId => $composableBuilder(
    column: $table.pendingTopicMapStaleCourseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoStartAnalysis => $composableBuilder(
    column: $table.autoStartAnalysis,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRealtime => $composableBuilder(
    column: $table.isRealtime,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalLecturesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalLecturesTable> {
  $$LocalLecturesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleGenerated => $composableBuilder(
    column: $table.titleGenerated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedChunks => $composableBuilder(
    column: $table.expectedChunks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lectureDatetime => $composableBuilder(
    column: $table.lectureDatetime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get whisperContext => $composableBuilder(
    column: $table.whisperContext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioPath => $composableBuilder(
    column: $table.audioPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get topicMapMovePending => $composableBuilder(
    column: $table.topicMapMovePending,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingTopicMapStaleCourseId =>
      $composableBuilder(
        column: $table.pendingTopicMapStaleCourseId,
        builder: (column) => ColumnOrderings(column),
      );

  ColumnOrderings<bool> get autoStartAnalysis => $composableBuilder(
    column: $table.autoStartAnalysis,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRealtime => $composableBuilder(
    column: $table.isRealtime,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalLecturesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalLecturesTable> {
  $$LocalLecturesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get courseId =>
      $composableBuilder(column: $table.courseId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleGenerated => $composableBuilder(
    column: $table.titleGenerated,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expectedChunks => $composableBuilder(
    column: $table.expectedChunks,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lectureDatetime => $composableBuilder(
    column: $table.lectureDatetime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get whisperContext => $composableBuilder(
    column: $table.whisperContext,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get audioPath =>
      $composableBuilder(column: $table.audioPath, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get topicMapMovePending => $composableBuilder(
    column: $table.topicMapMovePending,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingTopicMapStaleCourseId =>
      $composableBuilder(
        column: $table.pendingTopicMapStaleCourseId,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get autoStartAnalysis => $composableBuilder(
    column: $table.autoStartAnalysis,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRealtime => $composableBuilder(
    column: $table.isRealtime,
    builder: (column) => column,
  );
}

class $$LocalLecturesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalLecturesTable,
          LocalLecture,
          $$LocalLecturesTableFilterComposer,
          $$LocalLecturesTableOrderingComposer,
          $$LocalLecturesTableAnnotationComposer,
          $$LocalLecturesTableCreateCompanionBuilder,
          $$LocalLecturesTableUpdateCompanionBuilder,
          (
            LocalLecture,
            BaseReferences<_$AppDatabase, $LocalLecturesTable, LocalLecture>,
          ),
          LocalLecture,
          PrefetchHooks Function()
        > {
  $$LocalLecturesTableTableManager(_$AppDatabase db, $LocalLecturesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalLecturesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalLecturesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalLecturesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String?> courseId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> titleGenerated = const Value.absent(),
                Value<int?> expectedChunks = const Value.absent(),
                Value<DateTime?> lectureDatetime = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> whisperContext = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime?> lastAccessedAt = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> topicMapMovePending = const Value.absent(),
                Value<String?> pendingTopicMapStaleCourseId =
                    const Value.absent(),
                Value<bool> autoStartAnalysis = const Value.absent(),
                Value<bool> isRealtime = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalLecturesCompanion(
                id: id,
                userId: userId,
                courseId: courseId,
                title: title,
                titleGenerated: titleGenerated,
                expectedChunks: expectedChunks,
                lectureDatetime: lectureDatetime,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                whisperContext: whisperContext,
                summary: summary,
                audioPath: audioPath,
                metadataJson: metadataJson,
                syncStatus: syncStatus,
                lastAccessedAt: lastAccessedAt,
                isPinned: isPinned,
                topicMapMovePending: topicMapMovePending,
                pendingTopicMapStaleCourseId: pendingTopicMapStaleCourseId,
                autoStartAnalysis: autoStartAnalysis,
                isRealtime: isRealtime,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<String?> courseId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> titleGenerated = const Value.absent(),
                Value<int?> expectedChunks = const Value.absent(),
                Value<DateTime?> lectureDatetime = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String?> whisperContext = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> audioPath = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime?> lastAccessedAt = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> topicMapMovePending = const Value.absent(),
                Value<String?> pendingTopicMapStaleCourseId =
                    const Value.absent(),
                Value<bool> autoStartAnalysis = const Value.absent(),
                Value<bool> isRealtime = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalLecturesCompanion.insert(
                id: id,
                userId: userId,
                courseId: courseId,
                title: title,
                titleGenerated: titleGenerated,
                expectedChunks: expectedChunks,
                lectureDatetime: lectureDatetime,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                whisperContext: whisperContext,
                summary: summary,
                audioPath: audioPath,
                metadataJson: metadataJson,
                syncStatus: syncStatus,
                lastAccessedAt: lastAccessedAt,
                isPinned: isPinned,
                topicMapMovePending: topicMapMovePending,
                pendingTopicMapStaleCourseId: pendingTopicMapStaleCourseId,
                autoStartAnalysis: autoStartAnalysis,
                isRealtime: isRealtime,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalLecturesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalLecturesTable,
      LocalLecture,
      $$LocalLecturesTableFilterComposer,
      $$LocalLecturesTableOrderingComposer,
      $$LocalLecturesTableAnnotationComposer,
      $$LocalLecturesTableCreateCompanionBuilder,
      $$LocalLecturesTableUpdateCompanionBuilder,
      (
        LocalLecture,
        BaseReferences<_$AppDatabase, $LocalLecturesTable, LocalLecture>,
      ),
      LocalLecture,
      PrefetchHooks Function()
    >;
typedef $$LocalLectureAssetsTableCreateCompanionBuilder =
    LocalLectureAssetsCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      required String type,
      Value<double> startTime,
      Value<int> sequenceIndex,
      Value<String?> localPath,
      Value<String?> storageBucket,
      Value<String?> storagePath,
      Value<String> uploadStatus,
      Value<int> attemptCount,
      Value<DateTime?> nextRetryAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$LocalLectureAssetsTableUpdateCompanionBuilder =
    LocalLectureAssetsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<String> type,
      Value<double> startTime,
      Value<int> sequenceIndex,
      Value<String?> localPath,
      Value<String?> storageBucket,
      Value<String?> storagePath,
      Value<String> uploadStatus,
      Value<int> attemptCount,
      Value<DateTime?> nextRetryAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalLectureAssetsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalLectureAssetsTable> {
  $$LocalLectureAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequenceIndex => $composableBuilder(
    column: $table.sequenceIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadStatus => $composableBuilder(
    column: $table.uploadStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalLectureAssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalLectureAssetsTable> {
  $$LocalLectureAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get startTime => $composableBuilder(
    column: $table.startTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequenceIndex => $composableBuilder(
    column: $table.sequenceIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadStatus => $composableBuilder(
    column: $table.uploadStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalLectureAssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalLectureAssetsTable> {
  $$LocalLectureAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<int> get sequenceIndex => $composableBuilder(
    column: $table.sequenceIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get storageBucket => $composableBuilder(
    column: $table.storageBucket,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get uploadStatus => $composableBuilder(
    column: $table.uploadStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalLectureAssetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalLectureAssetsTable,
          LocalLectureAsset,
          $$LocalLectureAssetsTableFilterComposer,
          $$LocalLectureAssetsTableOrderingComposer,
          $$LocalLectureAssetsTableAnnotationComposer,
          $$LocalLectureAssetsTableCreateCompanionBuilder,
          $$LocalLectureAssetsTableUpdateCompanionBuilder,
          (
            LocalLectureAsset,
            BaseReferences<
              _$AppDatabase,
              $LocalLectureAssetsTable,
              LocalLectureAsset
            >,
          ),
          LocalLectureAsset,
          PrefetchHooks Function()
        > {
  $$LocalLectureAssetsTableTableManager(
    _$AppDatabase db,
    $LocalLectureAssetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalLectureAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalLectureAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalLectureAssetsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<double> startTime = const Value.absent(),
                Value<int> sequenceIndex = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String?> storageBucket = const Value.absent(),
                Value<String?> storagePath = const Value.absent(),
                Value<String> uploadStatus = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalLectureAssetsCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                type: type,
                startTime: startTime,
                sequenceIndex: sequenceIndex,
                localPath: localPath,
                storageBucket: storageBucket,
                storagePath: storagePath,
                uploadStatus: uploadStatus,
                attemptCount: attemptCount,
                nextRetryAt: nextRetryAt,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                required String type,
                Value<double> startTime = const Value.absent(),
                Value<int> sequenceIndex = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String?> storageBucket = const Value.absent(),
                Value<String?> storagePath = const Value.absent(),
                Value<String> uploadStatus = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalLectureAssetsCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                type: type,
                startTime: startTime,
                sequenceIndex: sequenceIndex,
                localPath: localPath,
                storageBucket: storageBucket,
                storagePath: storagePath,
                uploadStatus: uploadStatus,
                attemptCount: attemptCount,
                nextRetryAt: nextRetryAt,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalLectureAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalLectureAssetsTable,
      LocalLectureAsset,
      $$LocalLectureAssetsTableFilterComposer,
      $$LocalLectureAssetsTableOrderingComposer,
      $$LocalLectureAssetsTableAnnotationComposer,
      $$LocalLectureAssetsTableCreateCompanionBuilder,
      $$LocalLectureAssetsTableUpdateCompanionBuilder,
      (
        LocalLectureAsset,
        BaseReferences<
          _$AppDatabase,
          $LocalLectureAssetsTable,
          LocalLectureAsset
        >,
      ),
      LocalLectureAsset,
      PrefetchHooks Function()
    >;
typedef $$LocalUploadJobsTableCreateCompanionBuilder =
    LocalUploadJobsCompanion Function({
      required String id,
      required String userId,
      Value<String> kind,
      required String lectureId,
      required String assetId,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime?> nextRetryAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$LocalUploadJobsTableUpdateCompanionBuilder =
    LocalUploadJobsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> kind,
      Value<String> lectureId,
      Value<String> assetId,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime?> nextRetryAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalUploadJobsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalUploadJobsTable> {
  $$LocalUploadJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalUploadJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalUploadJobsTable> {
  $$LocalUploadJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalUploadJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalUploadJobsTable> {
  $$LocalUploadJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalUploadJobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalUploadJobsTable,
          LocalUploadJob,
          $$LocalUploadJobsTableFilterComposer,
          $$LocalUploadJobsTableOrderingComposer,
          $$LocalUploadJobsTableAnnotationComposer,
          $$LocalUploadJobsTableCreateCompanionBuilder,
          $$LocalUploadJobsTableUpdateCompanionBuilder,
          (
            LocalUploadJob,
            BaseReferences<
              _$AppDatabase,
              $LocalUploadJobsTable,
              LocalUploadJob
            >,
          ),
          LocalUploadJob,
          PrefetchHooks Function()
        > {
  $$LocalUploadJobsTableTableManager(
    _$AppDatabase db,
    $LocalUploadJobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalUploadJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalUploadJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalUploadJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalUploadJobsCompanion(
                id: id,
                userId: userId,
                kind: kind,
                lectureId: lectureId,
                assetId: assetId,
                status: status,
                attemptCount: attemptCount,
                nextRetryAt: nextRetryAt,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<String> kind = const Value.absent(),
                required String lectureId,
                required String assetId,
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalUploadJobsCompanion.insert(
                id: id,
                userId: userId,
                kind: kind,
                lectureId: lectureId,
                assetId: assetId,
                status: status,
                attemptCount: attemptCount,
                nextRetryAt: nextRetryAt,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalUploadJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalUploadJobsTable,
      LocalUploadJob,
      $$LocalUploadJobsTableFilterComposer,
      $$LocalUploadJobsTableOrderingComposer,
      $$LocalUploadJobsTableAnnotationComposer,
      $$LocalUploadJobsTableCreateCompanionBuilder,
      $$LocalUploadJobsTableUpdateCompanionBuilder,
      (
        LocalUploadJob,
        BaseReferences<_$AppDatabase, $LocalUploadJobsTable, LocalUploadJob>,
      ),
      LocalUploadJob,
      PrefetchHooks Function()
    >;
typedef $$LocalCoursesTableCreateCompanionBuilder =
    LocalCoursesCompanion Function({
      required String id,
      required String userId,
      required String courseTitle,
      Value<String?> courseCode,
      Value<String?> summary,
      Value<String?> schoolId,
      Value<String?> yearId,
      Value<String?> termId,
      Value<String?> subjectId,
      Value<String?> professorId,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$LocalCoursesTableUpdateCompanionBuilder =
    LocalCoursesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> courseTitle,
      Value<String?> courseCode,
      Value<String?> summary,
      Value<String?> schoolId,
      Value<String?> yearId,
      Value<String?> termId,
      Value<String?> subjectId,
      Value<String?> professorId,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$LocalCoursesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalCoursesTable> {
  $$LocalCoursesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get courseTitle => $composableBuilder(
    column: $table.courseTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get courseCode => $composableBuilder(
    column: $table.courseCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get schoolId => $composableBuilder(
    column: $table.schoolId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get yearId => $composableBuilder(
    column: $table.yearId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get termId => $composableBuilder(
    column: $table.termId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get professorId => $composableBuilder(
    column: $table.professorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCoursesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalCoursesTable> {
  $$LocalCoursesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get courseTitle => $composableBuilder(
    column: $table.courseTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get courseCode => $composableBuilder(
    column: $table.courseCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get schoolId => $composableBuilder(
    column: $table.schoolId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get yearId => $composableBuilder(
    column: $table.yearId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get termId => $composableBuilder(
    column: $table.termId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get professorId => $composableBuilder(
    column: $table.professorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCoursesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalCoursesTable> {
  $$LocalCoursesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get courseTitle => $composableBuilder(
    column: $table.courseTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get courseCode => $composableBuilder(
    column: $table.courseCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get schoolId =>
      $composableBuilder(column: $table.schoolId, builder: (column) => column);

  GeneratedColumn<String> get yearId =>
      $composableBuilder(column: $table.yearId, builder: (column) => column);

  GeneratedColumn<String> get termId =>
      $composableBuilder(column: $table.termId, builder: (column) => column);

  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get professorId => $composableBuilder(
    column: $table.professorId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$LocalCoursesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalCoursesTable,
          LocalCourse,
          $$LocalCoursesTableFilterComposer,
          $$LocalCoursesTableOrderingComposer,
          $$LocalCoursesTableAnnotationComposer,
          $$LocalCoursesTableCreateCompanionBuilder,
          $$LocalCoursesTableUpdateCompanionBuilder,
          (
            LocalCourse,
            BaseReferences<_$AppDatabase, $LocalCoursesTable, LocalCourse>,
          ),
          LocalCourse,
          PrefetchHooks Function()
        > {
  $$LocalCoursesTableTableManager(_$AppDatabase db, $LocalCoursesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCoursesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCoursesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCoursesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> courseTitle = const Value.absent(),
                Value<String?> courseCode = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> schoolId = const Value.absent(),
                Value<String?> yearId = const Value.absent(),
                Value<String?> termId = const Value.absent(),
                Value<String?> subjectId = const Value.absent(),
                Value<String?> professorId = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCoursesCompanion(
                id: id,
                userId: userId,
                courseTitle: courseTitle,
                courseCode: courseCode,
                summary: summary,
                schoolId: schoolId,
                yearId: yearId,
                termId: termId,
                subjectId: subjectId,
                professorId: professorId,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String courseTitle,
                Value<String?> courseCode = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> schoolId = const Value.absent(),
                Value<String?> yearId = const Value.absent(),
                Value<String?> termId = const Value.absent(),
                Value<String?> subjectId = const Value.absent(),
                Value<String?> professorId = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCoursesCompanion.insert(
                id: id,
                userId: userId,
                courseTitle: courseTitle,
                courseCode: courseCode,
                summary: summary,
                schoolId: schoolId,
                yearId: yearId,
                termId: termId,
                subjectId: subjectId,
                professorId: professorId,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCoursesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalCoursesTable,
      LocalCourse,
      $$LocalCoursesTableFilterComposer,
      $$LocalCoursesTableOrderingComposer,
      $$LocalCoursesTableAnnotationComposer,
      $$LocalCoursesTableCreateCompanionBuilder,
      $$LocalCoursesTableUpdateCompanionBuilder,
      (
        LocalCourse,
        BaseReferences<_$AppDatabase, $LocalCoursesTable, LocalCourse>,
      ),
      LocalCourse,
      PrefetchHooks Function()
    >;
typedef $$LocalCourseAttributesTableCreateCompanionBuilder =
    LocalCourseAttributesCompanion Function({
      required String id,
      required String userId,
      required String attributeType,
      required String attributeName,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$LocalCourseAttributesTableUpdateCompanionBuilder =
    LocalCourseAttributesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> attributeType,
      Value<String> attributeName,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$LocalCourseAttributesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalCourseAttributesTable> {
  $$LocalCourseAttributesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attributeType => $composableBuilder(
    column: $table.attributeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attributeName => $composableBuilder(
    column: $table.attributeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCourseAttributesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalCourseAttributesTable> {
  $$LocalCourseAttributesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attributeType => $composableBuilder(
    column: $table.attributeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attributeName => $composableBuilder(
    column: $table.attributeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCourseAttributesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalCourseAttributesTable> {
  $$LocalCourseAttributesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get attributeType => $composableBuilder(
    column: $table.attributeType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attributeName => $composableBuilder(
    column: $table.attributeName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$LocalCourseAttributesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalCourseAttributesTable,
          LocalCourseAttribute,
          $$LocalCourseAttributesTableFilterComposer,
          $$LocalCourseAttributesTableOrderingComposer,
          $$LocalCourseAttributesTableAnnotationComposer,
          $$LocalCourseAttributesTableCreateCompanionBuilder,
          $$LocalCourseAttributesTableUpdateCompanionBuilder,
          (
            LocalCourseAttribute,
            BaseReferences<
              _$AppDatabase,
              $LocalCourseAttributesTable,
              LocalCourseAttribute
            >,
          ),
          LocalCourseAttribute,
          PrefetchHooks Function()
        > {
  $$LocalCourseAttributesTableTableManager(
    _$AppDatabase db,
    $LocalCourseAttributesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCourseAttributesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalCourseAttributesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalCourseAttributesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> attributeType = const Value.absent(),
                Value<String> attributeName = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCourseAttributesCompanion(
                id: id,
                userId: userId,
                attributeType: attributeType,
                attributeName: attributeName,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String attributeType,
                required String attributeName,
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCourseAttributesCompanion.insert(
                id: id,
                userId: userId,
                attributeType: attributeType,
                attributeName: attributeName,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCourseAttributesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalCourseAttributesTable,
      LocalCourseAttribute,
      $$LocalCourseAttributesTableFilterComposer,
      $$LocalCourseAttributesTableOrderingComposer,
      $$LocalCourseAttributesTableAnnotationComposer,
      $$LocalCourseAttributesTableCreateCompanionBuilder,
      $$LocalCourseAttributesTableUpdateCompanionBuilder,
      (
        LocalCourseAttribute,
        BaseReferences<
          _$AppDatabase,
          $LocalCourseAttributesTable,
          LocalCourseAttribute
        >,
      ),
      LocalCourseAttribute,
      PrefetchHooks Function()
    >;
typedef $$LocalAnnouncementsTableCreateCompanionBuilder =
    LocalAnnouncementsCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      required String type,
      required String title,
      Value<String?> description,
      Value<String?> location,
      Value<String?> startSid,
      Value<String?> endSid,
      Value<String?> relatedTopicTitle,
      Value<String?> datetimeParametersJson,
      Value<DateTime?> completedAt,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$LocalAnnouncementsTableUpdateCompanionBuilder =
    LocalAnnouncementsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<String> type,
      Value<String> title,
      Value<String?> description,
      Value<String?> location,
      Value<String?> startSid,
      Value<String?> endSid,
      Value<String?> relatedTopicTitle,
      Value<String?> datetimeParametersJson,
      Value<DateTime?> completedAt,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$LocalAnnouncementsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalAnnouncementsTable> {
  $$LocalAnnouncementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startSid => $composableBuilder(
    column: $table.startSid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endSid => $composableBuilder(
    column: $table.endSid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relatedTopicTitle => $composableBuilder(
    column: $table.relatedTopicTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datetimeParametersJson => $composableBuilder(
    column: $table.datetimeParametersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalAnnouncementsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalAnnouncementsTable> {
  $$LocalAnnouncementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startSid => $composableBuilder(
    column: $table.startSid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endSid => $composableBuilder(
    column: $table.endSid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relatedTopicTitle => $composableBuilder(
    column: $table.relatedTopicTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datetimeParametersJson => $composableBuilder(
    column: $table.datetimeParametersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalAnnouncementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalAnnouncementsTable> {
  $$LocalAnnouncementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get startSid =>
      $composableBuilder(column: $table.startSid, builder: (column) => column);

  GeneratedColumn<String> get endSid =>
      $composableBuilder(column: $table.endSid, builder: (column) => column);

  GeneratedColumn<String> get relatedTopicTitle => $composableBuilder(
    column: $table.relatedTopicTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get datetimeParametersJson => $composableBuilder(
    column: $table.datetimeParametersJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$LocalAnnouncementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalAnnouncementsTable,
          LocalAnnouncement,
          $$LocalAnnouncementsTableFilterComposer,
          $$LocalAnnouncementsTableOrderingComposer,
          $$LocalAnnouncementsTableAnnotationComposer,
          $$LocalAnnouncementsTableCreateCompanionBuilder,
          $$LocalAnnouncementsTableUpdateCompanionBuilder,
          (
            LocalAnnouncement,
            BaseReferences<
              _$AppDatabase,
              $LocalAnnouncementsTable,
              LocalAnnouncement
            >,
          ),
          LocalAnnouncement,
          PrefetchHooks Function()
        > {
  $$LocalAnnouncementsTableTableManager(
    _$AppDatabase db,
    $LocalAnnouncementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAnnouncementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAnnouncementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAnnouncementsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> startSid = const Value.absent(),
                Value<String?> endSid = const Value.absent(),
                Value<String?> relatedTopicTitle = const Value.absent(),
                Value<String?> datetimeParametersJson = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAnnouncementsCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                type: type,
                title: title,
                description: description,
                location: location,
                startSid: startSid,
                endSid: endSid,
                relatedTopicTitle: relatedTopicTitle,
                datetimeParametersJson: datetimeParametersJson,
                completedAt: completedAt,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                required String type,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> startSid = const Value.absent(),
                Value<String?> endSid = const Value.absent(),
                Value<String?> relatedTopicTitle = const Value.absent(),
                Value<String?> datetimeParametersJson = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAnnouncementsCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                type: type,
                title: title,
                description: description,
                location: location,
                startSid: startSid,
                endSid: endSid,
                relatedTopicTitle: relatedTopicTitle,
                datetimeParametersJson: datetimeParametersJson,
                completedAt: completedAt,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalAnnouncementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalAnnouncementsTable,
      LocalAnnouncement,
      $$LocalAnnouncementsTableFilterComposer,
      $$LocalAnnouncementsTableOrderingComposer,
      $$LocalAnnouncementsTableAnnotationComposer,
      $$LocalAnnouncementsTableCreateCompanionBuilder,
      $$LocalAnnouncementsTableUpdateCompanionBuilder,
      (
        LocalAnnouncement,
        BaseReferences<
          _$AppDatabase,
          $LocalAnnouncementsTable,
          LocalAnnouncement
        >,
      ),
      LocalAnnouncement,
      PrefetchHooks Function()
    >;
typedef $$LocalLectureMomentsTableCreateCompanionBuilder =
    LocalLectureMomentsCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      required String momentType,
      Value<String?> noteText,
      required int timestampSec,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$LocalLectureMomentsTableUpdateCompanionBuilder =
    LocalLectureMomentsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<String> momentType,
      Value<String?> noteText,
      Value<int> timestampSec,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });

class $$LocalLectureMomentsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalLectureMomentsTable> {
  $$LocalLectureMomentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get momentType => $composableBuilder(
    column: $table.momentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteText => $composableBuilder(
    column: $table.noteText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampSec => $composableBuilder(
    column: $table.timestampSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalLectureMomentsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalLectureMomentsTable> {
  $$LocalLectureMomentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get momentType => $composableBuilder(
    column: $table.momentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteText => $composableBuilder(
    column: $table.noteText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampSec => $composableBuilder(
    column: $table.timestampSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalLectureMomentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalLectureMomentsTable> {
  $$LocalLectureMomentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<String> get momentType => $composableBuilder(
    column: $table.momentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get noteText =>
      $composableBuilder(column: $table.noteText, builder: (column) => column);

  GeneratedColumn<int> get timestampSec => $composableBuilder(
    column: $table.timestampSec,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$LocalLectureMomentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalLectureMomentsTable,
          LocalLectureMoment,
          $$LocalLectureMomentsTableFilterComposer,
          $$LocalLectureMomentsTableOrderingComposer,
          $$LocalLectureMomentsTableAnnotationComposer,
          $$LocalLectureMomentsTableCreateCompanionBuilder,
          $$LocalLectureMomentsTableUpdateCompanionBuilder,
          (
            LocalLectureMoment,
            BaseReferences<
              _$AppDatabase,
              $LocalLectureMomentsTable,
              LocalLectureMoment
            >,
          ),
          LocalLectureMoment,
          PrefetchHooks Function()
        > {
  $$LocalLectureMomentsTableTableManager(
    _$AppDatabase db,
    $LocalLectureMomentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalLectureMomentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalLectureMomentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalLectureMomentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<String> momentType = const Value.absent(),
                Value<String?> noteText = const Value.absent(),
                Value<int> timestampSec = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalLectureMomentsCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                momentType: momentType,
                noteText: noteText,
                timestampSec: timestampSec,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                required String momentType,
                Value<String?> noteText = const Value.absent(),
                required int timestampSec,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalLectureMomentsCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                momentType: momentType,
                noteText: noteText,
                timestampSec: timestampSec,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalLectureMomentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalLectureMomentsTable,
      LocalLectureMoment,
      $$LocalLectureMomentsTableFilterComposer,
      $$LocalLectureMomentsTableOrderingComposer,
      $$LocalLectureMomentsTableAnnotationComposer,
      $$LocalLectureMomentsTableCreateCompanionBuilder,
      $$LocalLectureMomentsTableUpdateCompanionBuilder,
      (
        LocalLectureMoment,
        BaseReferences<
          _$AppDatabase,
          $LocalLectureMomentsTable,
          LocalLectureMoment
        >,
      ),
      LocalLectureMoment,
      PrefetchHooks Function()
    >;
typedef $$LocalAsrModelsTableCreateCompanionBuilder =
    LocalAsrModelsCompanion Function({
      required String groupKey,
      required String modelId,
      required int engineCompatVersion,
      required int modelVersion,
      required String localPath,
      required int sizeBytes,
      required String status,
      Value<DateTime?> downloadedAt,
      Value<DateTime?> lastUsedAt,
      Value<int> rowid,
    });
typedef $$LocalAsrModelsTableUpdateCompanionBuilder =
    LocalAsrModelsCompanion Function({
      Value<String> groupKey,
      Value<String> modelId,
      Value<int> engineCompatVersion,
      Value<int> modelVersion,
      Value<String> localPath,
      Value<int> sizeBytes,
      Value<String> status,
      Value<DateTime?> downloadedAt,
      Value<DateTime?> lastUsedAt,
      Value<int> rowid,
    });

class $$LocalAsrModelsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalAsrModelsTable> {
  $$LocalAsrModelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupKey => $composableBuilder(
    column: $table.groupKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get engineCompatVersion => $composableBuilder(
    column: $table.engineCompatVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalAsrModelsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalAsrModelsTable> {
  $$LocalAsrModelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupKey => $composableBuilder(
    column: $table.groupKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get engineCompatVersion => $composableBuilder(
    column: $table.engineCompatVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalAsrModelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalAsrModelsTable> {
  $$LocalAsrModelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupKey =>
      $composableBuilder(column: $table.groupKey, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<int> get engineCompatVersion => $composableBuilder(
    column: $table.engineCompatVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$LocalAsrModelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalAsrModelsTable,
          LocalAsrModel,
          $$LocalAsrModelsTableFilterComposer,
          $$LocalAsrModelsTableOrderingComposer,
          $$LocalAsrModelsTableAnnotationComposer,
          $$LocalAsrModelsTableCreateCompanionBuilder,
          $$LocalAsrModelsTableUpdateCompanionBuilder,
          (
            LocalAsrModel,
            BaseReferences<_$AppDatabase, $LocalAsrModelsTable, LocalAsrModel>,
          ),
          LocalAsrModel,
          PrefetchHooks Function()
        > {
  $$LocalAsrModelsTableTableManager(
    _$AppDatabase db,
    $LocalAsrModelsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalAsrModelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalAsrModelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalAsrModelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupKey = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<int> engineCompatVersion = const Value.absent(),
                Value<int> modelVersion = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> downloadedAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAsrModelsCompanion(
                groupKey: groupKey,
                modelId: modelId,
                engineCompatVersion: engineCompatVersion,
                modelVersion: modelVersion,
                localPath: localPath,
                sizeBytes: sizeBytes,
                status: status,
                downloadedAt: downloadedAt,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupKey,
                required String modelId,
                required int engineCompatVersion,
                required int modelVersion,
                required String localPath,
                required int sizeBytes,
                required String status,
                Value<DateTime?> downloadedAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalAsrModelsCompanion.insert(
                groupKey: groupKey,
                modelId: modelId,
                engineCompatVersion: engineCompatVersion,
                modelVersion: modelVersion,
                localPath: localPath,
                sizeBytes: sizeBytes,
                status: status,
                downloadedAt: downloadedAt,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalAsrModelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalAsrModelsTable,
      LocalAsrModel,
      $$LocalAsrModelsTableFilterComposer,
      $$LocalAsrModelsTableOrderingComposer,
      $$LocalAsrModelsTableAnnotationComposer,
      $$LocalAsrModelsTableCreateCompanionBuilder,
      $$LocalAsrModelsTableUpdateCompanionBuilder,
      (
        LocalAsrModel,
        BaseReferences<_$AppDatabase, $LocalAsrModelsTable, LocalAsrModel>,
      ),
      LocalAsrModel,
      PrefetchHooks Function()
    >;
typedef $$LocalFunFactsTableCreateCompanionBuilder =
    LocalFunFactsCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      Value<String?> title,
      required String hook,
      required String body,
      Value<String?> metadataJson,
      Value<String?> reaction,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$LocalFunFactsTableUpdateCompanionBuilder =
    LocalFunFactsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<String?> title,
      Value<String> hook,
      Value<String> body,
      Value<String?> metadataJson,
      Value<String?> reaction,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });

class $$LocalFunFactsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalFunFactsTable> {
  $$LocalFunFactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hook => $composableBuilder(
    column: $table.hook,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reaction => $composableBuilder(
    column: $table.reaction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalFunFactsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalFunFactsTable> {
  $$LocalFunFactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hook => $composableBuilder(
    column: $table.hook,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reaction => $composableBuilder(
    column: $table.reaction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFunFactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalFunFactsTable> {
  $$LocalFunFactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get hook =>
      $composableBuilder(column: $table.hook, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reaction =>
      $composableBuilder(column: $table.reaction, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$LocalFunFactsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalFunFactsTable,
          LocalFunFact,
          $$LocalFunFactsTableFilterComposer,
          $$LocalFunFactsTableOrderingComposer,
          $$LocalFunFactsTableAnnotationComposer,
          $$LocalFunFactsTableCreateCompanionBuilder,
          $$LocalFunFactsTableUpdateCompanionBuilder,
          (
            LocalFunFact,
            BaseReferences<_$AppDatabase, $LocalFunFactsTable, LocalFunFact>,
          ),
          LocalFunFact,
          PrefetchHooks Function()
        > {
  $$LocalFunFactsTableTableManager(_$AppDatabase db, $LocalFunFactsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFunFactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFunFactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalFunFactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> hook = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<String?> reaction = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFunFactsCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                title: title,
                hook: hook,
                body: body,
                metadataJson: metadataJson,
                reaction: reaction,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                Value<String?> title = const Value.absent(),
                required String hook,
                required String body,
                Value<String?> metadataJson = const Value.absent(),
                Value<String?> reaction = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFunFactsCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                title: title,
                hook: hook,
                body: body,
                metadataJson: metadataJson,
                reaction: reaction,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalFunFactsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalFunFactsTable,
      LocalFunFact,
      $$LocalFunFactsTableFilterComposer,
      $$LocalFunFactsTableOrderingComposer,
      $$LocalFunFactsTableAnnotationComposer,
      $$LocalFunFactsTableCreateCompanionBuilder,
      $$LocalFunFactsTableUpdateCompanionBuilder,
      (
        LocalFunFact,
        BaseReferences<_$AppDatabase, $LocalFunFactsTable, LocalFunFact>,
      ),
      LocalFunFact,
      PrefetchHooks Function()
    >;
typedef $$LocalReviewCardsTableCreateCompanionBuilder =
    LocalReviewCardsCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      required int topicNumber,
      required String cardContentJson,
      required String cardType,
      Value<String?> title,
      Value<String?> heroEmoji,
      Value<String?> metadataJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$LocalReviewCardsTableUpdateCompanionBuilder =
    LocalReviewCardsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<int> topicNumber,
      Value<String> cardContentJson,
      Value<String> cardType,
      Value<String?> title,
      Value<String?> heroEmoji,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });

class $$LocalReviewCardsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalReviewCardsTable> {
  $$LocalReviewCardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardContentJson => $composableBuilder(
    column: $table.cardContentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardType => $composableBuilder(
    column: $table.cardType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get heroEmoji => $composableBuilder(
    column: $table.heroEmoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalReviewCardsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalReviewCardsTable> {
  $$LocalReviewCardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardContentJson => $composableBuilder(
    column: $table.cardContentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardType => $composableBuilder(
    column: $table.cardType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get heroEmoji => $composableBuilder(
    column: $table.heroEmoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalReviewCardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalReviewCardsTable> {
  $$LocalReviewCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardContentJson => $composableBuilder(
    column: $table.cardContentJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardType =>
      $composableBuilder(column: $table.cardType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get heroEmoji =>
      $composableBuilder(column: $table.heroEmoji, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$LocalReviewCardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalReviewCardsTable,
          LocalReviewCard,
          $$LocalReviewCardsTableFilterComposer,
          $$LocalReviewCardsTableOrderingComposer,
          $$LocalReviewCardsTableAnnotationComposer,
          $$LocalReviewCardsTableCreateCompanionBuilder,
          $$LocalReviewCardsTableUpdateCompanionBuilder,
          (
            LocalReviewCard,
            BaseReferences<
              _$AppDatabase,
              $LocalReviewCardsTable,
              LocalReviewCard
            >,
          ),
          LocalReviewCard,
          PrefetchHooks Function()
        > {
  $$LocalReviewCardsTableTableManager(
    _$AppDatabase db,
    $LocalReviewCardsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalReviewCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalReviewCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalReviewCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<int> topicNumber = const Value.absent(),
                Value<String> cardContentJson = const Value.absent(),
                Value<String> cardType = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> heroEmoji = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalReviewCardsCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                topicNumber: topicNumber,
                cardContentJson: cardContentJson,
                cardType: cardType,
                title: title,
                heroEmoji: heroEmoji,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                required int topicNumber,
                required String cardContentJson,
                required String cardType,
                Value<String?> title = const Value.absent(),
                Value<String?> heroEmoji = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalReviewCardsCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                topicNumber: topicNumber,
                cardContentJson: cardContentJson,
                cardType: cardType,
                title: title,
                heroEmoji: heroEmoji,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalReviewCardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalReviewCardsTable,
      LocalReviewCard,
      $$LocalReviewCardsTableFilterComposer,
      $$LocalReviewCardsTableOrderingComposer,
      $$LocalReviewCardsTableAnnotationComposer,
      $$LocalReviewCardsTableCreateCompanionBuilder,
      $$LocalReviewCardsTableUpdateCompanionBuilder,
      (
        LocalReviewCard,
        BaseReferences<_$AppDatabase, $LocalReviewCardsTable, LocalReviewCard>,
      ),
      LocalReviewCard,
      PrefetchHooks Function()
    >;
typedef $$LocalDeepNotesTableCreateCompanionBuilder =
    LocalDeepNotesCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      required int topicNumber,
      required String noteContents,
      Value<String?> metadataJson,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$LocalDeepNotesTableUpdateCompanionBuilder =
    LocalDeepNotesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<int> topicNumber,
      Value<String> noteContents,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });

class $$LocalDeepNotesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalDeepNotesTable> {
  $$LocalDeepNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteContents => $composableBuilder(
    column: $table.noteContents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalDeepNotesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalDeepNotesTable> {
  $$LocalDeepNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteContents => $composableBuilder(
    column: $table.noteContents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalDeepNotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalDeepNotesTable> {
  $$LocalDeepNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get noteContents => $composableBuilder(
    column: $table.noteContents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$LocalDeepNotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalDeepNotesTable,
          LocalDeepNote,
          $$LocalDeepNotesTableFilterComposer,
          $$LocalDeepNotesTableOrderingComposer,
          $$LocalDeepNotesTableAnnotationComposer,
          $$LocalDeepNotesTableCreateCompanionBuilder,
          $$LocalDeepNotesTableUpdateCompanionBuilder,
          (
            LocalDeepNote,
            BaseReferences<_$AppDatabase, $LocalDeepNotesTable, LocalDeepNote>,
          ),
          LocalDeepNote,
          PrefetchHooks Function()
        > {
  $$LocalDeepNotesTableTableManager(
    _$AppDatabase db,
    $LocalDeepNotesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalDeepNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalDeepNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalDeepNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<int> topicNumber = const Value.absent(),
                Value<String> noteContents = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDeepNotesCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                topicNumber: topicNumber,
                noteContents: noteContents,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                required int topicNumber,
                required String noteContents,
                Value<String?> metadataJson = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDeepNotesCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                topicNumber: topicNumber,
                noteContents: noteContents,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalDeepNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalDeepNotesTable,
      LocalDeepNote,
      $$LocalDeepNotesTableFilterComposer,
      $$LocalDeepNotesTableOrderingComposer,
      $$LocalDeepNotesTableAnnotationComposer,
      $$LocalDeepNotesTableCreateCompanionBuilder,
      $$LocalDeepNotesTableUpdateCompanionBuilder,
      (
        LocalDeepNote,
        BaseReferences<_$AppDatabase, $LocalDeepNotesTable, LocalDeepNote>,
      ),
      LocalDeepNote,
      PrefetchHooks Function()
    >;
typedef $$LocalKeywordsTableCreateCompanionBuilder =
    LocalKeywordsCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      required int topicNumber,
      required String keyword,
      required String definition,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$LocalKeywordsTableUpdateCompanionBuilder =
    LocalKeywordsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<int> topicNumber,
      Value<String> keyword,
      Value<String> definition,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });

class $$LocalKeywordsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalKeywordsTable> {
  $$LocalKeywordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get definition => $composableBuilder(
    column: $table.definition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalKeywordsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalKeywordsTable> {
  $$LocalKeywordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get definition => $composableBuilder(
    column: $table.definition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalKeywordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalKeywordsTable> {
  $$LocalKeywordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<int> get topicNumber => $composableBuilder(
    column: $table.topicNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get keyword =>
      $composableBuilder(column: $table.keyword, builder: (column) => column);

  GeneratedColumn<String> get definition => $composableBuilder(
    column: $table.definition,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$LocalKeywordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalKeywordsTable,
          LocalKeyword,
          $$LocalKeywordsTableFilterComposer,
          $$LocalKeywordsTableOrderingComposer,
          $$LocalKeywordsTableAnnotationComposer,
          $$LocalKeywordsTableCreateCompanionBuilder,
          $$LocalKeywordsTableUpdateCompanionBuilder,
          (
            LocalKeyword,
            BaseReferences<_$AppDatabase, $LocalKeywordsTable, LocalKeyword>,
          ),
          LocalKeyword,
          PrefetchHooks Function()
        > {
  $$LocalKeywordsTableTableManager(_$AppDatabase db, $LocalKeywordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalKeywordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalKeywordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalKeywordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<int> topicNumber = const Value.absent(),
                Value<String> keyword = const Value.absent(),
                Value<String> definition = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalKeywordsCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                topicNumber: topicNumber,
                keyword: keyword,
                definition: definition,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                required int topicNumber,
                required String keyword,
                required String definition,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalKeywordsCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                topicNumber: topicNumber,
                keyword: keyword,
                definition: definition,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalKeywordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalKeywordsTable,
      LocalKeyword,
      $$LocalKeywordsTableFilterComposer,
      $$LocalKeywordsTableOrderingComposer,
      $$LocalKeywordsTableAnnotationComposer,
      $$LocalKeywordsTableCreateCompanionBuilder,
      $$LocalKeywordsTableUpdateCompanionBuilder,
      (
        LocalKeyword,
        BaseReferences<_$AppDatabase, $LocalKeywordsTable, LocalKeyword>,
      ),
      LocalKeyword,
      PrefetchHooks Function()
    >;
typedef $$LocalLectureTopicsTableCreateCompanionBuilder =
    LocalLectureTopicsCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      required int topicIndex,
      required String topicTitle,
      required String topicType,
      Value<String?> summary,
      Value<String?> startSid,
      Value<String?> endSid,
      Value<String?> imagePath,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$LocalLectureTopicsTableUpdateCompanionBuilder =
    LocalLectureTopicsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<int> topicIndex,
      Value<String> topicTitle,
      Value<String> topicType,
      Value<String?> summary,
      Value<String?> startSid,
      Value<String?> endSid,
      Value<String?> imagePath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });

class $$LocalLectureTopicsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalLectureTopicsTable> {
  $$LocalLectureTopicsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get topicIndex => $composableBuilder(
    column: $table.topicIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topicTitle => $composableBuilder(
    column: $table.topicTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get topicType => $composableBuilder(
    column: $table.topicType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startSid => $composableBuilder(
    column: $table.startSid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endSid => $composableBuilder(
    column: $table.endSid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalLectureTopicsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalLectureTopicsTable> {
  $$LocalLectureTopicsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get topicIndex => $composableBuilder(
    column: $table.topicIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topicTitle => $composableBuilder(
    column: $table.topicTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get topicType => $composableBuilder(
    column: $table.topicType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get summary => $composableBuilder(
    column: $table.summary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startSid => $composableBuilder(
    column: $table.startSid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endSid => $composableBuilder(
    column: $table.endSid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalLectureTopicsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalLectureTopicsTable> {
  $$LocalLectureTopicsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<int> get topicIndex => $composableBuilder(
    column: $table.topicIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get topicTitle => $composableBuilder(
    column: $table.topicTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get topicType =>
      $composableBuilder(column: $table.topicType, builder: (column) => column);

  GeneratedColumn<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<String> get startSid =>
      $composableBuilder(column: $table.startSid, builder: (column) => column);

  GeneratedColumn<String> get endSid =>
      $composableBuilder(column: $table.endSid, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$LocalLectureTopicsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalLectureTopicsTable,
          LocalLectureTopic,
          $$LocalLectureTopicsTableFilterComposer,
          $$LocalLectureTopicsTableOrderingComposer,
          $$LocalLectureTopicsTableAnnotationComposer,
          $$LocalLectureTopicsTableCreateCompanionBuilder,
          $$LocalLectureTopicsTableUpdateCompanionBuilder,
          (
            LocalLectureTopic,
            BaseReferences<
              _$AppDatabase,
              $LocalLectureTopicsTable,
              LocalLectureTopic
            >,
          ),
          LocalLectureTopic,
          PrefetchHooks Function()
        > {
  $$LocalLectureTopicsTableTableManager(
    _$AppDatabase db,
    $LocalLectureTopicsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalLectureTopicsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalLectureTopicsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalLectureTopicsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<int> topicIndex = const Value.absent(),
                Value<String> topicTitle = const Value.absent(),
                Value<String> topicType = const Value.absent(),
                Value<String?> summary = const Value.absent(),
                Value<String?> startSid = const Value.absent(),
                Value<String?> endSid = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalLectureTopicsCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                topicIndex: topicIndex,
                topicTitle: topicTitle,
                topicType: topicType,
                summary: summary,
                startSid: startSid,
                endSid: endSid,
                imagePath: imagePath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                required int topicIndex,
                required String topicTitle,
                required String topicType,
                Value<String?> summary = const Value.absent(),
                Value<String?> startSid = const Value.absent(),
                Value<String?> endSid = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalLectureTopicsCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                topicIndex: topicIndex,
                topicTitle: topicTitle,
                topicType: topicType,
                summary: summary,
                startSid: startSid,
                endSid: endSid,
                imagePath: imagePath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalLectureTopicsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalLectureTopicsTable,
      LocalLectureTopic,
      $$LocalLectureTopicsTableFilterComposer,
      $$LocalLectureTopicsTableOrderingComposer,
      $$LocalLectureTopicsTableAnnotationComposer,
      $$LocalLectureTopicsTableCreateCompanionBuilder,
      $$LocalLectureTopicsTableUpdateCompanionBuilder,
      (
        LocalLectureTopic,
        BaseReferences<
          _$AppDatabase,
          $LocalLectureTopicsTable,
          LocalLectureTopic
        >,
      ),
      LocalLectureTopic,
      PrefetchHooks Function()
    >;
typedef $$LocalTopicMapsTableCreateCompanionBuilder =
    LocalTopicMapsCompanion Function({
      required String courseId,
      required String userId,
      required String mapJson,
      Value<bool> isStale,
      required DateTime updatedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$LocalTopicMapsTableUpdateCompanionBuilder =
    LocalTopicMapsCompanion Function({
      Value<String> courseId,
      Value<String> userId,
      Value<String> mapJson,
      Value<bool> isStale,
      Value<DateTime> updatedAt,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });

class $$LocalTopicMapsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalTopicMapsTable> {
  $$LocalTopicMapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mapJson => $composableBuilder(
    column: $table.mapJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isStale => $composableBuilder(
    column: $table.isStale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalTopicMapsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalTopicMapsTable> {
  $$LocalTopicMapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mapJson => $composableBuilder(
    column: $table.mapJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isStale => $composableBuilder(
    column: $table.isStale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalTopicMapsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalTopicMapsTable> {
  $$LocalTopicMapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get courseId =>
      $composableBuilder(column: $table.courseId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get mapJson =>
      $composableBuilder(column: $table.mapJson, builder: (column) => column);

  GeneratedColumn<bool> get isStale =>
      $composableBuilder(column: $table.isStale, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$LocalTopicMapsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalTopicMapsTable,
          LocalTopicMap,
          $$LocalTopicMapsTableFilterComposer,
          $$LocalTopicMapsTableOrderingComposer,
          $$LocalTopicMapsTableAnnotationComposer,
          $$LocalTopicMapsTableCreateCompanionBuilder,
          $$LocalTopicMapsTableUpdateCompanionBuilder,
          (
            LocalTopicMap,
            BaseReferences<_$AppDatabase, $LocalTopicMapsTable, LocalTopicMap>,
          ),
          LocalTopicMap,
          PrefetchHooks Function()
        > {
  $$LocalTopicMapsTableTableManager(
    _$AppDatabase db,
    $LocalTopicMapsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalTopicMapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalTopicMapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalTopicMapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> courseId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> mapJson = const Value.absent(),
                Value<bool> isStale = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTopicMapsCompanion(
                courseId: courseId,
                userId: userId,
                mapJson: mapJson,
                isStale: isStale,
                updatedAt: updatedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String courseId,
                required String userId,
                required String mapJson,
                Value<bool> isStale = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalTopicMapsCompanion.insert(
                courseId: courseId,
                userId: userId,
                mapJson: mapJson,
                isStale: isStale,
                updatedAt: updatedAt,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalTopicMapsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalTopicMapsTable,
      LocalTopicMap,
      $$LocalTopicMapsTableFilterComposer,
      $$LocalTopicMapsTableOrderingComposer,
      $$LocalTopicMapsTableAnnotationComposer,
      $$LocalTopicMapsTableCreateCompanionBuilder,
      $$LocalTopicMapsTableUpdateCompanionBuilder,
      (
        LocalTopicMap,
        BaseReferences<_$AppDatabase, $LocalTopicMapsTable, LocalTopicMap>,
      ),
      LocalTopicMap,
      PrefetchHooks Function()
    >;
typedef $$LocalSyncCursorsTableCreateCompanionBuilder =
    LocalSyncCursorsCompanion Function({
      required String userId,
      required String entityType,
      Value<DateTime?> lastPulledAt,
      Value<DateTime?> lastFullPulledAt,
      Value<int> rowid,
    });
typedef $$LocalSyncCursorsTableUpdateCompanionBuilder =
    LocalSyncCursorsCompanion Function({
      Value<String> userId,
      Value<String> entityType,
      Value<DateTime?> lastPulledAt,
      Value<DateTime?> lastFullPulledAt,
      Value<int> rowid,
    });

class $$LocalSyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSyncCursorsTable> {
  $$LocalSyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastFullPulledAt => $composableBuilder(
    column: $table.lastFullPulledAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSyncCursorsTable> {
  $$LocalSyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastFullPulledAt => $composableBuilder(
    column: $table.lastFullPulledAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSyncCursorsTable> {
  $$LocalSyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastFullPulledAt => $composableBuilder(
    column: $table.lastFullPulledAt,
    builder: (column) => column,
  );
}

class $$LocalSyncCursorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalSyncCursorsTable,
          LocalSyncCursor,
          $$LocalSyncCursorsTableFilterComposer,
          $$LocalSyncCursorsTableOrderingComposer,
          $$LocalSyncCursorsTableAnnotationComposer,
          $$LocalSyncCursorsTableCreateCompanionBuilder,
          $$LocalSyncCursorsTableUpdateCompanionBuilder,
          (
            LocalSyncCursor,
            BaseReferences<
              _$AppDatabase,
              $LocalSyncCursorsTable,
              LocalSyncCursor
            >,
          ),
          LocalSyncCursor,
          PrefetchHooks Function()
        > {
  $$LocalSyncCursorsTableTableManager(
    _$AppDatabase db,
    $LocalSyncCursorsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<DateTime?> lastPulledAt = const Value.absent(),
                Value<DateTime?> lastFullPulledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncCursorsCompanion(
                userId: userId,
                entityType: entityType,
                lastPulledAt: lastPulledAt,
                lastFullPulledAt: lastFullPulledAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String entityType,
                Value<DateTime?> lastPulledAt = const Value.absent(),
                Value<DateTime?> lastFullPulledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSyncCursorsCompanion.insert(
                userId: userId,
                entityType: entityType,
                lastPulledAt: lastPulledAt,
                lastFullPulledAt: lastFullPulledAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalSyncCursorsTable,
      LocalSyncCursor,
      $$LocalSyncCursorsTableFilterComposer,
      $$LocalSyncCursorsTableOrderingComposer,
      $$LocalSyncCursorsTableAnnotationComposer,
      $$LocalSyncCursorsTableCreateCompanionBuilder,
      $$LocalSyncCursorsTableUpdateCompanionBuilder,
      (
        LocalSyncCursor,
        BaseReferences<_$AppDatabase, $LocalSyncCursorsTable, LocalSyncCursor>,
      ),
      LocalSyncCursor,
      PrefetchHooks Function()
    >;
typedef $$LocalCacheEntriesTableCreateCompanionBuilder =
    LocalCacheEntriesCompanion Function({
      required String id,
      required String userId,
      required String lectureId,
      required String localFilePath,
      required int sizeBytes,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });
typedef $$LocalCacheEntriesTableUpdateCompanionBuilder =
    LocalCacheEntriesCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> lectureId,
      Value<String> localFilePath,
      Value<int> sizeBytes,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$LocalCacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalCacheEntriesTable> {
  $$LocalCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalCacheEntriesTable> {
  $$LocalCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lectureId => $composableBuilder(
    column: $table.lectureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalCacheEntriesTable> {
  $$LocalCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get lectureId =>
      $composableBuilder(column: $table.lectureId, builder: (column) => column);

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$LocalCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalCacheEntriesTable,
          LocalCacheEntry,
          $$LocalCacheEntriesTableFilterComposer,
          $$LocalCacheEntriesTableOrderingComposer,
          $$LocalCacheEntriesTableAnnotationComposer,
          $$LocalCacheEntriesTableCreateCompanionBuilder,
          $$LocalCacheEntriesTableUpdateCompanionBuilder,
          (
            LocalCacheEntry,
            BaseReferences<
              _$AppDatabase,
              $LocalCacheEntriesTable,
              LocalCacheEntry
            >,
          ),
          LocalCacheEntry,
          PrefetchHooks Function()
        > {
  $$LocalCacheEntriesTableTableManager(
    _$AppDatabase db,
    $LocalCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> lectureId = const Value.absent(),
                Value<String> localFilePath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCacheEntriesCompanion(
                id: id,
                userId: userId,
                lectureId: lectureId,
                localFilePath: localFilePath,
                sizeBytes: sizeBytes,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String lectureId,
                required String localFilePath,
                required int sizeBytes,
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCacheEntriesCompanion.insert(
                id: id,
                userId: userId,
                lectureId: lectureId,
                localFilePath: localFilePath,
                sizeBytes: sizeBytes,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalCacheEntriesTable,
      LocalCacheEntry,
      $$LocalCacheEntriesTableFilterComposer,
      $$LocalCacheEntriesTableOrderingComposer,
      $$LocalCacheEntriesTableAnnotationComposer,
      $$LocalCacheEntriesTableCreateCompanionBuilder,
      $$LocalCacheEntriesTableUpdateCompanionBuilder,
      (
        LocalCacheEntry,
        BaseReferences<_$AppDatabase, $LocalCacheEntriesTable, LocalCacheEntry>,
      ),
      LocalCacheEntry,
      PrefetchHooks Function()
    >;
typedef $$LocalUserProfilesTableCreateCompanionBuilder =
    LocalUserProfilesCompanion Function({
      required String id,
      Value<String?> username,
      Value<String?> avatarUrl,
      Value<String?> bio,
      Value<String?> interests,
      Value<String?> futureGoals,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$LocalUserProfilesTableUpdateCompanionBuilder =
    LocalUserProfilesCompanion Function({
      Value<String> id,
      Value<String?> username,
      Value<String?> avatarUrl,
      Value<String?> bio,
      Value<String?> interests,
      Value<String?> futureGoals,
      Value<String?> metadataJson,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$LocalUserProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalUserProfilesTable> {
  $$LocalUserProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bio => $composableBuilder(
    column: $table.bio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get interests => $composableBuilder(
    column: $table.interests,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get futureGoals => $composableBuilder(
    column: $table.futureGoals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalUserProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalUserProfilesTable> {
  $$LocalUserProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bio => $composableBuilder(
    column: $table.bio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get interests => $composableBuilder(
    column: $table.interests,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get futureGoals => $composableBuilder(
    column: $table.futureGoals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalUserProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalUserProfilesTable> {
  $$LocalUserProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get bio =>
      $composableBuilder(column: $table.bio, builder: (column) => column);

  GeneratedColumn<String> get interests =>
      $composableBuilder(column: $table.interests, builder: (column) => column);

  GeneratedColumn<String> get futureGoals => $composableBuilder(
    column: $table.futureGoals,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalUserProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalUserProfilesTable,
          LocalUserProfile,
          $$LocalUserProfilesTableFilterComposer,
          $$LocalUserProfilesTableOrderingComposer,
          $$LocalUserProfilesTableAnnotationComposer,
          $$LocalUserProfilesTableCreateCompanionBuilder,
          $$LocalUserProfilesTableUpdateCompanionBuilder,
          (
            LocalUserProfile,
            BaseReferences<
              _$AppDatabase,
              $LocalUserProfilesTable,
              LocalUserProfile
            >,
          ),
          LocalUserProfile,
          PrefetchHooks Function()
        > {
  $$LocalUserProfilesTableTableManager(
    _$AppDatabase db,
    $LocalUserProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalUserProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalUserProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalUserProfilesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> bio = const Value.absent(),
                Value<String?> interests = const Value.absent(),
                Value<String?> futureGoals = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalUserProfilesCompanion(
                id: id,
                username: username,
                avatarUrl: avatarUrl,
                bio: bio,
                interests: interests,
                futureGoals: futureGoals,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> username = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> bio = const Value.absent(),
                Value<String?> interests = const Value.absent(),
                Value<String?> futureGoals = const Value.absent(),
                Value<String?> metadataJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalUserProfilesCompanion.insert(
                id: id,
                username: username,
                avatarUrl: avatarUrl,
                bio: bio,
                interests: interests,
                futureGoals: futureGoals,
                metadataJson: metadataJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalUserProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalUserProfilesTable,
      LocalUserProfile,
      $$LocalUserProfilesTableFilterComposer,
      $$LocalUserProfilesTableOrderingComposer,
      $$LocalUserProfilesTableAnnotationComposer,
      $$LocalUserProfilesTableCreateCompanionBuilder,
      $$LocalUserProfilesTableUpdateCompanionBuilder,
      (
        LocalUserProfile,
        BaseReferences<
          _$AppDatabase,
          $LocalUserProfilesTable,
          LocalUserProfile
        >,
      ),
      LocalUserProfile,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalOutboxTableTableManager get localOutbox =>
      $$LocalOutboxTableTableManager(_db, _db.localOutbox);
  $$LocalLecturesTableTableManager get localLectures =>
      $$LocalLecturesTableTableManager(_db, _db.localLectures);
  $$LocalLectureAssetsTableTableManager get localLectureAssets =>
      $$LocalLectureAssetsTableTableManager(_db, _db.localLectureAssets);
  $$LocalUploadJobsTableTableManager get localUploadJobs =>
      $$LocalUploadJobsTableTableManager(_db, _db.localUploadJobs);
  $$LocalCoursesTableTableManager get localCourses =>
      $$LocalCoursesTableTableManager(_db, _db.localCourses);
  $$LocalCourseAttributesTableTableManager get localCourseAttributes =>
      $$LocalCourseAttributesTableTableManager(_db, _db.localCourseAttributes);
  $$LocalAnnouncementsTableTableManager get localAnnouncements =>
      $$LocalAnnouncementsTableTableManager(_db, _db.localAnnouncements);
  $$LocalLectureMomentsTableTableManager get localLectureMoments =>
      $$LocalLectureMomentsTableTableManager(_db, _db.localLectureMoments);
  $$LocalAsrModelsTableTableManager get localAsrModels =>
      $$LocalAsrModelsTableTableManager(_db, _db.localAsrModels);
  $$LocalFunFactsTableTableManager get localFunFacts =>
      $$LocalFunFactsTableTableManager(_db, _db.localFunFacts);
  $$LocalReviewCardsTableTableManager get localReviewCards =>
      $$LocalReviewCardsTableTableManager(_db, _db.localReviewCards);
  $$LocalDeepNotesTableTableManager get localDeepNotes =>
      $$LocalDeepNotesTableTableManager(_db, _db.localDeepNotes);
  $$LocalKeywordsTableTableManager get localKeywords =>
      $$LocalKeywordsTableTableManager(_db, _db.localKeywords);
  $$LocalLectureTopicsTableTableManager get localLectureTopics =>
      $$LocalLectureTopicsTableTableManager(_db, _db.localLectureTopics);
  $$LocalTopicMapsTableTableManager get localTopicMaps =>
      $$LocalTopicMapsTableTableManager(_db, _db.localTopicMaps);
  $$LocalSyncCursorsTableTableManager get localSyncCursors =>
      $$LocalSyncCursorsTableTableManager(_db, _db.localSyncCursors);
  $$LocalCacheEntriesTableTableManager get localCacheEntries =>
      $$LocalCacheEntriesTableTableManager(_db, _db.localCacheEntries);
  $$LocalUserProfilesTableTableManager get localUserProfiles =>
      $$LocalUserProfilesTableTableManager(_db, _db.localUserProfiles);
}
