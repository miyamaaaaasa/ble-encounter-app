import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/encounter_record.dart';
import '../../models/game_data.dart';
import '../../services/game_storage.dart';
import '../../ui/encounter_helpers.dart';

// ─── ② はじめましてタワーRPG ─────────────────────────────────────────────────

class TowerRpgScreen extends StatefulWidget {
  final List<EncounterRecord> todayRevealed;
  const TowerRpgScreen({super.key, required this.todayRevealed});

  @override
  State<TowerRpgScreen> createState() => _TowerRpgScreenState();
}

class _TowerState {
  final int floor;
  final int partyHp;
  final int partyMaxHp;
  final int enemyHp;
  final int enemyMaxHp;
  final String enemyName;
  final List<String> log;
  final bool won;
  final bool lost;

  const _TowerState({
    required this.floor, required this.partyHp, required this.partyMaxHp,
    required this.enemyHp, required this.enemyMaxHp, required this.enemyName,
    this.log = const [], this.won = false, this.lost = false,
  });
}

class _TowerRpgScreenState extends State<TowerRpgScreen> {
  late ValueNotifier<_TowerState?> _stateNotifier;
  late List<TowerHero> _party;
  int _maxFloor = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _stateNotifier = ValueNotifier(null);
    _party = widget.todayRevealed.map(TowerHero.fromEncounter).toList();
    _load();
  }

  @override
  void dispose() {
    _stateNotifier.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await GameStorage.load();
    if (!mounted) return;
    _maxFloor = data.towerMaxFloor;
    setState(() => _loading = false);
  }

  void _startBattle() {
    if (_party.isEmpty) return;
    final partyHp = _party.fold<int>(0, (s, h) => s + h.maxHp);
    final enemy   = TowerFloorDef.forFloor(1);
    _stateNotifier.value = _TowerState(
      floor: 1, partyHp: partyHp, partyMaxHp: partyHp,
      enemyHp: enemy.hp, enemyMaxHp: enemy.hp, enemyName: enemy.name,
      log: ['⚔️ 1階の ${enemy.name} に挑戦！'],
    );
  }

  void _attack() {
    final s = _stateNotifier.value;
    if (s == null || s.won || s.lost) return;

    final rng = math.Random();
    var newLog = List<String>.from(s.log);
    int partyHp = s.partyHp;
    int enemyHp = s.enemyHp;

    // ─── 勇者団の攻撃 ───────────────────────────────────────────
    int totalDmg = 0;
    String? magicUsed;
    bool healed = false;

    for (final hero in _party) {
      if (hero.magicType == 'oneshot' && rng.nextInt(100) < 10) {
        // 必殺技（10%発動）
        totalDmg += enemyHp; // 一撃必殺
        magicUsed = '✨${hero.name}の必殺技発動！';
      } else if (hero.magicType == 'heal' && partyHp < s.partyMaxHp * 0.5) {
        // 回復（HP50%以下で発動）
        final heal = (hero.maxHp * 0.5).round();
        partyHp = (partyHp + heal).clamp(0, s.partyMaxHp);
        healed = true;
        newLog.add('💚 ${hero.name}がヒール！（+$heal HP）');
      } else if (hero.magicType == 'all') {
        // 全体攻撃
        totalDmg += (hero.atk * 1.5).round();
      } else {
        totalDmg += hero.atk;
      }
    }

    if (magicUsed != null) {
      newLog.add(magicUsed);
      enemyHp = 0;
    } else {
      final variance = rng.nextInt(5) - 2;
      final dmg = (totalDmg + variance).clamp(1, 9999);
      enemyHp = (enemyHp - dmg).clamp(0, s.enemyMaxHp);
      if (!healed) newLog.add('⚔️ 勇者団の攻撃！ ${enemy_name(s)} に $dmg ダメージ！');
    }

    // ─── 敵の反撃 ───────────────────────────────────────────────
    if (enemyHp > 0) {
      final enemy  = TowerFloorDef.forFloor(s.floor);
      final eDmg   = (enemy.atk + rng.nextInt(4) - 2).clamp(1, 9999);
      partyHp = (partyHp - eDmg).clamp(0, s.partyMaxHp);
      newLog.add('💥 ${s.enemyName}の攻撃！ $eDmg ダメージ！');
    }

    // ログは最新5件
    if (newLog.length > 6) newLog = newLog.sublist(newLog.length - 6);

    // ─── 勝利 / 敗北判定 ────────────────────────────────────────
    if (enemyHp <= 0) {
      final nextFloor = s.floor + 1;
      final newMax    = nextFloor > _maxFloor ? nextFloor - 1 : _maxFloor;
      if (nextFloor - 1 > _maxFloor) {
        _maxFloor = nextFloor - 1;
        _saveMaxFloor(newMax);
      }
      newLog.add('🎉 ${s.floor}階クリア！');

      final nextEnemy = TowerFloorDef.forFloor(nextFloor);
      _stateNotifier.value = _TowerState(
        floor: nextFloor, partyHp: partyHp, partyMaxHp: s.partyMaxHp,
        enemyHp: nextEnemy.hp, enemyMaxHp: nextEnemy.hp, enemyName: nextEnemy.name,
        log: [...newLog, '⚔️ ${nextFloor}階の ${nextEnemy.name} に挑戦！'],
      );
    } else if (partyHp <= 0) {
      newLog.add('💀 全員力尽きた… ${s.floor - 1}階が最高記録！');
      _stateNotifier.value = _TowerState(
        floor: s.floor, partyHp: 0, partyMaxHp: s.partyMaxHp,
        enemyHp: enemyHp, enemyMaxHp: s.enemyMaxHp, enemyName: s.enemyName,
        log: newLog, lost: true,
      );
    } else {
      _stateNotifier.value = _TowerState(
        floor: s.floor, partyHp: partyHp, partyMaxHp: s.partyMaxHp,
        enemyHp: enemyHp, enemyMaxHp: s.enemyMaxHp, enemyName: s.enemyName,
        log: newLog,
      );
    }
  }

  String enemy_name(_TowerState s) => s.enemyName;

  Future<void> _saveMaxFloor(int floor) async {
    final data = await GameStorage.load();
    await GameStorage.save(data.copyWith(towerMaxFloor: floor));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('はじめましてタワーRPG'),
        actions: [
          if (_maxFloor > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('最高 $_maxFloor 階',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: _party.isEmpty
          ? Center(
              child: _EmptyState(
                icon: '⚔️',
                title: 'まだ勇者がいません',
                subtitle: '今日タブで出会いを確認すると\n勇者が仲間に加わります',
              ),
            )
          : Column(children: [
              // ─── 仲間一覧 ──────────────────────────────────────────────
              _PartyBar(party: _party),
              const Divider(height: 1),
              // ─── バトルエリア ───────────────────────────────────────────
              Expanded(
                child: ValueListenableBuilder<_TowerState?>(
                  valueListenable: _stateNotifier,
                  builder: (ctx, st, _) {
                    if (st == null) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🏰', style: TextStyle(fontSize: 72)),
                            const SizedBox(height: 16),
                            const Text('タワーに挑戦しよう！',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text('仲間: ${_party.length} 人', style: TextStyle(color: Theme.of(ctx).colorScheme.outline)),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _startBattle,
                              icon: const Text('⚔️', style: TextStyle(fontSize: 18)),
                              label: const Text('挑戦開始！'),
                              style: FilledButton.styleFrom(minimumSize: const Size(180, 50)),
                            ),
                          ],
                        ),
                      );
                    }
                    return _BattleView(
                      state: st, onAttack: _attack, onRetry: _startBattle);
                  },
                ),
              ),
            ]),
    );
  }
}

