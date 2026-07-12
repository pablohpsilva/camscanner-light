// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DocumentsTable extends Documents
    with TableInfo<$DocumentsTable, Document> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
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
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isIdCardMeta = const VerificationMeta(
    'isIdCard',
  );
  @override
  late final GeneratedColumn<bool> isIdCard = GeneratedColumn<bool>(
    'is_id_card',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_id_card" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    createdAt,
    modifiedAt,
    isIdCard,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<Document> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('is_id_card')) {
      context.handle(
        _isIdCardMeta,
        isIdCard.isAcceptableOrUnknown(data['is_id_card']!, _isIdCardMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Document map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Document(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      isIdCard: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_id_card'],
      )!,
    );
  }

  @override
  $DocumentsTable createAlias(String alias) {
    return $DocumentsTable(attachedDatabase, alias);
  }
}

class Document extends DataClass implements Insertable<Document> {
  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// True when this document is an ID card (front + back). Only its PDF export
  /// layout differs (single page, both images centered). Default false.
  final bool isIdCard;
  const Document({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    required this.isIdCard,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    map['is_id_card'] = Variable<bool>(isIdCard);
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
      isIdCard: Value(isIdCard),
    );
  }

  factory Document.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Document(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      isIdCard: serializer.fromJson<bool>(json['isIdCard']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'isIdCard': serializer.toJson<bool>(isIdCard),
    };
  }

  Document copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isIdCard,
  }) => Document(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    isIdCard: isIdCard ?? this.isIdCard,
  );
  Document copyWithCompanion(DocumentsCompanion data) {
    return Document(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      isIdCard: data.isIdCard.present ? data.isIdCard.value : this.isIdCard,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Document(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('isIdCard: $isIdCard')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, modifiedAt, isIdCard);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Document &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.isIdCard == this.isIdCard);
}

class DocumentsCompanion extends UpdateCompanion<Document> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<bool> isIdCard;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.isIdCard = const Value.absent(),
  });
  DocumentsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required DateTime createdAt,
    required DateTime modifiedAt,
    this.isIdCard = const Value.absent(),
  }) : name = Value(name),
       createdAt = Value(createdAt),
       modifiedAt = Value(modifiedAt);
  static Insertable<Document> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<bool>? isIdCard,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (isIdCard != null) 'is_id_card': isIdCard,
    });
  }

  DocumentsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<DateTime>? modifiedAt,
    Value<bool>? isIdCard,
  }) {
    return DocumentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isIdCard: isIdCard ?? this.isIdCard,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (isIdCard.present) {
      map['is_id_card'] = Variable<bool>(isIdCard.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('isIdCard: $isIdCard')
          ..write(')'))
        .toString();
  }
}

