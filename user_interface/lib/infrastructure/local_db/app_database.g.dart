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
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    op,
    payloadJson,
    enqueuedAt,
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
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('enqueued_at')) {
      context.handle(
        _enqueuedAtMeta,
        enqueuedAt.isAcceptableOrUnknown(data['enqueued_at']!, _enqueuedAtMeta),
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
      )!,
      enqueuedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}enqueued_at'],
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
  final String payloadJson;
  final DateTime enqueuedAt;
  const LocalOutboxData({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.op,
    required this.payloadJson,
    required this.enqueuedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['op'] = Variable<String>(op);
    map['payload_json'] = Variable<String>(payloadJson);
    map['enqueued_at'] = Variable<DateTime>(enqueuedAt);
    return map;
  }

  LocalOutboxCompanion toCompanion(bool nullToAbsent) {
    return LocalOutboxCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      op: Value(op),
      payloadJson: Value(payloadJson),
      enqueuedAt: Value(enqueuedAt),
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
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      enqueuedAt: serializer.fromJson<DateTime>(json['enqueuedAt']),
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
      'payloadJson': serializer.toJson<String>(payloadJson),
      'enqueuedAt': serializer.toJson<DateTime>(enqueuedAt),
    };
  }

  LocalOutboxData copyWith({
    int? id,
    String? entityType,
    String? entityId,
    String? op,
    String? payloadJson,
    DateTime? enqueuedAt,
  }) => LocalOutboxData(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    op: op ?? this.op,
    payloadJson: payloadJson ?? this.payloadJson,
    enqueuedAt: enqueuedAt ?? this.enqueuedAt,
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
          ..write('enqueuedAt: $enqueuedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, entityType, entityId, op, payloadJson, enqueuedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalOutboxData &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.op == this.op &&
          other.payloadJson == this.payloadJson &&
          other.enqueuedAt == this.enqueuedAt);
}

class LocalOutboxCompanion extends UpdateCompanion<LocalOutboxData> {
  final Value<int> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> op;
  final Value<String> payloadJson;
  final Value<DateTime> enqueuedAt;
  const LocalOutboxCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.op = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.enqueuedAt = const Value.absent(),
  });
  LocalOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required String op,
    required String payloadJson,
    this.enqueuedAt = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       op = Value(op),
       payloadJson = Value(payloadJson);
  static Insertable<LocalOutboxData> custom({
    Expression<int>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? op,
    Expression<String>? payloadJson,
    Expression<DateTime>? enqueuedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (op != null) 'op': op,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (enqueuedAt != null) 'enqueued_at': enqueuedAt,
    });
  }

  LocalOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? op,
    Value<String>? payloadJson,
    Value<DateTime>? enqueuedAt,
  }) {
    return LocalOutboxCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      op: op ?? this.op,
      payloadJson: payloadJson ?? this.payloadJson,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
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
          ..write('enqueuedAt: $enqueuedAt')
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
  static const VerificationMeta _lastSyncErrorMeta = const VerificationMeta(
    'lastSyncError',
  );
  @override
  late final GeneratedColumn<String> lastSyncError = GeneratedColumn<String>(
    'last_sync_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    syncStatus,
    lastSyncError,
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
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('last_sync_error')) {
      context.handle(
        _lastSyncErrorMeta,
        lastSyncError.isAcceptableOrUnknown(
          data['last_sync_error']!,
          _lastSyncErrorMeta,
        ),
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
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      lastSyncError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_sync_error'],
      ),
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
  final String syncStatus;
  final String? lastSyncError;
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
    required this.syncStatus,
    this.lastSyncError,
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
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || lastSyncError != null) {
      map['last_sync_error'] = Variable<String>(lastSyncError);
    }
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
      syncStatus: Value(syncStatus),
      lastSyncError: lastSyncError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncError),
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
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      lastSyncError: serializer.fromJson<String?>(json['lastSyncError']),
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
      'syncStatus': serializer.toJson<String>(syncStatus),
      'lastSyncError': serializer.toJson<String?>(lastSyncError),
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
    String? syncStatus,
    Value<String?> lastSyncError = const Value.absent(),
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
    syncStatus: syncStatus ?? this.syncStatus,
    lastSyncError: lastSyncError.present
        ? lastSyncError.value
        : this.lastSyncError,
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
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      lastSyncError: data.lastSyncError.present
          ? data.lastSyncError.value
          : this.lastSyncError,
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
          ..write('syncStatus: $syncStatus, ')
          ..write('lastSyncError: $lastSyncError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
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
    syncStatus,
    lastSyncError,
  );
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
          other.syncStatus == this.syncStatus &&
          other.lastSyncError == this.lastSyncError);
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
  final Value<String> syncStatus;
  final Value<String?> lastSyncError;
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
    this.syncStatus = const Value.absent(),
    this.lastSyncError = const Value.absent(),
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
    this.syncStatus = const Value.absent(),
    this.lastSyncError = const Value.absent(),
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
    Expression<String>? syncStatus,
    Expression<String>? lastSyncError,
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
      if (syncStatus != null) 'sync_status': syncStatus,
      if (lastSyncError != null) 'last_sync_error': lastSyncError,
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
    Value<String>? syncStatus,
    Value<String?>? lastSyncError,
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
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncError: lastSyncError ?? this.lastSyncError,
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
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (lastSyncError.present) {
      map['last_sync_error'] = Variable<String>(lastSyncError.value);
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
          ..write('syncStatus: $syncStatus, ')
          ..write('lastSyncError: $lastSyncError, ')
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
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localOutbox,
    localLectures,
    localLectureAssets,
    localUploadJobs,
  ];
}

typedef $$LocalOutboxTableCreateCompanionBuilder =
    LocalOutboxCompanion Function({
      Value<int> id,
      required String entityType,
      required String entityId,
      required String op,
      required String payloadJson,
      Value<DateTime> enqueuedAt,
    });
typedef $$LocalOutboxTableUpdateCompanionBuilder =
    LocalOutboxCompanion Function({
      Value<int> id,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> op,
      Value<String> payloadJson,
      Value<DateTime> enqueuedAt,
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
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> enqueuedAt = const Value.absent(),
              }) => LocalOutboxCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                op: op,
                payloadJson: payloadJson,
                enqueuedAt: enqueuedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entityType,
                required String entityId,
                required String op,
                required String payloadJson,
                Value<DateTime> enqueuedAt = const Value.absent(),
              }) => LocalOutboxCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                op: op,
                payloadJson: payloadJson,
                enqueuedAt: enqueuedAt,
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
      Value<String> syncStatus,
      Value<String?> lastSyncError,
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
      Value<String> syncStatus,
      Value<String?> lastSyncError,
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

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
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

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
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

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSyncError => $composableBuilder(
    column: $table.lastSyncError,
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
                Value<String> syncStatus = const Value.absent(),
                Value<String?> lastSyncError = const Value.absent(),
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
                syncStatus: syncStatus,
                lastSyncError: lastSyncError,
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
                Value<String> syncStatus = const Value.absent(),
                Value<String?> lastSyncError = const Value.absent(),
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
                syncStatus: syncStatus,
                lastSyncError: lastSyncError,
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
}
