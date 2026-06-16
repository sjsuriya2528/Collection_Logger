import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final AppVersionInfo versionInfo;

  const UpdateDialog({Key? key, required this.versionInfo}) : super(key: key);

  static Future<void> showIfNeeded(BuildContext context) async {
    final versionInfo = await UpdateService.checkForUpdates();
    if (versionInfo != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: !versionInfo.forceUpdate,
        builder: (context) => UpdateDialog(versionInfo: versionInfo),
      );
    }
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = '';

  void _startDownload() {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Downloading update...';
    });

    UpdateService.downloadAndInstallUpdate(
      url: widget.versionInfo.url,
      onProgress: (progress) {
        setState(() {
          _progress = progress;
        });
      },
      onSuccess: () {
        if (mounted) {
          setState(() {
            _statusMessage = 'Download complete! Opening installer...';
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _statusMessage = 'Error: $error';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !widget.versionInfo.forceUpdate,
      child: AlertDialog(
        title: Text('Update Available (${widget.versionInfo.version})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A new version of the app is available.'),
            const SizedBox(height: 12),
            if (widget.versionInfo.releaseNotes.isNotEmpty) ...[
              const Text('What\'s new:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(widget.versionInfo.releaseNotes),
              const SizedBox(height: 16),
            ],
            if (_isDownloading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ],
            if (_statusMessage.isNotEmpty)
              Text(
                _statusMessage,
                style: TextStyle(
                  color: _statusMessage.startsWith('Error') ? Colors.red : Colors.green,
                ),
              ),
          ],
        ),
        actions: [
          if (!widget.versionInfo.forceUpdate && !_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          if (!_isDownloading)
            ElevatedButton(
              onPressed: _startDownload,
              child: const Text('Update Now'),
            ),
        ],
      ),
    );
  }
}
