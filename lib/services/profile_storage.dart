import 'package:shared_preferences/shared_preferences.dart';
import '../models/own_profile.dart';
import '../models/encounter_record.dart';

class ProfileStorage {
  static const _ownProfileKey = 'own_profile_v1';
  static const _encountersKey = 'encounters_v1';

  Future<OwnProfile?> loadOwnProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_ownProfileKey);
    if (json == null) return null;
    return OwnProfile.fromStorageJson(json);
  }

  Future<void> saveOwnProfile(OwnProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownProfileKey, profile.toStorageJson());
  }

  Future<List<EncounterRecord>> loadEncounters() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_encountersKey);
    if (json == null) return [];
    try {
      return EncounterRecord.decodeList(json);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveEncounters(List<EncounterRecord> encounters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_encountersKey, EncounterRecord.encodeList(encounters));
  }
}