class $PagesTable extends Pages with TableInfo<$PagesTable, Page> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PagesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<int> documentId = GeneratedColumn<int>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES documents (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativeImagePathMeta = const VerificationMeta(
    'relativeImagePath',
  );
  @override
  late final GeneratedColumn<String> relativeImagePath =
      GeneratedColumn<String>(
        'relative_image_path',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _cornersMeta = const VerificationMeta(
    'corners',
  );
  @override
  late final GeneratedColumn<String> corners = GeneratedColumn<String>(
    'corners',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _flatRelativePathMeta = const VerificationMeta(
    'flatRelativePath',
  );
  @override
  late final GeneratedColumn<String> flatRelativePath = GeneratedColumn<String>(
    'flat_relative_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rotationQuarterTurnsMeta =
      const VerificationMeta('rotationQuarterTurns');
  @override
  late final GeneratedColumn<int> rotationQuarterTurns = GeneratedColumn<int>(
    'rotation_quarter_turns',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ocrTextMeta = const VerificationMeta(
    'ocrText',
  );
  @override
  late final GeneratedColumn<String> ocrText = GeneratedColumn<String>(
    'ocr_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ocrBoxesMeta = const VerificationMeta(
    'ocrBoxes',
  );
  @override
  late final GeneratedColumn<String> ocrBoxes = GeneratedColumn<String>(
    'ocr_boxes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    documentId,
    position,
    relativeImagePath,
    corners,
    flatRelativePath,
    rotationQuarterTurns,
    ocrText,
    ocrBoxes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Page> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('relative_image_path')) {
      context.handle(
        _relativeImagePathMeta,
        relativeImagePath.isAcceptableOrUnknown(
          data['relative_image_path']!,
          _relativeImagePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativeImagePathMeta);
    }
    if (data.containsKey('corners')) {
      context.handle(
        _cornersMeta,
        corners.isAcceptableOrUnknown(data['corners']!, _cornersMeta),
      );
    }
    if (data.containsKey('flat_relative_path')) {
      context.handle(
        _flatRelativePathMeta,
        flatRelativePath.isAcceptableOrUnknown(
          data['flat_relative_path']!,
          _flatRelativePathMeta,
        ),
      );
    }
    if (data.containsKey('rotation_quarter_turns')) {
      context.handle(
        _rotationQuarterTurnsMeta,
        rotationQuarterTurns.isAcceptableOrUnknown(
          data['rotation_quarter_turns']!,
          _rotationQuarterTurnsMeta,
        ),
      );
    }
    if (data.containsKey('ocr_text')) {
      context.handle(
        _ocrTextMeta,
        ocrText.isAcceptableOrUnknown(data['ocr_text']!, _ocrTextMeta),
      );
    }
    if (data.containsKey('ocr_boxes')) {
      context.handle(
        _ocrBoxesMeta,
        ocrBoxes.isAcceptableOrUnknown(data['ocr_boxes']!, _ocrBoxesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Page map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Page(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      relativeImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_image_path'],
      )!,
      corners: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}corners'],
      ),
      flatRelativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}flat_relative_path'],
      ),
      rotationQuarterTurns: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rotation_quarter_turns'],
      )!,
      ocrText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_text'],
      ),
      ocrBoxes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_boxes'],
      ),
    );
  }

  @override
  $PagesTable createAlias(String alias) {
    return $PagesTable(attachedDatabase, alias);
  }
}

class Page extends DataClass implements Insertable<Page> {
  final int id;
  final int documentId;
  final int position;
  final String relativeImagePath;

  /// Normalized crop quad (E1) as "x0,y0,...,x3,y3"; null = uncropped (full
  /// frame). See CropCorners.
  final String? corners;

  /// Perspective-flattened image path (E2), relative to the app documents dir;
  /// null until the flatten step has been run for this page.
  final String? flatRelativePath;

  /// Number of 90° clockwise quarter-turns applied to the DISPLAY image (0..3).
  /// Rotation is metadata re-applied during flat regeneration — never baked
  /// destructively into the base image. See DriftDocumentRepository._writeFlat.
  final int rotationQuarterTurns;

  /// Recognized OCR text for this page (O1); null until OCR has run.
  final String? ocrText;

