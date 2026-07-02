import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AvatarService {
  static SupabaseClient get _c => Supabase.instance.client;
  static const _bucket = 'avatars';
  static const _maxSize = 200 * 1024; // 200KB
  static const _maxDim = 256;
  static const _pendingKey = 'avatar_pending_upload_v1';

  // ─── ローカル永続化（アプリ再起動後もアイコンを保持） ───────────────

  static Future<File> _localFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/avatar.jpg');
  }

  /// ローカル保存済みのアバターファイル（なければ null）
  static Future<File?> loadLocal() async {
    try {
      final f = await _localFile();
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  static Future<File> saveLocal(Uint8List bytes) async {
    final f = await _localFile();
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// ローカル保存＋サーバーアップロード。
  /// オフライン・認証未完了でもローカルには必ず保存され、
  /// 次回起動時に retryPendingUpload() で自動アップロードされる。
  static Future<File> uploadOrQueue(Uint8List bytes) async {
    final file = await saveLocal(bytes);
    final url = await upload(bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingKey, url == null);
    return file;
  }

  /// 前回アップロードに失敗したアイコンを再送する（起動時に呼ぶ）
  static Future<void> retryPendingUpload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_pendingKey) ?? false)) return;
      final f = await loadLocal();
      if (f == null) {
        await prefs.setBool(_pendingKey, false);
        return;
      }
      final url = await upload(await f.readAsBytes());
      if (url != null) {
        await prefs.setBool(_pendingKey, false);
        debugPrint('[Avatar] pending upload completed');
      }
    } catch (e) {
      debugPrint('[Avatar] retryPendingUpload: $e');
    }
  }

  static Future<Uint8List?> pickAndCompress() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    return await compute(_compressImage, bytes);
  }

  static Uint8List _compressImage(Uint8List bytes) {
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    if (decoded.width > _maxDim || decoded.height > _maxDim) {
      decoded = img.copyResize(decoded,
          width: _maxDim, height: _maxDim, maintainAspect: true);
    }

    var quality = 85;
    var result = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    while (result.length > _maxSize && quality > 20) {
      quality -= 10;
      result = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    }
    return result;
  }

  static Future<String?> upload(Uint8List imageBytes) async {
    final userId = _c.auth.currentUser?.id;
    if (userId == null) return null;

    final path = '$userId/avatar.jpg';
    try {
      await _c.storage.from(_bucket).uploadBinary(
        path,
        imageBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );
      final url = _c.storage.from(_bucket).getPublicUrl(path);
      await _c.from('users').update({'avatar_url': url}).eq('id', userId);
      debugPrint('[Avatar] uploaded ${imageBytes.length} bytes → $url');
      return url;
    } catch (e) {
      debugPrint('[Avatar] upload error: $e');
      return null;
    }
  }

  static String? getAvatarUrl(String userId) {
    try {
      return _c.storage
          .from(_bucket)
          .getPublicUrl('$userId/avatar.jpg');
    } catch (_) {
      return null;
    }
  }
}
