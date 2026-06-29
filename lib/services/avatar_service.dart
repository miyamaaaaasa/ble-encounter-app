import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AvatarService {
  static SupabaseClient get _c => Supabase.instance.client;
  static const _bucket = 'avatars';
  static const _maxSize = 200 * 1024; // 200KB
  static const _maxDim = 256;

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
