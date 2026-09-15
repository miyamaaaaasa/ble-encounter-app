import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/broadcast_service.dart';

/// バナーに出す1件と、一覧に出す全件。
class BroadcastState {
  final Broadcast? banner; // 未読のうち最新1件（閉じたら null）
  final List<Broadcast> all; // 新しい順の一覧

  const BroadcastState({this.banner, this.all = const []});
}

/// 管理者からのお知らせ（文化祭運営用）の受信状態。
///
/// アプリ起動中に定期ポーリングする。プッシュ通知ではないため、
/// アプリを完全に閉じている間は届かない（FCM等の外部サービスを
/// 導入せず自前サーバー完結を優先した結果の割り切り）。
class BroadcastNotifier extends StateNotifier<BroadcastState> {
  BroadcastNotifier() : super(const BroadcastState()) {
    _start();
  }

  Timer? _timer;
  static const _interval = Duration(minutes: 2);

  Future<void> _start() async {
    await _reload(); // 保存済みを先に表示（オフラインでも見える）
    await refresh();
    _timer = Timer.periodic(_interval, (_) => refresh());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    state = BroadcastState(
      banner: await BroadcastService.bannerTarget(),
      all: await BroadcastService.loadCached(),
    );
  }

  Future<void> refresh() async {
    try {
      final fresh = await BroadcastService.fetchNew();
      if (fresh.isEmpty) return;
      await _reload();
      debugPrint('[Broadcast] ${fresh.length} new arrived');
    } catch (e) {
      debugPrint('[Broadcast] refresh error: $e');
    }
  }

  /// バナーを閉じる。閉じた位置は端末に保存されるので、
  /// 次回のポーリングで同じものが再表示されることはない。
  Future<void> dismissBanner() async {
    final b = state.banner;
    if (b == null) return;
    await BroadcastService.dismissUpTo(b.id);
    await _reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final broadcastProvider =
    StateNotifierProvider<BroadcastNotifier, BroadcastState>(
        (ref) => BroadcastNotifier());
