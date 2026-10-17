import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_encounter/models/dot_avatar.dart';
import 'package:ble_encounter/models/piece_data.dart';
import 'package:ble_encounter/models/own_profile.dart';
import 'package:ble_encounter/models/encounter_record.dart';
import 'package:ble_encounter/services/profile_storage.dart';
import 'package:ble_encounter/services/piece_storage.dart';
import 'package:ble_encounter/providers/puzzle_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'art, revealed history and pieces survive storage reload and provider recreation',
      () async {
    SharedPreferences.setMockInitialValues({});
    final at = DateTime(2026, 10, 1, 10);
    final pixels = List.generate(256, (i) => i % 16);
    await ProfileStorage()
        .saveOwnProfile(const OwnProfile(name: 'そら', colorIndex: 2));
    await ProfileStorage().saveEncounters([
      EncounterRecord(
          peerId: 'peer',
          name: '山田',
          colorIndex: 2,
          firstMet: at,
          lastMet: at,
          meetCount: 2,
          rssi: 0,
          isRevealed: true,
          peerPixels: pixels)
    ]);
    await DotAvatarStorage.save(DotAvatar(pixels: pixels));
    await OwnPieceStorage.save(PieceData(pixels: pixels));
    await PuzzlePieceStorage.save([
      PuzzlePiece(
          ownerId: 'peer',
          ownerName: '山田',
          ownerColorIndex: 2,
          piece: PieceData(pixels: pixels),
          firstMetAt: at,
          lastMetAt: at,
          meetCount: 2,
          isRevealed: true)
    ]);
    for (var i = 0; i < 2; i++) {
      final container = ProviderContainer();
      container.read(puzzleProvider);
      await container.read(puzzleProvider.notifier).refresh();
      final piece = container.read(puzzleProvider).pieces.single;
      expect(piece.piece.pixels, pixels);
      expect(piece.isRevealed, isTrue);
      container.dispose();
    }
    expect((await DotAvatarStorage.load())!.pixels, pixels);
    expect((await OwnPieceStorage.load())!.pixels, pixels);
    expect((await ProfileStorage().loadOwnProfile())!.name, 'そら');
    expect((await ProfileStorage().loadEncounters()).single.peerPixels, pixels);
  });
}
