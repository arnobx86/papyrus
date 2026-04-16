import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_config.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class VersionService {
  static Future<void> checkForUpdates(BuildContext context, {bool showNoUpdateMsg = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim();
      
      // Get Architecture
      String arch = 'universal';
      if (Platform.isAndroid) {
        final deviceInfo = await DeviceInfoPlugin().androidInfo;
        final abi = deviceInfo.supportedAbis.isNotEmpty ? deviceInfo.supportedAbis[0] : '';
        
        if (abi.contains('arm64')) {
          arch = 'arm64';
        } else if (abi.contains('armeabi')) {
          arch = 'arm';
        } else if (abi.contains('x86')) {
          arch = 'x86';
        }
      }
      
      final url = '${AppConfig.websiteUrl}/api/update-check?arch=$arch';
      debugPrint('Update check URL: $url');
      final response = await http.get(Uri.parse(url));
      
      debugPrint('Update check response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Latest version data: $data');
        
        final latestVersion = (data['latest_version'] as String? ?? '').trim();
        final downloadUrl = data['download_url'] as String?;
        final updateType = data['update_type']; // 'soft' or 'force'
        final releaseNotes = data['release_notes'];

        debugPrint('Comparing: Current["$currentVersion"] vs Latest["$latestVersion"]');

        if (latestVersion.isNotEmpty && _isVersionNewer(currentVersion, latestVersion)) {
          debugPrint('Update available! Showing dialog.');
          if (context.mounted) {
            _showUpdateDialog(context, latestVersion, downloadUrl ?? '', updateType == 'force', releaseNotes);
          }
        } else {
          debugPrint('No update needed.');
          if (showNoUpdateMsg && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are on the latest version!'), backgroundColor: Colors.green),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      if (showNoUpdateMsg && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static bool _isVersionNewer(String current, String latest) {
    // Sanitize versions (remove +buildNumber part and whitespace)
    String cleanCurrent = current.split('+')[0].trim();
    String cleanLatest = latest.split('+')[0].trim();

    if (cleanCurrent == cleanLatest) return false;

    List<int> currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    int maxLength = currentParts.length > latestParts.length ? currentParts.length : latestParts.length;

    for (int i = 0; i < maxLength; i++) {
      int c = i < currentParts.length ? currentParts[i] : 0;
      int l = i < latestParts.length ? latestParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static void _showUpdateDialog(BuildContext context, String version, String url, bool isForce, String? notes) {
    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (context) => PopScope(
        canPop: !isForce,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: Color(0xFF195243)),
              const SizedBox(width: 12),
              Text(isForce ? 'Critical Update' : 'New Update Available', style: const TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version $version is now available.', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (notes != null && notes.trim().isNotEmpty) ...[
                  const Text('What\'s new:', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(notes.trim(), style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 16),
                ],
                Text(isForce 
                  ? 'This update is required to continue using the app.' 
                  : 'Would you like to download the latest version for better performance?'),
              ],
            ),
          ),
          actions: [
            if (!isForce)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later', style: TextStyle(color: Colors.grey)),
              ),
            ElevatedButton(
              onPressed: () {
                if (url.isNotEmpty) {
                  _launchURL(url);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF195243),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _launchURL(String url) async {
    try {
      final uri = Uri.parse(url);
      // Try external application mode first
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success) {
        // Fallback to default
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Could not launch update URL: $e');
    }
  }
}
