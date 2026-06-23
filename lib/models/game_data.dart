import 'dart:convert';
import 'encounter_record.dart';
import '../ui/encounter_helpers.dart';

// ─── ピースパズル ─────────────────────────────────────────────────────────────

class PieceState {
  static const total = 25;
  final List<bool> collected; // index 0-24
  final List<bool> isGold;
  final Set<String> earnedFrom; // peerIds already awarded today

  PieceState({
    List<bool>? collected,
    List<bool>? isGold,
    Set<String>? earnedFrom,
  })  : collected = collected ?? List.filled(total, false),
        isGold = isGold ?? List.filled(total, false),
        earnedFrom = earnedFrom ?? {};

  int get count => collected.where((c) => c).length;
  bool get isComplete => count >= total;

  PieceState addPiece(String peerId, bool gold) {
    if (earnedFrom.contains(peerId)) return this;
    // 決定論的スロット割り当て: peerId hashベース
    final hash = peerId.hashCode.abs();
    int slot = -1;
    for (int i = 0; i < total; i++) {
      final s = (hash + i) % total;
      if (!collected[s]) { slot = s; break; }
    }
    if (slot == -1) return this; // all filled
    final nc = List<bool>.from(collected)..[slot] = true;
    final ng = List<bool>.from(isGold)..[slot] = gold;
    return PieceState(
      collected: nc, isGold: ng,
      earnedFrom: {...earnedFrom, peerId},
    );
  }

  Map<String, dynamic> toJson() => {
    'c': collected.map((b) => b ? 1 : 0).toList(),
    'g': isGold.map((b) => b ? 1 : 0).toList(),
    'f': earnedFrom.toList(),
  };

  factory PieceState.fromJson(Map<String, dynamic> j) => PieceState(
    collected: (j['c'] as List).map((v) => v == 1).toList(),
    isGold: (j['g'] as List).map((v) => v == 1).toList(),
    earnedFrom: Set<String>.from(j['f'] as List),
  );
}

// ─── タワーRPG ────────────────────────────────────────────────────────────────

class TowerHero {
  final String name;
  final int atk;
  final int maxHp;
  final String magicName;
  final String magicType; // 'single' | 'heal' | 'all' | 'oneshot'
  final CardRarity rarity;

  const TowerHero({
    required this.name, required this.atk, required this.maxHp,
    required this.magicName, required this.magicType, required this.rarity,
  });

  factory TowerHero.fromEncounter(EncounterRecord e) {
    final r = cardRarityOf(e.meetCount);
    return switch (r) {
      CardRarity.common   => TowerHero(name: e.name, atk: 10, maxHp: 20, magicName: 'ファイア', magicType: 'single', rarity: r),
      CardRarity.craft    => TowerHero(name: e.name, atk: 15, maxHp: 35, magicName: 'ヒール',   magicType: 'heal',   rarity: r),
      CardRarity.gradient => TowerHero(name: e.name, atk: 25, maxHp: 60, magicName: 'サンダー', magicType: 'all',    rarity: r),
      CardRarity.hologram => TowerHero(name: e.name, atk: 60, maxHp: 120,magicName: '必殺技',   magicType: 'oneshot',rarity: r),
    };
  }
}

class TowerFloorDef {
  final int floor;
  final String name;
  final int hp;
  final int atk;

  const TowerFloorDef({required this.floor, required this.name, required this.hp, required this.atk});

  static TowerFloorDef forFloor(int f) {
    const names = [
      'スライム', 'コウモリ', 'ゴブリン', 'オーク', 'ウィザード',
      'ドラゴン', '鎧の騎士', '魔将軍', '幽霊兵', 'ダークエルフ',
      '魔龍', '邪神の使い', '闇の皇帝', '千の眼', '最終兵器',
    ];
    final idx = ((f - 1) % names.length).clamp(0, names.length - 1);
    return TowerFloorDef(
      floor: f,
      name: names[idx],
      hp: 30 + f * 12,
      atk: 4 + f * 2,
    );
  }
}

