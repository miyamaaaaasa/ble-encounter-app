import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_snapshot.dart';
import 'account_cipher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../core/api_config.dart';

/// 自前サーバー（さくらVPS）との通信。旧 SupabaseService の置き換え。
///
/// 認証は失効しないAPIキー方式（SecureStorageに保管）。
/// Supabase時代に起きていた「約6時間でセッションが切れて同期が止まる」問題が
/// 構造的に発生しない。
///
/// 公開メソッドのシグネチャは旧 SupabaseService と揃えてあるため、
/// 呼び出し側（providers / resolver / editor）の変更は最小限で済む。
class ApiService {
  ApiService._();

  static const _store = FlutterSecureStorage();
  @visibleForTesting
  static http.Client client = http.Client();
  static const _keyApiKey = 'api_key_v1';
  static const _keyUserId = 'api_user_id_v1';
  static const _timeout = Duration(seconds: 12);

  static final accountBlocked = ValueNotifier<bool>(false);
  static const blockedKey = 'account_blocked_v1';
  static const recoveryKey = 'account_recovery_v1';
  static const resetPendingKey = 'account_reset_pending_v1';
  static const quarantineKey = 'account_quarantine_v1';
  static const archiveSecretKey = 'account_archive_secret_v1';
  static String? _lastSnapshot;
  static bool _syncingAccount = false;
  static String? _apiKey;
  static String? _userId;

  /// 多重実行防止。init / 匿名登録が同時に走っても実際の処理は1回だけにする。
  /// これが無いと、保存前の read が null を返した分だけ匿名登録が重複し、
  /// 起動のたびに別人格が量産される（＝発行したトークンが解決できなくなる）。
  static Future<void>? _initFuture;
  static Future<bool>? _signUpFuture;

  static String? get userId => _userId;
  static bool get isReady => _apiKey != null && _userId != null;

  /// 起動時に呼ぶ。保存済みの資格情報を復元し、無ければ匿名登録する。
  /// 何度呼んでも初回の処理を共有する（副作用は起きない）。
  static Future<void> init() => _initFuture ??= _init();

  static Future<void> _init() async {
    accountBlocked.value =
        (await SharedPreferences.getInstance()).getBool(blockedKey) ?? false;
    if (accountBlocked.value) {
      AccountSnapshot.locked = true;
      return;
    }
    if (await _restore()) {
      debugPrint('[Api] restored uid=${_userId!.substring(0, 8)}');
      return;
    }
    await _signUpAnonymously();
  }

  /// 保存済み資格情報の読み出し。取得できた場合のみフィールドへ反映する
  /// （null で上書きしないことが競合対策の要）。
  static Future<bool> _restore() async {
    final key = await _store.read(key: _keyApiKey);
    final uid = await _store.read(key: _keyUserId);
    if (key == null || uid == null) return false;
    _apiKey = key;
    _userId = uid;
    return true;
  }

  /// 匿名ユーザーを新規作成（旧 signInAnonymously 相当）。
  /// 本名・メール・電話などは一切送らない（匿名性の維持）。
  static Future<bool> _signUpAnonymously() =>
      _signUpFuture ??= _doSignUp().whenComplete(() => _signUpFuture = null);

  static Future<bool> _doSignUp() async {
    // 直前に別経路が登録を終えていれば、それを使い回して新規作成しない
    if (accountBlocked.value) return false;
    if (isReady || await _restore()) return true;
    try {
      final res = await client
          .post(Uri.parse('$apiBaseUrl/auth/anon'))
          .timeout(_timeout);
      if (!_accepted(res)) {
        debugPrint('[Api] signup failed: ${res.statusCode}');
        return false;
      }
      final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final key = m['api_key'] as String?;
      final uid = m['user_id'] as String?;
      if (key == null || uid == null) {
        debugPrint('[Api] signup failed: malformed response');
        return false;
      }
      await _store.write(key: _keyApiKey, value: key);
      await _store.write(key: _keyUserId, value: uid);
      _apiKey = key;
      _userId = uid;
      debugPrint('[Api] anonymous signup OK uid=${uid.substring(0, 8)}');
      return true;
    } catch (e) {
      debugPrint('[Api] signup error: $e');
      return false;
    }
  }

