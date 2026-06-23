import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/encounter_record.dart';
import '../../models/game_data.dart';
import '../../services/game_storage.dart';

// ─── ③ すれちがい水族館 ──────────────────────────────────────────────────────

class AquariumScreen extends StatefulWidget {
  final List<EncounterRecord> todayRevealed;
  const AquariumScreen({super.key, required this.todayRevealed});

  @override
  State<AquariumScreen> createState() => _AquariumScreenState();
}

class _AquariumScreenState extends State<AquariumScreen>
    with SingleTickerProviderStateMixin {
  List<AquariumFish> _pond    = []; // 今日の池（未釣り）
  List<AquariumFish> _fishBook= []; // 図鑑（釣り上げた全魚）
  Set<String> _todayFish      = {};
  bool _loading               = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data      = await GameStorage.load();
    final todayFish = await GameStorage.loadTodayFish();
    // 今日の出会いを池に放流（まだ放流されていない分のみ）
    var aquariumHistory = List<AquariumFish>.from(data.aquariumHistory);

    for (final e in widget.todayRevealed) {
      if (todayFish.contains(e.peerId)) continue;
      final fish = AquariumFish.fromEncounter(e);
      aquariumHistory.add(fish);
      todayFish.add(e.peerId);
    }

    if (aquariumHistory.length != data.aquariumHistory.length) {
      await GameStorage.save(data.copyWith(aquariumHistory: aquariumHistory));
      await GameStorage.saveTodayFish(todayFish);
    }

    // 今日の未釣り魚 = 今日addedAtで !caught
    final today = DateTime.now();
    final pond = aquariumHistory.where((f) =>
        !f.caught &&
        f.addedAt.year  == today.year &&
        f.addedAt.month == today.month &&
        f.addedAt.day   == today.day).toList();

    final book = aquariumHistory.where((f) => f.caught).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));

    if (!mounted) return;
    setState(() {
      _pond       = pond;
      _fishBook   = book;
      _todayFish  = todayFish;
      _loading    = false;
    });
  }

  Future<void> _catchFish(AquariumFish fish) async {
    final data = await GameStorage.load();
    final updated = data.aquariumHistory.map((f) =>
        f.peerId == fish.peerId && !f.caught ? f.copyWith(caught: true) : f).toList();
    await GameStorage.save(data.copyWith(aquariumHistory: updated));
    await GameStorage.saveTodayFish(_todayFish);

    final caught = updated.firstWhere(
        (f) => f.peerId == fish.peerId && f.caught,
        orElse: () => fish.copyWith(caught: true));

    if (!mounted) return;
    setState(() {
      _pond    = _pond.where((f) => f.peerId != fish.peerId).toList();
      _fishBook = [caught, ..._fishBook];
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${fish.emoji} ${fish.name} を釣り上げた！（${fish.region}から）'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('すれちがい水族館'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: '🏊 釣り場（${_pond.length}匹）'),
            Tab(text: '📖 図鑑（${_fishBook.length}匹）'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _PondView(pond: _pond, onCatch: _catchFish),
          _FishBookView(book: _fishBook),
        ],
      ),
    );
  }
}

// ─── 釣り場ビュー ─────────────────────────────────────────────────────────────
class _PondView extends StatelessWidget {
  final List<AquariumFish> pond;
  final void Function(AquariumFish) onCatch;
  const _PondView({required this.pond, required this.onCatch});

  @override
  Widget build(BuildContext context) {
    if (pond.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🌊', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text('今日の池はまだ空っぽ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('今日タブで出会いを確認すると\nその人の地域の魚が池に放流されます',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
        ]),
      );
    }

    return Column(children: [
      // ─── 池（CustomPainter背景 + 魚タップ）──────────────────────────
      Expanded(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CustomPaint(
              painter: _PondPainter(),
              child: _FishInPond(pond: pond, onCatch: onCatch),
            ),
          ),
        ),
      ),
      // ─── 説明 ───────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text('魚をタップして釣り上げよう！',
            style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
      ),
    ]);
  }
}

class _PondPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 水色グラデーション背景
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1565C0), Color(0xFF42A5F5), Color(0xFF80DEEA)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 波紋（楕円）
    final wavePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (int i = 1; i <= 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5, size.height * 0.5),
          width: size.width * 0.2 * i,
          height: size.height * 0.15 * i,
        ),
        wavePaint,
      );
    }

    // 底の砂地
    final sandPaint = Paint()..color = const Color(0xFFF5DEB3).withOpacity(0.3);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.88),
        width: size.width * 0.9,
        height: size.height * 0.2,
      ),
      sandPaint,
    );
  }

  @override
  bool shouldRepaint(_PondPainter _) => false;
}

class _FishInPond extends StatelessWidget {
  final List<AquariumFish> pond;
  final void Function(AquariumFish) onCatch;
  const _FishInPond({required this.pond, required this.onCatch});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      return Stack(
        children: pond.asMap().entries.map((entry) {
          final i    = entry.key;
          final fish = entry.value;
          // 決定論的配置（peerId hashベース）
          final hash = fish.peerId.hashCode.abs();
          final px   = ((hash * 17 + i * 73) % 80 + 10) / 100.0; // 10-90%
          final py   = ((hash * 31 + i * 59) % 60 + 15) / 100.0; // 15-75%

          return Positioned(
            left: w * px - 20,
            top:  h * py - 20,
            child: GestureDetector(
              onTap: () => onCatch(fish),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(fish.emoji, style: const TextStyle(fontSize: 36)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(fish.region,
                      style: const TextStyle(color: Colors.white, fontSize: 8)),
                ),
              ]),
            ),
          );
        }).toList(),
      );
    });
  }
}

// ─── 図鑑ビュー ───────────────────────────────────────────────────────────────
class _FishBookView extends StatelessWidget {
  final List<AquariumFish> book;
  const _FishBookView({required this.book});

  @override
  Widget build(BuildContext context) {
    if (book.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('📖', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text('まだ図鑑は空っぽ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text('池の魚を釣り上げて図鑑を埋めよう！',
              style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
        ]),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 0.85,
        crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      itemCount: book.length,
      itemBuilder: (ctx, i) {
        final fish = book[i];
        final d = fish.addedAt;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Theme.of(ctx).colorScheme.outline.withOpacity(0.3)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(fish.emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 4),
            Text(fish.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(fish.region,
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(ctx).colorScheme.primary)),
            Text('${d.month}/${d.day}',
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(ctx).colorScheme.outline)),
          ]),
        );
      },
    );
  }
}
