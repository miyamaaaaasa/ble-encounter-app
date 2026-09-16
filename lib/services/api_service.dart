import 'dart:convert';
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
  static const _keyApiKey = 'api_key_v1';
  static const _keyUserId = 'api_user_id_v1';
  static const _timeout = Duration(seconds: 12);

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
    if (isReady || await _restore()) return true;
    try {
      final res = await http
          .post(Uri.parse('$apiBaseUrl/auth/anon'))
          .timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('[Api] signup failed: ${res.statusCode}');
        return false;
      }
      final m = jsonDecode(res.body) as Map<String, dynamic>;
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
    if (isReady) return true;
    return _signUpAnonymously();
  }

  static Map<String, String> get _headers => {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      };

  // ─── Token ───────────────────────────────────────────────────────

  /// BLEで流す使い捨てトークンを発行（24時間有効）
  static Future<String?> issueToken() async {
    if (!await _ready()) return null;
    try {
      final res = await http
          .post(Uri.parse('$apiBaseUrl/tokens/issue'), headers: _headers)
          .timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('[Api] issueToken: ${res.statusCode}');
        return null;
      }
      return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String?;
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
      final res = await http
          .post(Uri.parse('$apiBaseUrl/tokens/resolve'),
              headers: _headers, body: jsonEncode({'tokens': tokens}))
          .timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('[Api] resolveTokens: ${res.statusCode}');
        return null;
      }
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
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
  static Future<List<Map<String, dynamic>>?> fetchBroadcasts(int sinceId) async {
    // 起動直後は init() がまだ完了しておらず isReady が false になり得る。
    // そこで諦めると次のポーリング（2分後）まで何も出ず、配信直後に
    // アプリを開いた利用者に届かない。他APIと同様に準備完了を待つ。
    if (!await _ready()) return null;
    try {
      final res = await http
          .get(Uri.parse('$apiBaseUrl/broadcasts?since=$sinceId'),
              headers: _headers)
          .timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('[Api] fetchBroadcasts: ${res.statusCode}');
        return null;
      }
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[Api] fetchBroadcasts: $e');
      return null;
    }
  }

  // ─── Profile ─────────────────────────────────────────────────────

  /// 表示名・色・ドット絵・バッジレベルをサーバーへ同期。
  /// ドット絵はサーバー側で4bit/pxに圧縮され128バイトで保存される。
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
    if (!await _ready()) return false;
    try {
      final res = await http
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
      return res.statusCode == 200;
    } catch (e) {
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
      final res = await http
          .delete(Uri.parse('$apiBaseUrl/account'), headers: _headers)
          .timeout(_timeout);
      if (res.statusCode != 200) {
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
      final res = await http
          .post(Uri.parse('$apiBaseUrl/profile'),
              headers: _headers, body: jsonEncode({'piece_data': pixels}))
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[Api] savePieceData: $e');
      return false;
    }
  }
}
