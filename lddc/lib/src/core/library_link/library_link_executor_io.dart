import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../storage/app_storage_paths_port.dart';

Future<QueryExecutor> createDefaultLibraryLinkExecutorImpl() async {
  final File dbFile = await AppStoragePathsRegistry.current
      .resolveLibraryLinkDatabaseFile();
  final Directory dbDir = dbFile.parent;
  await dbDir.create(recursive: true);
  return NativeDatabase.createInBackground(dbFile);
}