// ─── 仲間バー ─────────────────────────────────────────────────────────────────
class _PartyBar extends StatelessWidget {
  final List<TowerHero> party;
  const _PartyBar({required this.party});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: party.length,
        itemBuilder: (ctx, i) {
          final h = party[i];
          final color = rarityBorderColor(h.rarity);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withOpacity(0.2),
                  child: Text(
                    h.name.isNotEmpty ? h.name.characters.first : '?',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 2),
                Text(h.magicName,
                    style: const TextStyle(fontSize: 8, height: 1)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── バトル表示 ───────────────────────────────────────────────────────────────
class _BattleView extends StatelessWidget {
  final _TowerState state;
  final VoidCallback onAttack;
  final VoidCallback onRetry;
  const _BattleView({required this.state, required this.onAttack, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // ─── 階層表示 ──────────────────────────────────────────────────
        Text('${state.floor} 階', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(state.enemyName,
            style: TextStyle(fontSize: 20, color: theme.colorScheme.error)),
        const SizedBox(height: 12),

        // ─── 敵 HP バー ────────────────────────────────────────────────
        _HpBar(label: '👾 敵HP', hp: state.enemyHp, maxHp: state.enemyMaxHp,
            color: theme.colorScheme.error),
        const SizedBox(height: 8),
        // ─── 味方 HP バー ──────────────────────────────────────────────
        _HpBar(label: '🛡️ 勇者HP', hp: state.partyHp, maxHp: state.partyMaxHp,
            color: theme.colorScheme.primary),

        const SizedBox(height: 16),
        // ─── 戦闘ログ ─────────────────────────────────────────────────
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView(
              reverse: true,
              children: state.log.reversed.map((l) =>
                  Text(l, style: const TextStyle(fontSize: 13, height: 1.6))).toList(),
            ),
          ),
        ),

        const SizedBox(height: 12),
        // ─── ボタン ────────────────────────────────────────────────────
        if (state.lost || state.won)
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Text('🔄', style: TextStyle(fontSize: 18)),
            label: const Text('もう一度挑戦'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          )
        else
          FilledButton.icon(
            onPressed: onAttack,
            icon: const Text('⚔️', style: TextStyle(fontSize: 18)),
            label: const Text('攻撃！'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
      ]),
    );
  }
}

class _HpBar extends StatelessWidget {
  final String label;
  final int hp;
  final int maxHp;
  final Color color;
  const _HpBar({required this.label, required this.hp, required this.maxHp, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = maxHp > 0 ? hp / maxHp : 0.0;
    return Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            minHeight: 10,
            color: color,
            backgroundColor: color.withOpacity(0.15),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('$hp/$maxHp', style: const TextStyle(fontSize: 11)),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(icon, style: const TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
      ]),
    );
  }
}
