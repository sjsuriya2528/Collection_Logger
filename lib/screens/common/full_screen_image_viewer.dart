import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../../services/api_service.dart';

class FullScreenImageViewer extends StatefulWidget {
  final String path;
  final String title;

  const FullScreenImageViewer({super.key, required this.path, required this.title});

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  bool _showUI = true;

  @override
  Widget build(BuildContext context) {
    final bool isLocal = !widget.path.startsWith('http') && !widget.path.startsWith('/uploads');
    final String imageUrl = isLocal ? '' : ApiService.getImageUrl(widget.path);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AnimatedOpacity(
          opacity: _showUI ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: AppBar(
            backgroundColor: Colors.black26,
            elevation: 0,
            title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 5.0,
            child: Hero(
              tag: widget.path,
              child: isLocal
                  ? Image.file(File(widget.path), fit: BoxFit.contain)
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.cyanAccent),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_rounded, color: Colors.redAccent, size: 64),
                          SizedBox(height: 16),
                          Text('Failed to load image', style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
