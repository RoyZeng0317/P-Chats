import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class MediaResult {
  final String url;
  final String publicId;
  MediaResult({required this.url, required this.publicId});
}

class PickedFile {
  final File file;
  final String name;
  PickedFile({required this.file, required this.name});
}

class MediaService {
  final _picker = ImagePicker();

  Future<File?> pickImage() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<File?> captureImage() async {
    final picked = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 85);
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<File?> pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<File?> captureVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.camera);
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<PickedFile?> pickFile() async {
    // withData:true ensures bytes are loaded even under Android scoped storage
    final result =
        await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;

    File file;
    if (f.bytes != null) {
      // Write bytes to a temp file so we have a normal File path for upload
      final tmp = await getTemporaryDirectory();
      final tmpFile = File('${tmp.path}/${f.name}');
      await tmpFile.writeAsBytes(f.bytes!);
      file = tmpFile;
    } else if (f.path != null) {
      file = File(f.path!);
    } else {
      return null;
    }

    return PickedFile(file: file, name: f.name);
  }

  // Signed upload using API Key + Secret — no upload preset required.
  // resourceType: 'image' | 'video' | 'raw'
  Future<(MediaResult?, String?)> upload(
      String uid, File file, String resourceType) async {
    try {
      final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
      final apiKey = dotenv.env['CLOUDINARY_API_KEY'] ?? '';
      final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'] ?? '';

      if (cloudName.isEmpty) return (null, '缺少 CLOUDINARY_CLOUD_NAME');
      if (apiKey.isEmpty) return (null, '缺少 CLOUDINARY_API_KEY');
      if (apiSecret.isEmpty) return (null, '缺少 CLOUDINARY_API_SECRET');

      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final folder = 'pchats/$uid';

      // Params must be sorted alphabetically before signing
      final toSign = 'folder=$folder&timestamp=$timestamp';
      final signature =
          sha256.convert(utf8.encode(toSign + apiSecret)).toString();

      final uri = Uri.parse(
          'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');

      final request = http.MultipartRequest('POST', uri)
        ..fields['api_key'] = apiKey
        ..fields['timestamp'] = timestamp.toString()
        ..fields['signature'] = signature
        ..fields['folder'] = folder
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      debugPrint('[MediaService] status=${response.statusCode}');
      debugPrint('[MediaService] body=${response.body}');

      if (response.statusCode != 200) {
        String errMsg = 'HTTP ${response.statusCode}';
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final msg = body['error']?['message'] as String?;
          if (msg != null && msg.isNotEmpty) errMsg = msg;
        } catch (_) {}
        return (null, errMsg);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (
        MediaResult(
          url: data['secure_url'] as String,
          publicId: data['public_id'] as String,
        ),
        null,
      );
    } catch (e) {
      debugPrint('[MediaService] upload exception: $e');
      return (null, e.toString());
    }
  }

  Future<void> delete(String publicId, String resourceType) async {
    try {
      final cloudName = dotenv.env['CLOUDINARY_CLOUD_NAME'] ?? '';
      final apiKey = dotenv.env['CLOUDINARY_API_KEY'] ?? '';
      final apiSecret = dotenv.env['CLOUDINARY_API_SECRET'] ?? '';

      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final toSign = 'public_id=$publicId&timestamp=$timestamp';
      final signature =
          sha256.convert(utf8.encode(toSign + apiSecret)).toString();

      await http.post(
        Uri.parse(
            'https://api.cloudinary.com/v1_1/$cloudName/$resourceType/destroy'),
        body: {
          'public_id': publicId,
          'api_key': apiKey,
          'timestamp': timestamp.toString(),
          'signature': signature,
          'signature_algorithm': 'sha256',
        },
      );
    } catch (_) {}
  }
}