  /// 未登録なら登録を試みる（オフライン起動後の自己回復）
  static Future<bool> _ready() async {
    if (accountBlocked.value) return false;
    if (isReady) return true;
    return _signUpAnonymously();
  }

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      };

  static bool _accepted(http.Response res) {
    if (res.statusCode == 403 || res.statusCode == 401) {
      try {
        if (const {
          'account_inactive',
          'unauthorized'
        }.contains((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error'])) {
          AccountSnapshot.locked = true;
          accountBlocked.value = true;
        }
      } catch (_) {}
    }
    return res.statusCode == 200 && !accountBlocked.value;
  }

  /// Check session on foreground entry; upload only changed compressed data.
  static Future<void> checkAccount() async {
    await init();
    if (accountBlocked.value || !await _ready() || _syncingAccount) return;
    _syncingAccount = true;
    try {
      var recovery = await _store.read(key: recoveryKey);
      if (recovery == null) {
        final rng = Random.secure();
        recovery = List.generate(
                32, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
      }
      final archive = await AccountSnapshot.capture();
      var secret = await _store.read(key: archiveSecretKey);
      if (secret == null) {
        secret = await AccountCipher.newKey();
        await _store.write(key: archiveSecretKey, value: secret);
      }
      final encrypted = archive != _lastSnapshot
          ? await AccountCipher.encrypt(archive, secret, _userId!)
          : null;
      final res = await client
          .post(Uri.parse('$apiBaseUrl/account/session'),
              headers: _headers,
              body: jsonEncode({
                'recovery_key': recovery,
                if (encrypted != null) 'archive': encrypted
              }))
          .timeout(_timeout);
      if (_accepted(res)) {
        await _store.write(key: recoveryKey, value: recovery);
        _lastSnapshot = archive;
      }
    } catch (_) {/* Offline never implies deletion. */} finally {
      _syncingAccount = false;
    }
  }

  /// Non-login proof and encrypted quarantine are kept separately from the revoked session.
  static Future<void> releaseBlockedAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(blockedKey, true);
    await prefs.setBool(resetPendingKey, true);
    // Legacy anonymous accounts use their existing device proof only to request
    // a NEW session explicitly. The old bearer key stays permanently revoked.
    final legacyProof = _apiKey ?? await _store.read(key: _keyApiKey);
    if (await _store.read(key: recoveryKey) == null && legacyProof != null) {
      await _store.write(key: recoveryKey, value: legacyProof);
    }
    if (prefs.getString('own_profile_v1') != null ||
        await _store.read(key: quarantineKey) == null) {
      await _store.write(
          key: quarantineKey, value: await AccountSnapshot.capture());
    }
    await _store.delete(key: _keyApiKey);
    await _store.delete(key: _keyUserId);
    _apiKey = null;
    _userId = null;
    _lastSnapshot = null;
  }

  static Future<bool> reconnectAccount() async {
    final recovery = await _store.read(key: recoveryKey);
    if (recovery == null) return false;
    final res = await client
        .post(Uri.parse('$apiBaseUrl/auth/reconnect'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'recovery_key': recovery}))
        .timeout(_timeout);
    if (res.statusCode != 200) return false;
    final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final local = await _store.read(key: quarantineKey);
    final secret = await _store.read(key: archiveSecretKey);
    final cloud = m['archive'] as String;
    final archive = local ??
        (cloud.isEmpty
            ? ''
            : await AccountCipher.decrypt(
                cloud, secret!, m['user_id'] as String));
    await AccountSnapshot.restore(archive);
    await _store.write(key: _keyApiKey, value: m['api_key'] as String);
    await _store.write(key: _keyUserId, value: m['user_id'] as String);
    _apiKey = m['api_key'] as String;
    _userId = m['user_id'] as String;
    await (await SharedPreferences.getInstance()).remove(blockedKey);
    await _store.delete(key: quarantineKey);
    _initFuture = Future.value();
    AccountSnapshot.locked = false;
    accountBlocked.value = false;
    return true;
  }

  // ─── Token ───────────────────────────────────────────────────────

  /// BLEで流す使い捨てトークンを発行（24時間有効）
  static Future<String?> issueToken() async {
    if (!await _ready()) return null;
    try {
      final res = await client
          .post(Uri.parse('$apiBaseUrl/tokens/issue'), headers: _headers)
          .timeout(_timeout);
      if (!_accepted(res)) {
        debugPrint('[Api] issueToken: ${res.statusCode}');
        return null;
      }
      return (jsonDecode(utf8.decode(res.bodyBytes))
          as Map<String, dynamic>)['token'] as String?;
    } catch (e) {
      debugPrint('[Api] issueToken: $e');
      return null;
    }
  }

  /// 収集したトークンを相手プロフィールへ解決。
  /// 通信エラー時は null を返す（成功して0件の [] と区別する）。
  /// null のときは呼び出し側がトークンを保持し続けるため、すれ違いが消えない。
  static Future<List<Map<String, dynamic>>?> resolveTokens(
      List<String> tokens) async {
    if (tokens.isEmpty) return [];
    if (!await _ready()) return null;
    try {
      final res = await client
          .post(Uri.parse('$apiBaseUrl/tokens/resolve'),
              headers: _headers, body: jsonEncode({'tokens': tokens}))
          .timeout(_timeout);
      if (!_accepted(res)) {
        debugPrint('[Api] resolveTokens: ${res.statusCode}');
        return null;
      }
      return (jsonDecode(utf8.decode(res.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Api] resolveTokens: $e');
      return null;
    }
  }

  // ─── お知らせ配信（文化祭運営用）─────────────────────────────────

  /// 管理者が配信したお知らせを取得する。
  ///
  /// プッシュ通知ではなくポーリング方式。FCM等の外部サービスを導入せず
  /// 自前サーバーで完結させるため、アプリ起動中のみ受信できる。
  /// [sinceId] より新しいものだけが返るので、端末側は最後に読んだIDを保持する。
  /// 通信エラー時は null（呼び出し側が既読IDを進めないようにするため、
  /// 成功して0件の [] とは区別する）。
  static Future<List<Map<String, dynamic>>?> fetchBroadcasts(
      int sinceId) async {
    // 起動直後は init() がまだ完了しておらず isReady が false になり得る。
    // そこで諦めると次のポーリング（2分後）まで何も出ず、配信直後に
    // アプリを開いた利用者に届かない。他APIと同様に準備完了を待つ。
    if (!await _ready()) return null;
    try {
      final res = await client
          .get(Uri.parse('$apiBaseUrl/broadcasts?since=$sinceId'),
              headers: _headers)
          .timeout(_timeout);
      if (!_accepted(res)) {
        debugPrint('[Api] fetchBroadcasts: ${res.statusCode}');
        return null;
      }
      return (jsonDecode(utf8.decode(res.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Api] fetchBroadcasts: $e');
      return null;
    }
  }

  // ─── すれ違いの相互記録 ───────────────────────────────────────────

  /// 「自分を検出した相手」の一覧を取得する。
  ///
  /// BLEの検出は必ずしも双方向に成立しない。とくにiOSはバックグラウンドに入ると
  /// 広告がApple独自形式へ移り、Android端末からは検出できない（OSの制約）。
  /// そこでサーバーが「AがBを解決したらB側にも記録する」ため、ここを取り込めば
  /// 片方向しか検出できない組み合わせでも出会いが成立する。
  ///
  /// 相手IDで突き合わせて重ねるだけなので、何度呼んでも二重登録は起きない。
  /// 通信エラー時は null（呼び出し側が無言で諦められるように空と区別する）。
  static Future<List<Map<String, dynamic>>?> fetchMutualEncounters() async {
    if (!await _ready()) return null;
    try {
      final res = await client
          .get(Uri.parse('$apiBaseUrl/encounters/mutual'), headers: _headers)
          .timeout(_timeout);
      if (!_accepted(res)) {
        debugPrint('[Api] fetchMutual: ${res.statusCode}');
        return null;
      }
      return (jsonDecode(utf8.decode(res.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Api] fetchMutual: $e');
      return null;
    }
  }

  // ─── Profile ─────────────────────────────────────────────────────

  /// 表示名・色・ドット絵・バッジレベルをサーバーへ同期。
  /// ドット絵はサーバー側で4bit/pxに圧縮され128バイトで保存される。
  static String? profileError;
  static Future<bool> syncProfile({
    required String displayName,
    required int colorIndex,
    List<int>? piecePixels,
    int? badgeLevel,
    // 自己紹介テンプレート（初期設定で選ぶ4項目の選択肢インデックス）。
    // 自由入力は送らない＝匿名性を保ったまま人となりだけ伝える。
    int? introStatus,
    int? introHobbyCat,
    int? introHobbyDet,
    int? introPhrase,
  }) async {
    profileError = null;
    if (!await _ready()) {
      profileError = '通信状況を確認してください';
      return false;
    }
    try {
      final res = await client
          .post(Uri.parse('$apiBaseUrl/profile'),
              headers: _headers,
              body: jsonEncode({
                'display_name': displayName,
                'color_index': colorIndex,
                if (piecePixels != null) 'piece_data': piecePixels,
                if (badgeLevel != null) 'badge_level': badgeLevel,
                if (introStatus != null) 'intro_status': introStatus,
                if (introHobbyCat != null) 'intro_hobby_cat': introHobbyCat,
                if (introHobbyDet != null) 'intro_hobby_det': introHobbyDet,
                if (introPhrase != null) 'intro_phrase': introPhrase,
              }))
          .timeout(_timeout);
      if (res.statusCode == 422) {
        profileError = 'この名前は使用できません';
      } else if (res.statusCode != 200) {
        profileError = '保存できませんでした。通信状況を確認してください';
      }
      return _accepted(res);
    } catch (e) {
      profileError = '保存できませんでした。通信状況を確認してください';
      debugPrint('[Api] syncProfile: $e');
      return false;
    }
  }

  /// サーバー上の自分のデータを完全に削除する（Google Playのデータ削除要件）。
  ///
  /// 成功したら端末に保存した資格情報も破棄するため、以後は次回起動時に
  /// 新しい匿名ユーザーとして登録し直される（＝別人として再出発する）。
  static Future<bool> deleteAccount() async {
    if (!isReady) return true; // 未登録なら消すものが無い
    try {
      final res = await client
          .delete(Uri.parse('$apiBaseUrl/account'), headers: _headers)
          .timeout(_timeout);
      if (!_accepted(res)) {
        debugPrint('[Api] deleteAccount: ${res.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[Api] deleteAccount: $e');
      return false;
    }
    await _store.delete(key: _keyApiKey);
    await _store.delete(key: _keyUserId);
    _apiKey = null;
    _userId = null;
    _initFuture = null; // 次回 init() で新規登録できるようにする
    debugPrint('[Api] account deleted');
    return true;
  }

  /// ドット絵だけを更新（エディタ保存時）
  static Future<bool> savePieceData(List<int> pixels) async {
    if (!await _ready()) return false;
    try {
      final res = await client
          .post(Uri.parse('$apiBaseUrl/profile'),
              headers: _headers, body: jsonEncode({'piece_data': pixels}))
          .timeout(_timeout);
      return _accepted(res);
    } catch (e) {
      debugPrint('[Api] savePieceData: $e');
      return false;
    }
  }
}
