// lib/data/services/upload_service.dart

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../../core/constants/api_constants.dart';
class UploadService {
  static const String baseUrl = ApiConstants.baseUrl;
  
  Future<Map<String, dynamic>> uploadFile(File file) async {
    try {
      print('📤 Upload: ${file.path}');
      
      final uri = Uri.parse('$baseUrl/upload');
      final request = http.MultipartRequest('POST', uri);
      
      final fileStream = http.ByteStream(file.openRead());
      final fileLength = await file.length();
      final fileName = path.basename(file.path);
      
      request.files.add(http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: fileName,
      ));
      
      print('📤 Envoi (${(fileLength / 1024 / 1024).toStringAsFixed(2)} MB)...');
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        print('✅ Upload OK');
        return {'success': true, 'filename': fileName};
      } else {
        print('❌ Erreur: ${response.statusCode}');
        return {'success': false, 'error': 'Erreur ${response.statusCode}'};
      }
      
    } catch (e) {
      print('❌ Exception: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}