  /// JSON-encoded OCR word boxes (OcrResult.encodeBoxes); null until OCR has run.
  final String? ocrBoxes;
  const Page({
    required this.id,
    required this.documentId,
    required this.position,
    required this.relativeImagePath,
    this.corners,
    this.flatRelativePath,
    required this.rotationQuarterTurns,
    this.ocrText,
    this.ocrBoxes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['document_id'] = Variable<int>(documentId);
    map['position'] = Variable<int>(position);
    map['relative_image_path'] = Variable<String>(relativeImagePath);
    if (!nullToAbsent || corners != null) {
      map['corners'] = Variable<String>(corners);
    }
    if (!nullToAbsent || flatRelativePath != null) {
      map['flat_relative_path'] = Variable<String>(flatRelativePath);
    }
    map['rotation_quarter_turns'] = Variable<int>(rotationQuarterTurns);
    if (!nullToAbsent || ocrText != null) {
      map['ocr_text'] = Variable<String>(ocrText);
    }
    if (!nullToAbsent || ocrBoxes != null) {
      map['ocr_boxes'] = Variable<String>(ocrBoxes);
    }
    return map;
  }

  PagesCompanion toCompanion(bool nullToAbsent) {
    return PagesCompanion(
      id: Value(id),
      documentId: Value(documentId),
      position: Value(position),
      relativeImagePath: Value(relativeImagePath),
      corners: corners == null && nullToAbsent
          ? const Value.absent()
          : Value(corners),
      flatRelativePath: flatRelativePath == null && nullToAbsent
          ? const Value.absent()
          : Value(flatRelativePath),
      rotationQuarterTurns: Value(rotationQuarterTurns),
      ocrText: ocrText == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrText),
      ocrBoxes: ocrBoxes == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrBoxes),
    );
  }

  factory Page.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Page(
      id: serializer.fromJson<int>(json['id']),
      documentId: serializer.fromJson<int>(json['documentId']),
      position: serializer.fromJson<int>(json['position']),
      relativeImagePath: serializer.fromJson<String>(json['relativeImagePath']),
      corners: serializer.fromJson<String?>(json['corners']),
      flatRelativePath: serializer.fromJson<String?>(json['flatRelativePath']),
      rotationQuarterTurns: serializer.fromJson<int>(
        json['rotationQuarterTurns'],
      ),
      ocrText: serializer.fromJson<String?>(json['ocrText']),
      ocrBoxes: serializer.fromJson<String?>(json['ocrBoxes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'documentId': serializer.toJson<int>(documentId),
      'position': serializer.toJson<int>(position),
      'relativeImagePath': serializer.toJson<String>(relativeImagePath),
      'corners': serializer.toJson<String?>(corners),
      'flatRelativePath': serializer.toJson<String?>(flatRelativePath),
      'rotationQuarterTurns': serializer.toJson<int>(rotationQuarterTurns),
      'ocrText': serializer.toJson<String?>(ocrText),
      'ocrBoxes': serializer.toJson<String?>(ocrBoxes),
    };
  }

  Page copyWith({
    int? id,
    int? documentId,
    int? position,
    String? relativeImagePath,
    Value<String?> corners = const Value.absent(),
    Value<String?> flatRelativePath = const Value.absent(),
    int? rotationQuarterTurns,
    Value<String?> ocrText = const Value.absent(),
    Value<String?> ocrBoxes = const Value.absent(),
  }) => Page(
    id: id ?? this.id,
    documentId: documentId ?? this.documentId,
    position: position ?? this.position,
    relativeImagePath: relativeImagePath ?? this.relativeImagePath,
    corners: corners.present ? corners.value : this.corners,
    flatRelativePath: flatRelativePath.present
        ? flatRelativePath.value
        : this.flatRelativePath,
    rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
    ocrText: ocrText.present ? ocrText.value : this.ocrText,
    ocrBoxes: ocrBoxes.present ? ocrBoxes.value : this.ocrBoxes,
  );
  Page copyWithCompanion(PagesCompanion data) {
    return Page(
      id: data.id.present ? data.id.value : this.id,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      position: data.position.present ? data.position.value : this.position,
      relativeImagePath: data.relativeImagePath.present
          ? data.relativeImagePath.value
          : this.relativeImagePath,
      corners: data.corners.present ? data.corners.value : this.corners,
      flatRelativePath: data.flatRelativePath.present
          ? data.flatRelativePath.value
          : this.flatRelativePath,
      rotationQuarterTurns: data.rotationQuarterTurns.present
          ? data.rotationQuarterTurns.value
          : this.rotationQuarterTurns,
      ocrText: data.ocrText.present ? data.ocrText.value : this.ocrText,
      ocrBoxes: data.ocrBoxes.present ? data.ocrBoxes.value : this.ocrBoxes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Page(')
          ..write('id: $id, ')
          ..write('documentId: $documentId, ')
          ..write('position: $position, ')
          ..write('relativeImagePath: $relativeImagePath, ')
          ..write('corners: $corners, ')
          ..write('flatRelativePath: $flatRelativePath, ')
          ..write('rotationQuarterTurns: $rotationQuarterTurns, ')
          ..write('ocrText: $ocrText, ')
          ..write('ocrBoxes: $ocrBoxes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    documentId,
    position,
    relativeImagePath,
    corners,
    flatRelativePath,
    rotationQuarterTurns,
    ocrText,
    ocrBoxes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Page &&
          other.id == this.id &&
          other.documentId == this.documentId &&
          other.position == this.position &&
          other.relativeImagePath == this.relativeImagePath &&
          other.corners == this.corners &&
          other.flatRelativePath == this.flatRelativePath &&
          other.rotationQuarterTurns == this.rotationQuarterTurns &&
          other.ocrText == this.ocrText &&
          other.ocrBoxes == this.ocrBoxes);
}

class PagesCompanion extends UpdateCompanion<Page> {
  final Value<int> id;
  final Value<int> documentId;
  final Value<int> position;
  final Value<String> relativeImagePath;
  final Value<String?> corners;
  final Value<String?> flatRelativePath;
  final Value<int> rotationQuarterTurns;
  final Value<String?> ocrText;
  final Value<String?> ocrBoxes;
  const PagesCompanion({
    this.id = const Value.absent(),
    this.documentId = const Value.absent(),
    this.position = const Value.absent(),
    this.relativeImagePath = const Value.absent(),
    this.corners = const Value.absent(),
    this.flatRelativePath = const Value.absent(),
    this.rotationQuarterTurns = const Value.absent(),
    this.ocrText = const Value.absent(),
    this.ocrBoxes = const Value.absent(),
  });
  PagesCompanion.insert({
    this.id = const Value.absent(),
    required int documentId,
    required int position,
    required String relativeImagePath,
    this.corners = const Value.absent(),
    this.flatRelativePath = const Value.absent(),
    this.rotationQuarterTurns = const Value.absent(),
    this.ocrText = const Value.absent(),
    this.ocrBoxes = const Value.absent(),
  }) : documentId = Value(documentId),
       position = Value(position),
       relativeImagePath = Value(relativeImagePath);
  static Insertable<Page> custom({
    Expression<int>? id,
    Expression<int>? documentId,
    Expression<int>? position,
    Expression<String>? relativeImagePath,
    Expression<String>? corners,
    Expression<String>? flatRelativePath,
    Expression<int>? rotationQuarterTurns,
    Expression<String>? ocrText,
    Expression<String>? ocrBoxes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (documentId != null) 'document_id': documentId,
      if (position != null) 'position': position,
      if (relativeImagePath != null) 'relative_image_path': relativeImagePath,
      if (corners != null) 'corners': corners,
      if (flatRelativePath != null) 'flat_relative_path': flatRelativePath,
      if (rotationQuarterTurns != null)
        'rotation_quarter_turns': rotationQuarterTurns,
      if (ocrText != null) 'ocr_text': ocrText,
      if (ocrBoxes != null) 'ocr_boxes': ocrBoxes,
    });
  }

  PagesCompanion copyWith({
    Value<int>? id,
    Value<int>? documentId,
    Value<int>? position,
    Value<String>? relativeImagePath,
    Value<String?>? corners,
    Value<String?>? flatRelativePath,
    Value<int>? rotationQuarterTurns,
    Value<String?>? ocrText,
    Value<String?>? ocrBoxes,
  }) {
    return PagesCompanion(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      position: position ?? this.position,
      relativeImagePath: relativeImagePath ?? this.relativeImagePath,
      corners: corners ?? this.corners,
      flatRelativePath: flatRelativePath ?? this.flatRelativePath,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      ocrText: ocrText ?? this.ocrText,
      ocrBoxes: ocrBoxes ?? this.ocrBoxes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<int>(documentId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (relativeImagePath.present) {
      map['relative_image_path'] = Variable<String>(relativeImagePath.value);
    }
    if (corners.present) {
      map['corners'] = Variable<String>(corners.value);
    }
    if (flatRelativePath.present) {
      map['flat_relative_path'] = Variable<String>(flatRelativePath.value);
    }
    if (rotationQuarterTurns.present) {
      map['rotation_quarter_turns'] = Variable<int>(rotationQuarterTurns.value);
    }
    if (ocrText.present) {
      map['ocr_text'] = Variable<String>(ocrText.value);
    }
    if (ocrBoxes.present) {
      map['ocr_boxes'] = Variable<String>(ocrBoxes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PagesCompanion(')
          ..write('id: $id, ')
          ..write('documentId: $documentId, ')
          ..write('position: $position, ')
          ..write('relativeImagePath: $relativeImagePath, ')
          ..write('corners: $corners, ')
          ..write('flatRelativePath: $flatRelativePath, ')
          ..write('rotationQuarterTurns: $rotationQuarterTurns, ')
          ..write('ocrText: $ocrText, ')
          ..write('ocrBoxes: $ocrBoxes')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $PagesTable pages = $PagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [documents, pages];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('pages', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$DocumentsTableCreateCompanionBuilder =
    DocumentsCompanion Function({
      Value<int> id,
      required String name,
      required DateTime createdAt,
      required DateTime modifiedAt,
      Value<bool> isIdCard,
    });
typedef $$DocumentsTableUpdateCompanionBuilder =
    DocumentsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<DateTime> modifiedAt,
      Value<bool> isIdCard,
    });

final class $$DocumentsTableReferences
    extends BaseReferences<_$AppDatabase, $DocumentsTable, Document> {
  $$DocumentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PagesTable, List<Page>> _pagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.pages,
    aliasName: 'documents__id__pages__document_id',
  );

  $$PagesTableProcessedTableManager get pagesRefs {
    final manager = $$PagesTableTableManager(
      $_db,
      $_db.pages,
    ).filter((f) => f.documentId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_pagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isIdCard => $composableBuilder(
    column: $table.isIdCard,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> pagesRefs(
    Expression<bool> Function($$PagesTableFilterComposer f) f,
  ) {
    final $$PagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pages,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PagesTableFilterComposer(
            $db: $db,
            $table: $db.pages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isIdCard => $composableBuilder(
    column: $table.isIdCard,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isIdCard =>
      $composableBuilder(column: $table.isIdCard, builder: (column) => column);

  Expression<T> pagesRefs<T extends Object>(
    Expression<T> Function($$PagesTableAnnotationComposer a) f,
  ) {
    final $$PagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pages,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PagesTableAnnotationComposer(
            $db: $db,
            $table: $db.pages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DocumentsTable,
          Document,
          $$DocumentsTableFilterComposer,
          $$DocumentsTableOrderingComposer,
          $$DocumentsTableAnnotationComposer,
          $$DocumentsTableCreateCompanionBuilder,
          $$DocumentsTableUpdateCompanionBuilder,
          (Document, $$DocumentsTableReferences),
          Document,
          PrefetchHooks Function({bool pagesRefs})
        > {
  $$DocumentsTableTableManager(_$AppDatabase db, $DocumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<bool> isIdCard = const Value.absent(),
              }) => DocumentsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                isIdCard: isIdCard,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required DateTime createdAt,
                required DateTime modifiedAt,
                Value<bool> isIdCard = const Value.absent(),
              }) => DocumentsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                isIdCard: isIdCard,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DocumentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({pagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (pagesRefs) db.pages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (pagesRefs)
                    await $_getPrefetchedData<Document, $DocumentsTable, Page>(
                      currentTable: table,
                      referencedTable: $$DocumentsTableReferences
                          ._pagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$DocumentsTableReferences(db, table, p0).pagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.documentId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$DocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DocumentsTable,
      Document,
      $$DocumentsTableFilterComposer,
      $$DocumentsTableOrderingComposer,
      $$DocumentsTableAnnotationComposer,
      $$DocumentsTableCreateCompanionBuilder,
      $$DocumentsTableUpdateCompanionBuilder,
      (Document, $$DocumentsTableReferences),
      Document,
      PrefetchHooks Function({bool pagesRefs})
    >;
typedef $$PagesTableCreateCompanionBuilder =
    PagesCompanion Function({
      Value<int> id,
      required int documentId,
      required int position,
      required String relativeImagePath,
      Value<String?> corners,
      Value<String?> flatRelativePath,
      Value<int> rotationQuarterTurns,
      Value<String?> ocrText,
      Value<String?> ocrBoxes,
    });
typedef $$PagesTableUpdateCompanionBuilder =
    PagesCompanion Function({
      Value<int> id,
      Value<int> documentId,
      Value<int> position,
      Value<String> relativeImagePath,
      Value<String?> corners,
      Value<String?> flatRelativePath,
      Value<int> rotationQuarterTurns,
      Value<String?> ocrText,
      Value<String?> ocrBoxes,
    });

final class $$PagesTableReferences
    extends BaseReferences<_$AppDatabase, $PagesTable, Page> {
  $$PagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DocumentsTable _documentIdTable(_$AppDatabase db) =>
      db.documents.createAlias('pages__document_id__documents__id');

  $$DocumentsTableProcessedTableManager get documentId {
    final $_column = $_itemColumn<int>('document_id')!;

    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_documentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PagesTableFilterComposer extends Composer<_$AppDatabase, $PagesTable> {
  $$PagesTableFilterComposer({
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

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativeImagePath => $composableBuilder(
    column: $table.relativeImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get corners => $composableBuilder(
    column: $table.corners,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get flatRelativePath => $composableBuilder(
    column: $table.flatRelativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rotationQuarterTurns => $composableBuilder(
    column: $table.rotationQuarterTurns,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrBoxes => $composableBuilder(
    column: $table.ocrBoxes,
    builder: (column) => ColumnFilters(column),
  );

  $$DocumentsTableFilterComposer get documentId {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PagesTableOrderingComposer
    extends Composer<_$AppDatabase, $PagesTable> {
  $$PagesTableOrderingComposer({
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

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativeImagePath => $composableBuilder(
    column: $table.relativeImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get corners => $composableBuilder(
    column: $table.corners,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get flatRelativePath => $composableBuilder(
    column: $table.flatRelativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rotationQuarterTurns => $composableBuilder(
    column: $table.rotationQuarterTurns,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrText => $composableBuilder(
    column: $table.ocrText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrBoxes => $composableBuilder(
    column: $table.ocrBoxes,
    builder: (column) => ColumnOrderings(column),
  );

  $$DocumentsTableOrderingComposer get documentId {
    final $$DocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PagesTable> {
  $$PagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get relativeImagePath => $composableBuilder(
    column: $table.relativeImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get corners =>
      $composableBuilder(column: $table.corners, builder: (column) => column);

  GeneratedColumn<String> get flatRelativePath => $composableBuilder(
    column: $table.flatRelativePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rotationQuarterTurns => $composableBuilder(
    column: $table.rotationQuarterTurns,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ocrText =>
      $composableBuilder(column: $table.ocrText, builder: (column) => column);

  GeneratedColumn<String> get ocrBoxes =>
      $composableBuilder(column: $table.ocrBoxes, builder: (column) => column);

  $$DocumentsTableAnnotationComposer get documentId {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PagesTable,
          Page,
          $$PagesTableFilterComposer,
          $$PagesTableOrderingComposer,
          $$PagesTableAnnotationComposer,
          $$PagesTableCreateCompanionBuilder,
          $$PagesTableUpdateCompanionBuilder,
          (Page, $$PagesTableReferences),
          Page,
          PrefetchHooks Function({bool documentId})
        > {
  $$PagesTableTableManager(_$AppDatabase db, $PagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> documentId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> relativeImagePath = const Value.absent(),
                Value<String?> corners = const Value.absent(),
                Value<String?> flatRelativePath = const Value.absent(),
                Value<int> rotationQuarterTurns = const Value.absent(),
                Value<String?> ocrText = const Value.absent(),
                Value<String?> ocrBoxes = const Value.absent(),
              }) => PagesCompanion(
                id: id,
                documentId: documentId,
                position: position,
                relativeImagePath: relativeImagePath,
                corners: corners,
                flatRelativePath: flatRelativePath,
                rotationQuarterTurns: rotationQuarterTurns,
                ocrText: ocrText,
                ocrBoxes: ocrBoxes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int documentId,
                required int position,
                required String relativeImagePath,
                Value<String?> corners = const Value.absent(),
                Value<String?> flatRelativePath = const Value.absent(),
                Value<int> rotationQuarterTurns = const Value.absent(),
                Value<String?> ocrText = const Value.absent(),
                Value<String?> ocrBoxes = const Value.absent(),
              }) => PagesCompanion.insert(
                id: id,
                documentId: documentId,
                position: position,
                relativeImagePath: relativeImagePath,
                corners: corners,
                flatRelativePath: flatRelativePath,
                rotationQuarterTurns: rotationQuarterTurns,
                ocrText: ocrText,
                ocrBoxes: ocrBoxes,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PagesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({documentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (documentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.documentId,
                                referencedTable: $$PagesTableReferences
                                    ._documentIdTable(db),
                                referencedColumn: $$PagesTableReferences
                                    ._documentIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PagesTable,
      Page,
      $$PagesTableFilterComposer,
      $$PagesTableOrderingComposer,
      $$PagesTableAnnotationComposer,
      $$PagesTableCreateCompanionBuilder,
      $$PagesTableUpdateCompanionBuilder,
      (Page, $$PagesTableReferences),
      Page,
      PrefetchHooks Function({bool documentId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$PagesTableTableManager get pages =>
      $$PagesTableTableManager(_db, _db.pages);
}
