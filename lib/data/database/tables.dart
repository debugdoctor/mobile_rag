import 'package:drift/drift.dart';

class KnowledgeBases extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get embeddingModel => text().nullable()();
  TextColumn get chunkSeparators => text().nullable()();
  IntColumn get chunkSizeMin => integer().nullable()();
  IntColumn get chunkSizeMax => integer().nullable()();
  IntColumn get chunkOverlap => integer().nullable()();
  IntColumn get maxFileSizeMb => integer().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get knowledgeBaseId => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class DocumentChunks extends Table {
  TextColumn get id => text()();
  TextColumn get documentId => text()();
  IntColumn get chunkIndex => integer()();
  TextColumn get content => text()();
  TextColumn get createdAt => text()();
  TextColumn get embedding => text().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().nullable()();
  TextColumn get summary => text().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get createdAt => text()();
  TextColumn get metadata => text().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {key};
}
