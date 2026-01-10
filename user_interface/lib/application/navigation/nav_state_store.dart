import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in main()');
});

class NavStateStore {
  NavStateStore(this.prefs);
  final SharedPreferences prefs;

  static const _kLastNotesLocation = 'last_notes_location';

  String? get lastNotesLocation => prefs.getString(_kLastNotesLocation);

  Future<void> setLastNotesLocation(String location) async {
    await prefs.setString(_kLastNotesLocation, location);
  }

  static const _kLastFolderSyncAt = 'last_folder_sync_at_ms';

  int? get lastFolderSyncAtMs => prefs.getInt(_kLastFolderSyncAt);

  Future<void> setLastFolderSyncAt(DateTime dtUtc) async {
    await prefs.setInt(_kLastFolderSyncAt, dtUtc.millisecondsSinceEpoch);
  }

  DateTime? get lastFolderSyncAt {
    final ms = lastFolderSyncAtMs;
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}

final navStateStoreProvider = Provider<NavStateStore>((ref) {
  return NavStateStore(ref.watch(sharedPrefsProvider));
});
