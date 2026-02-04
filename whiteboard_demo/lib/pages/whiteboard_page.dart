import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/developer_mode_provider.dart';
import '../services/app_config_service.dart';
import '../controllers/whiteboard_controller.dart';
import '../controllers/timeline_playback_controller.dart';
import '../services/timeline_api_service.dart';
import '../services/lesson_api_service.dart';
import '../whiteboard/painters/whiteboard_painter.dart';
import '../services/stroke_timing_service.dart' show StrokeTimingConfig;

/// Lesson context passed to the whiteboard
class LessonContext {
  final int? lessonId;
  final int? sessionId;
  final String? topic;
  final String? title;

  const LessonContext({
    this.lessonId,
    this.sessionId,
    this.topic,
    this.title,
  });
}

/// Main whiteboard page with mobile-first UI
class WhiteboardPageMobile extends StatefulWidget {
  final LessonContext? lessonContext;
  final VoidCallback? onLessonComplete;

  const WhiteboardPageMobile({
    super.key,
    this.lessonContext,
    this.onLessonComplete,
  });

  @override
  State<WhiteboardPageMobile> createState() => _WhiteboardPageMobileState();
}

class _WhiteboardPageMobileState extends State<WhiteboardPageMobile>
    with SingleTickerProviderStateMixin {
  late final WhiteboardController _controller;
  late final TimelinePlaybackController _playbackController;
  int _navIndex = 0;
  bool _isLoading = true;

  // Text input controllers
  final _textPromptController = TextEditingController(text: 'Hello');
  final _textXController = TextEditingController(text: '0');
  final _textYController = TextEditingController(text: '0');
  final _textSizeController = TextEditingController(text: '180');

  // Image input controllers (for dev mode)
  final _imageNameController = TextEditingController(text: 'triangle.json');
  final _imageXController = TextEditingController(text: '0');
  final _imageYController = TextEditingController(text: '0');
  final _imageScaleController = TextEditingController(text: '1.0');

  bool _controllersInitialized = false;

  @override
  void initState() {
    super.initState();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_controllersInitialized) {
      _controllersInitialized = true;
      _initializeControllers();
    }
  }
  
  void _initializeControllers() {
    // Get config service for backend URL
    final configService = Provider.of<AppConfigService>(context, listen: false);
    final baseUrl = configService.backendUrl;
    
    _controller = WhiteboardController(baseUrl: baseUrl);
    _controller.initAnimation(this);
    
    _playbackController = TimelinePlaybackController();
    _playbackController.setBaseUrl(baseUrl);
    
    // Set the drawing callback
    _playbackController.onDrawingActionsTriggered = _controller.handleDrawingActions;
    
    _playbackController.onTimelineCompleted = _onLessonComplete;

    _initialize();
  }

  Future<void> _initialize() async {
    // Try to load backend objects, but don't fail if backend is unavailable
    try {
      await _controller.loadFromBackend();
    } catch (e) {
      debugPrint('Backend load skipped: $e');
    }
    
    // If we have a lesson context, start or load the lesson
    if (widget.lessonContext != null) {
      await _initializeLesson(widget.lessonContext!);
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _initializeLesson(LessonContext context) async {
    final configService = Provider.of<AppConfigService>(this.context, listen: false);
    final baseUrl = configService.backendUrl;
    
    int? sessionId = context.sessionId;
    
    // If we have a topic but no sessionId, start a new lesson
    if (sessionId == null && context.topic != null) {
      try {
        debugPrint('Starting new lesson for topic: ${context.topic}');
        final lessonApi = LessonApiService(baseUrl: baseUrl);
        final session = await lessonApi.startLesson(topic: context.topic!);
        sessionId = session.id;
        debugPrint('Lesson started with session ID: $sessionId');
      } catch (e) {
        debugPrint('Failed to start lesson: $e');
        // Show error to user
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text('Could not start lesson: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }
    
    // Now load the timeline if we have a session
    if (sessionId != null) {
      await _loadTimeline(sessionId);
    }
  }

  Future<void> _loadTimeline(int sessionId) async {
    try {
      final configService = Provider.of<AppConfigService>(context, listen: false);
      final api = TimelineApiService(baseUrl: configService.backendUrl);
      
      // Use generateTimeline instead of getSessionTimeline
      // generateTimeline will return cached timeline if exists, or generate a new one
      debugPrint('Generating/loading timeline for session $sessionId...');
      final timeline = await api.generateTimeline(sessionId);
      debugPrint('Timeline loaded: ${timeline.segments.length} segments');
      await _playbackController.loadTimeline(timeline);
      
      // Auto-start playback after loading
      debugPrint('Auto-starting lesson playback...');
      await _playbackController.play();
    } catch (e) {
      debugPrint('Failed to load timeline: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load lesson timeline: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _onLessonComplete() {
    widget.onLessonComplete?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    _playbackController.dispose();
    _textPromptController.dispose();
    _textXController.dispose();
    _textYController.dispose();
    _textSizeController.dispose();
    _imageNameController.dispose();
    _imageXController.dispose();
    _imageYController.dispose();
    _imageScaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final devMode = Provider.of<DeveloperModeProvider>(context);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.lessonContext?.title ?? 'Whiteboard'),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        foregroundColor: colorScheme.primary,
        elevation: 1,
        actions: [
          // Play/Pause button for timeline
          if (_playbackController.timeline != null)
            IconButton(
              icon: Icon(
                _playbackController.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              onPressed: () {
                if (_playbackController.isPlaying) {
                  _playbackController.pause();
                } else {
                  _playbackController.play();
                }
                setState(() {});
              },
            ),
          // Developer mode controls (only visible when dev mode is enabled)
          if (devMode.isEnabled)
            IconButton(
              icon: const Icon(Icons.developer_mode, color: Colors.orange),
              tooltip: 'Developer Controls',
              onPressed: () => _showDeveloperPanel(context),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return SafeArea(
            child: Column(
              children: [
                // Canvas
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: WhiteboardPainter(
                            staticStrokes: _controller.staticStrokes,
                            animStrokes: _controller.animStrokes,
                            animationT: _controller.animValue,
                            basePenWidth: 3.0,
                            stepMode: false,
                            stepStrokeCount: 0,
                            boardWidth: 2000.0,
                            boardHeight: 2000.0,
                            strokeColor: Colors.black,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),

                // Status bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? Colors.grey[850] : Colors.grey[200],
                  child: Text(
                    _controller.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),

                // Progress indicator for timeline
                if (_playbackController.timeline != null)
                  ListenableBuilder(
                    listenable: _playbackController,
                    builder: (context, _) {
                      final progress = _playbackController.totalDuration > 0
                          ? _playbackController.currentTime /
                              _playbackController.totalDuration
                          : 0.0;
                      return LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        selectedIndex: _navIndex,
        onDestinationSelected: (i) {
          setState(() => _navIndex = i);
          switch (i) {
            case 0:
              _showTextBottomSheet(context);
              break;
            case 1:
              if (devMode.isEnabled) {
                _showLoadImageSheet(context);
              } else {
                _controller.replayAnimation();
              }
              break;
            case 2:
              _showEraseBottomSheet(context);
              break;
            case 3:
              _controller.clear();
              break;
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.edit_outlined),
            label: 'Text',
          ),
          NavigationDestination(
            icon: Icon(devMode.isEnabled ? Icons.image_outlined : Icons.replay_outlined),
            label: devMode.isEnabled ? 'Image' : 'Replay',
          ),
          const NavigationDestination(
            icon: Icon(Icons.delete_outline),
            label: 'Erase',
          ),
          const NavigationDestination(
            icon: Icon(Icons.clear_all),
            label: 'Clear',
          ),
        ],
      ),
    );
  }

  void _showTextBottomSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: mq.viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Write Text',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _textPromptController,
                decoration: const InputDecoration(
                  labelText: 'Text',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textXController,
                      decoration: const InputDecoration(
                        labelText: 'X',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _textYController,
                      decoration: const InputDecoration(
                        labelText: 'Y',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _textSizeController,
                      decoration: const InputDecoration(
                        labelText: 'Size',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _addText();
                      },
                      child: const Text('Write'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _addText() {
    final text = _textPromptController.text.trim();
    if (text.isEmpty) return;

    final x = double.tryParse(_textXController.text) ?? 0.0;
    final y = double.tryParse(_textYController.text) ?? 0.0;
    final size = double.tryParse(_textSizeController.text) ?? 180.0;

    _controller.addText(
      text: text,
      origin: Offset(x, y),
      letterSize: size,
    );
  }

  void _showEraseBottomSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final names = _controller.drawnObjectNames;
        
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Erase Object',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (names.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nothing to erase'),
                )
              else
                ...names.map((name) => ListTile(
                  title: Text(name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _controller.eraseObject(name);
                    },
                  ),
                )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLoadImageSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: mq.viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.developer_mode, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Load Vector Image (Dev)',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _imageNameController,
                decoration: const InputDecoration(
                  labelText: 'File Name (e.g. triangle.json)',
                  border: OutlineInputBorder(),
                  helperText: 'JSON file from /api/wb/generate/vectors/',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _imageXController,
                      decoration: const InputDecoration(
                        labelText: 'X',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(signed: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _imageYController,
                      decoration: const InputDecoration(
                        labelText: 'Y',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(signed: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _imageScaleController,
                      decoration: const InputDecoration(
                        labelText: 'Scale',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _loadImage();
                      },
                      child: const Text('Load'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _loadImage() {
    final fileName = _imageNameController.text.trim();
    if (fileName.isEmpty) return;

    final x = double.tryParse(_imageXController.text) ?? 0.0;
    final y = double.tryParse(_imageYController.text) ?? 0.0;
    final scale = double.tryParse(_imageScaleController.text) ?? 1.0;

    _controller.addImage(
      fileName: fileName,
      origin: Offset(x, y),
      scale: scale,
    );
  }

  void _showDeveloperPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return _DeveloperPanel(
              controller: _controller,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }
}

/// Developer panel with timing controls (hidden by default)
class _DeveloperPanel extends StatefulWidget {
  final WhiteboardController controller;
  final ScrollController scrollController;

  const _DeveloperPanel({
    required this.controller,
    required this.scrollController,
  });

  @override
  State<_DeveloperPanel> createState() => _DeveloperPanelState();
}

class _DeveloperPanelState extends State<_DeveloperPanel> {
  late StrokeTimingConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.controller.timingConfig.copyWith();
  }

  void _updateConfig() {
    widget.controller.updateTimingConfig(_config);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: ListView(
        controller: widget.scrollController,
        children: [
          const Text(
            'Developer Controls',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          
          _buildSlider(
            'Global Speed',
            _config.globalSpeedMultiplier,
            0.25,
            3.0,
            (v) => setState(() {
              _config = _config.copyWith(globalSpeedMultiplier: v);
              _updateConfig();
            }),
          ),
          
          const SizedBox(height: 16),
          const Text('Stroke Timing', style: TextStyle(fontWeight: FontWeight.bold)),
          
          _buildSlider(
            'Min Stroke Time (s)',
            _config.minStrokeTimeSec,
            0.05,
            0.5,
            (v) => setState(() {
              _config = _config.copyWith(minStrokeTimeSec: v);
              _updateConfig();
            }),
          ),
          
          _buildSlider(
            'Max Stroke Time (s)',
            _config.maxStrokeTimeSec,
            0.1,
            1.0,
            (v) => setState(() {
              _config = _config.copyWith(maxStrokeTimeSec: v);
              _updateConfig();
            }),
          ),
          
          _buildSlider(
            'Length Factor (s/1000px)',
            _config.lengthTimePerKPxSec,
            0.0,
            0.3,
            (v) => setState(() {
              _config = _config.copyWith(lengthTimePerKPxSec: v);
              _updateConfig();
            }),
          ),
          
          _buildSlider(
            'Curvature Extra (s)',
            _config.curvatureExtraMaxSec,
            0.0,
            0.3,
            (v) => setState(() {
              _config = _config.copyWith(curvatureExtraMaxSec: v);
              _updateConfig();
            }),
          ),
          
          const SizedBox(height: 16),
          const Text('Travel Timing', style: TextStyle(fontWeight: FontWeight.bold)),
          
          _buildSlider(
            'Base Travel (s)',
            _config.baseTravelTimeSec,
            0.0,
            0.6,
            (v) => setState(() {
              _config = _config.copyWith(baseTravelTimeSec: v);
              _updateConfig();
            }),
          ),
          
          _buildSlider(
            'Travel per 1000px (s)',
            _config.travelTimePerKPxSec,
            0.0,
            0.4,
            (v) => setState(() {
              _config = _config.copyWith(travelTimePerKPxSec: v);
              _updateConfig();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(3)}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
