import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

class AppVersionInfo {
  final String version;
  final String url;
  final bool forceUpdate;
  final String releaseNotes;

  AppVersionInfo({
    required this.version,
    required this.url,
    required this.forceUpdate,
    required this.releaseNotes,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      version: json['version'] ?? '1.0.0',
      url: json['url'] ?? '',
      forceUpdate: json['forceUpdate'] ?? false,
      releaseNotes: json['releaseNotes'] ?? '',
    );
  }
}

class UpdateService {
  static Future<AppVersionInfo?> checkForUpdates() async {
    try {
      final response = await http.get(Uri.parse('${ApiService.baseUrl}/api/app-version'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final platformKey = Platform.isAndroid ? 'android' : (Platform.isWindows ? 'windows' : null);
        
        if (platformKey != null && data[platformKey] != null) {
          final serverVersionInfo = AppVersionInfo.fromJson(data[platformKey]);
          final packageInfo = await PackageInfo.fromPlatform();
          
          if (_isNewerVersion(packageInfo.version, serverVersionInfo.version)) {
            return serverVersionInfo;
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
    return null;
  }

  static bool _isNewerVersion(String currentVersion, String serverVersion) {
    try {
      final currentParts = currentVersion.split('.').map(int.parse).toList();
      final serverParts = serverVersion.split('.').map(int.parse).toList();
      
      for (int i = 0; i < currentParts.length && i < serverParts.length; i++) {
        if (serverParts[i] > currentParts[i]) return true;
        if (serverParts[i] < currentParts[i]) return false;
      }
      return serverParts.length > currentParts.length;
    } catch (e) {
      return false; // Fallback if parsing fails
    }
  }

  static Future<void> downloadAndInstallUpdate({
    required String url,
    required Function(double) onProgress,
    required VoidCallback onSuccess,
    required Function(String) onError,
  }) async {
    try {
      final dio = Dio();
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String fileName = url.split('/').last;
      
      // Ensure the correct extension based on platform
      if (Platform.isWindows && !fileName.toLowerCase().endsWith('.exe')) {
        fileName = 'update_$timestamp.exe';
      } else if (Platform.isAndroid) {
        fileName = 'update_$timestamp.apk';
      } else {
        final parts = fileName.split('.');
        final ext = parts.length > 1 ? '.${parts.last}' : '';
        fileName = 'update_$timestamp$ext';
      }

      final savePath = '${dir.path}/$fileName';

      // Check if file already exists from a previous failed attempt, and delete it
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }

      await dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      // Download complete, now launch it
      final result = await OpenFilex.open(
        savePath,
        type: Platform.isAndroid ? 'application/vnd.android.package-archive' : null,
      );
      
      if (result.type == ResultType.done) {
        onSuccess();
        if (Platform.isWindows) {
          // On Windows, close the app immediately so the installer can overwrite files
          exit(0);
        }
      } else {
        onError("Could not open installer: ${result.message}");
      }
    } catch (e) {
      onError("Download failed: $e");
    }
  }
}