// ─── 水族館 ───────────────────────────────────────────────────────────────────

class FishDef {
  final String emoji;
  final String name;
  final String region; // 由来地域ラベル
  const FishDef(this.emoji, this.name, this.region);
}

const _fishTable = [
  FishDef('🐟', 'アジ',     '関東'),
  FishDef('🐡', 'フグ',     '九州'),
  FishDef('🐠', 'クマノミ', '沖縄'),
  FishDef('🐙', 'タコ',     '近畿'),
  FishDef('🦑', 'イカ',     '東北'),
  FishDef('🦀', 'カニ',     '北海道'),
  FishDef('🦞', 'ロブスター','北海道'),
  FishDef('🐬', 'イルカ',   '四国'),
  FishDef('🦈', 'サメ',     '沖縄'),
  FishDef('🐳', 'クジラ',   '北海道'),
  FishDef('🦭', 'アザラシ', '北海道'),
  FishDef('🦐', 'エビ',     '近畿'),
  FishDef('🎣', 'タイ',     '四国'),
  FishDef('🐚', 'サザエ',   '九州'),
];

FishDef fishForPeer(String peerId, int hobbyCategory) {
  final idx = (peerId.hashCode.abs() + hobbyCategory * 3) % _fishTable.length;
  return _fishTable[idx];
}

class AquariumFish {
  final String peerId;
  final String emoji;
  final String name;
  final String region;
  final bool caught;
  final DateTime addedAt;

  const AquariumFish({
    required this.peerId, required this.emoji, required this.name,
    required this.region, this.caught = false, required this.addedAt,
  });

  AquariumFish copyWith({bool? caught}) => AquariumFish(
    peerId: peerId, emoji: emoji, name: name,
    region: region, caught: caught ?? this.caught, addedAt: addedAt,
  );

  Map<String, dynamic> toJson() => {
    'p': peerId, 'e': emoji, 'n': name, 'r': region,
    'c': caught, 't': addedAt.millisecondsSinceEpoch,
  };

  factory AquariumFish.fromJson(Map<String, dynamic> j) => AquariumFish(
    peerId: j['p'] as String, emoji: j['e'] as String,
    name: j['n'] as String, region: j['r'] as String,
    caught: j['c'] as bool? ?? false,
    addedAt: DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
  );

  static AquariumFish fromEncounter(EncounterRecord e) {
    final def = fishForPeer(e.peerId, e.template.hobbyCategory);
    return AquariumFish(
      peerId: e.peerId, emoji: def.emoji, name: def.name,
      region: def.region, addedAt: DateTime.now(),
    );
  }
}

// ─── 全ゲームデータ ───────────────────────────────────────────────────────────

class GameData {
  final PieceState puzzle;
  final int towerMaxFloor;
  final List<AquariumFish> aquariumHistory; // 全日分の釣り履歴

  const GameData({
    required this.puzzle,
    this.towerMaxFloor = 0,
    this.aquariumHistory = const [],
  });

  GameData copyWith({
    PieceState? puzzle,
    int? towerMaxFloor,
    List<AquariumFish>? aquariumHistory,
  }) => GameData(
    puzzle: puzzle ?? this.puzzle,
    towerMaxFloor: towerMaxFloor ?? this.towerMaxFloor,
    aquariumHistory: aquariumHistory ?? this.aquariumHistory,
  );

  Map<String, dynamic> toJson() => {
    'puzzle': puzzle.toJson(),
    'towerMax': towerMaxFloor,
    'aquarium': aquariumHistory.map((f) => f.toJson()).toList(),
  };

  factory GameData.fromJson(Map<String, dynamic> j) => GameData(
    puzzle: j['puzzle'] != null
        ? PieceState.fromJson(j['puzzle'] as Map<String, dynamic>)
        : PieceState(),
    towerMaxFloor: j['towerMax'] as int? ?? 0,
    aquariumHistory: (j['aquarium'] as List? ?? [])
        .map((e) => AquariumFish.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  factory GameData.empty() => GameData(puzzle: PieceState());
}
