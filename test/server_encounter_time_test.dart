import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/core/peer_id.dart';
import 'package:ble_encounter/providers/ble_providers.dart';
import 'package:ble_encounter/services/profile_storage.dart';

class _HistoryApp extends AppNotifier {
  @override
  AppState build() => const AppState(isLoading: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'delayed resolution preserves capture time and stale polls never add meetings',
      () async {
    SharedPreferences.setMockInitialValues({});
    await PeerId.init();
    final container = ProviderContainer(
        overrides: [appProvider.overrideWith(_HistoryApp.new)]);
    addTearDown(container.dispose);
    final app = container.read(appProvider.notifier);
    final captured = DateTime(2026, 10, 1, 11, 59);
    Future<void> merge(DateTime at) => app.upsertFromServerProfile(
        peerId: 'peer', name: 'そら', colorIndex: 0, metAt: at);
    await merge(captured);
    expect(container.read(appProvider).encounters.single.lastMet, captured);
    expect(
        AppNotifier.gateTimeFor(
            container.read(appProvider).encounters.single.lastMet),
        DateTime(2026, 10, 1, 12));
    for (var i = 0; i < 5; i++) {
      await merge(captured);
    }
    expect(container.read(appProvider).encounters.single.meetCount, 1);
    final next = DateTime(2026, 10, 2, 10);
    await merge(next);
    await merge(captured);
    final restored = (await ProfileStorage().loadEncounters()).single;
    expect(restored.meetCount, 2);
    expect(restored.lastMet, next);
    expect(restored.firstMet, captured);
    app.dispose();
  });
}
