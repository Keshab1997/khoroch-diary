// Web-only ledger opener. This file is selected (via a conditional import in
// `main.dart`) only when `dart.library.js_interop` is present — i.e. the default
// Flutter JS web build. It must never be compiled into the native (mobile /
// desktop) build, which uses `local_ledger.dart`'s `LocalLedger.device()`
// instead.
import 'package:drift/wasm.dart';

import 'local_ledger.dart';

/// Opens the local ledger on the web using a WASM build of SQLite, persisting
/// data in the browser (IndexedDB or OPFS, chosen by drift). This replaces the
/// old in-memory preview so the web app keeps a real, persistent local ledger
/// that behaves like the native one.
///
/// The two files referenced here (`sqlite3.wasm` and `drift_worker.js`) are
/// copied into the `web/` folder and shipped with the web build.
Future<LocalLedger> openWebLedger() async {
  final WasmDatabaseResult result = await WasmDatabase.open(
    // Kept from the pre-rename build: IndexedDB is keyed by this name, so
    // changing it would orphan the ledger already saved in the browser.
    databaseName: 'khatabook',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return LocalLedger(result.resolvedExecutor.executor);
}
