import '../entities/ring_alert_preferences.dart';

abstract class RingAlertPreferencesRepository {
  Future<RingAlertPreferences> getPreferences(String uid);

  Future<void> savePreferences(String uid, RingAlertPreferences preferences);
}
