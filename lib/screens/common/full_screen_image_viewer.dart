import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../services/api_service.dart';

class FullScreenImageViewer extends StatefulWidget {
  final List<String> paths;
  final int initialIndex;
  final String title;

  const FullScreenImageViewer({
    super.key, 
    required this.paths, 
    this.initialIndex = 0,
    required this.title,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> with SingleTickerProviderStateMixin {
  bool _showUI = true;
  late int _currentIndex;
  late PageController _pageController;
  final TransformationController _transformationController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;
  int _rotationQuarterTurns = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (_animation != null) {
          _transformationController.value = _animation!.value;
        }
      });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_animationController.isAnimating) return;
    
    final position = _doubleTapDetails!.localPosition;
    final double scale = 3.0; // Target zoom scale
    
    Matrix4 endMatrix;
    if (_transformationController.value.isIdentity()) {
      // Zoom in
      final x = -position.dx * (scale - 1);
      final y = -position.dy * (scale - 1);
      endMatrix = Matrix4.identity()
        ..translate(x, y)
        ..scale(scale);
    } else {
      // Zoom out
      endMatrix = Matrix4.identity();
    }

    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(CurveTween(curve: Curves.easeInOut).animate(_animationController));

    _animationController.forward(from: 0);
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _rotationQuarterTurns = 0;
      _transformationController.value = Matrix4.identity();
    });
  }

  void _previousPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _nextPage() {
    if (_currentIndex < widget.paths.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _previousPage();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _nextPage();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
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
            title: Text(
              widget.paths.length > 1 
                  ? '${widget.title} (${_currentIndex + 1}/${widget.paths.length})'
                  : widget.title, 
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.rotate_90_degrees_cw_rounded, color: Colors.white),
                onPressed: () => setState(() => _rotationQuarterTurns++),
              ),
            ],
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
        ),
      ),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _showUI = !_showUI),
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: _handleDoubleTap,
            child: Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: widget.paths.length,
                itemBuilder: (context, index) {
                  final String path = widget.paths[index];
                  final bool isLocal = !path.startsWith('http') && !path.startsWith('/uploads');
                  final String imageUrl = isLocal ? '' : ApiService.getImageUrl(path);

                  return InteractiveViewer(
                    transformationController: index == _currentIndex ? _transformationController : null,
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: RotatedBox(
                      quarterTurns: index == _currentIndex ? _rotationQuarterTurns : 0,
                      child: Hero(
                        tag: path,
                        child: isLocal
                          ? Image.file(File(path), fit: BoxFit.contain)
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
                  );
                },
              ),
            ),
          ),
          
          // Desktop Navigation Arrows
          if (_showUI && (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) && widget.paths.length > 1) ...[
            if (_currentIndex > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 32),
                    onPressed: _previousPage,
                  ),
                ),
              ),
            if (_currentIndex < widget.paths.length - 1)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 32),
                    onPressed: _nextPage,
                  ),
                ),
              ),
          ],
        ],
      ),
    ));
  }
}
