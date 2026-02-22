// lib/main.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import './providers/developer_mode_provider.dart';
// Local imports
import 'vectorizer.dart';
import 'services/backend_vectorizer.dart';
import 'assistant_api.dart';
import 'assistant_audio.dart';
import 'sdk_live_bridge.dart';
import 'planner.dart';
import 'models/timeline.dart';
import 'services/auth_service.dart';
import 'services/timeline_api.dart';
import 'controllers/timeline_playback_controller.dart';
import 'controllers/whiteboard_orchestrator.dart';
import 'services/lesson_pipeline_api.dart';
import 'services/app_config_service.dart';
import 'theme_provider.dart';
import 'pages/login.dart';
import 'pages/signup.dart';
import 'pages/home.dart';
import 'pages/lessons_page.dart';
import 'pages/settings_page.dart';
import 'pages/auth_gate.dart';
import 'pages/market_page.dart';
import 'pages/whiteboard_page.dart';
import 'pages/lesson_history_page.dart';

// Whiteboard module
import 'whiteboard/whiteboard.dart';
// UI widgets
import 'widgets/lesson_playback_bar.dart';
import 'widgets/lesson_completion_overlay.dart';
import 'widgets/developer_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/.env');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => DeveloperModeProvider()),
        ChangeNotifierProvider(create: (_) => AppConfigService()),
      ],
      child: const DrawnOutApp(),
    ),
  );
}

class DrawnOutApp extends StatelessWidget {
  const DrawnOutApp({super.key});

  ThemeData _buildTheme(bool dark, {bool highContrast = false}) {
    final base = dark ? ThemeData.dark() : ThemeData.light();
    var theme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: dark ? Colors.tealAccent.shade200 : Colors.blue,
        secondary: dark ? Colors.tealAccent : Colors.blueAccent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              dark ? Colors.tealAccent.shade200 : Colors.blueAccent,
          foregroundColor: dark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 3,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? Colors.tealAccent.shade200 : Colors.blue,
        ),
      ),
    );

    if (highContrast) {
      theme = theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          outline: dark ? Colors.white : Colors.black,
        ),
        dividerTheme: DividerThemeData(
          color: dark ? Colors.white54 : Colors.black54,
          thickness: 2,
        ),
      );
    }

    return theme;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DrawnOut',
      theme: _buildTheme(themeProvider.isDarkMode, highContrast: themeProvider.isHighContrast),
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignupPage(),
        '/home': (context) => const HomePage(),
        '/lessons': (context) => const LessonsPage(),
        '/settings': (context) => const SettingsPage(),
        '/market': (context) => const MarketPage(),
        '/history': (context) => const LessonHistoryPage(),
        '/whiteboard': (context) => const WhiteboardPageWrapper(),
        '/whiteboard/user': (context) =>
            const WhiteboardPageWrapper(startInDeveloperMode: false),
        '/whiteboard/dev': (context) =>
            const WhiteboardPageWrapper(startInDeveloperMode: true),
        '/whiteboard/mobile': (context) => const WhiteboardPageMobile(),
        '/whiteboard/legacy': (context) => const WhiteboardPageWrapper(),
      },
    );
  }
}

// Core classes (PlacedImage, StrokePlan, VectorObject), painters (SketchPainter,
// CommittedPainter), and SketchPlayer widget are now imported from whiteboard/whiteboard.dart

/// Whiteboard wrapper that extracts route arguments and passes them through.
class WhiteboardPageWrapper extends StatelessWidget {
  /// Parameter kept for backward compatibility but no longer used.
  final bool startInDeveloperMode;

  const WhiteboardPageWrapper({
    super.key,
    this.startInDeveloperMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // Extract lesson arguments if passed via route
    final args = ModalRoute.of(context)?.settings.arguments;
    String? topic;
    String? title;
    int? sessionId;
    bool rewatch = false;
    if (args is Map<String, dynamic>) {
      topic = args['topic'] as String?;
      title = args['title'] as String?;
      sessionId = args['session_id'] as int?;
      rewatch = (args['rewatch'] as bool?) ?? false;
    }
    return WhiteboardPage(
      autoStartTopic: topic,
      lessonTitle: title,
      autoStartSessionId: rewatch ? sessionId : null,
    );
  }
}

/// Developer whiteboard page with full controls.
class WhiteboardPage extends StatefulWidget {
  /// If set, auto-starts the synced lesson pipeline on this topic.
  final String? autoStartTopic;
  /// Display title for the lesson (shown in loading UI).
  final String? lessonTitle;
  /// If set, skips generation and replays a saved timeline for this session.
  final int? autoStartSessionId;

  const WhiteboardPage({
    super.key,
    this.autoStartTopic,
    this.lessonTitle,
    this.autoStartSessionId,
  });

  @override
  State<WhiteboardPage> createState() => _WhiteboardPageState();
}

class _WhiteboardPageState extends State<WhiteboardPage> {
  /// Single source of truth for the backend API base URL.  Reads from the
  /// .env file (API_URL) and falls back to 127.0.0.1:8000.
  static String get _defaultApiUrl =>
      (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();

  String get _effectiveBaseUrl {
    final text = _apiUrlCtrl.text.trim();
    return text.isEmpty ? _defaultApiUrl : text;
  }

  static const double canvasW = 1600; // fallback/default
  static const double canvasH = 1000; // fallback/default
  Size? _canvasSize; // live size from LayoutBuilder
  Size? _pendingCanvasSize;
  bool _canvasSizeUpdateScheduled = false;

  // Orchestrator for whiteboard business logic
  late final WhiteboardOrchestrator _orchestrator;

  // Services
  final _strokeService = const StrokeService();
  final _textSketchService = const TextSketchService();
  late ImageSketchService _imageSketchService;

  // Delegate board/plan/raster/busy to orchestrator
  List<VectorObject> get _board => _orchestrator.board;
  PlacedImage? get _raster => _orchestrator.raster;
  StrokePlan? get _plan => _orchestrator.plan;
  bool get _busy => _orchestrator.busy;

  set _raster(PlacedImage? value) => _orchestrator.raster = value;
  set _plan(StrokePlan? value) => _orchestrator.plan = value;
  set _busy(bool value) => _orchestrator.setBusy(value);

  Uint8List? get _uploadedBytes => _orchestrator.uploadedBytes;
  ui.Image? get _uploadedImage => _orchestrator.uploadedImage;
  DateTime?
      _currentAnimEnd; // when current sketch animation is expected to finish
  bool _diagramInFlight = false; // fetching or preparing diagram
  DateTime? _diagramAnimEnd; // when diagram animation is expected to finish

  final _xCtrl = TextEditingController(text: '0');
  final _yCtrl = TextEditingController(text: '0');
  final _wCtrl = TextEditingController(text: '800');
  final _textCtrl = TextEditingController(text: 'Hello world');

  // --- Vectorizer defaults mirrored in UI ---
  String _edgeMode = 'Canny';
  double _blurK = 5;
  double _cannyLo = 50; // match defaults
  double _cannyHi = 160;
  double _dogSigma = 1.2;
  double _dogK = 1.6;
  double _dogThresh = 6.0;
  double _epsilon = 1.1187500000000001;
  double _resample = 1.410714285714286;
  double _minPerim = 19.839285714285793;
  bool _externalOnly = false;
  double _worldScale = 1.0;

  // Playback/style (unchanged)
  double _seconds = 60;
  int _passes = 1;
  double _opacity = 0.8;
  double _width = 5;
  double _jitterAmp = 0;
  double _jitterFreq = 0.02;
  bool _showRasterUnder = true;
  bool _planUnderlay = true; // per-plan underlay toggle
  bool _debugAllowUnderDiagrams = false; // allow underlay for auto diagrams

  // Stroke shaping knobs (match defaults)
  double _angleThreshold = 30.0; // deg
  double _angleWindow = 4; // samples
  double _smoothPasses = 3; // 0..3
  bool _mergeParallel = true;
  double _mergeMaxDist = 12.0; // px/world
  double _minStrokeLen = 8.70; // px/world
  double _minStrokePoints = 6; // int

  bool _showDevPanel = false; // Toggle for developer panel visibility (requires is_developer flag)
  double _textFontSize = 60.0;
  // Assistant
  late final _apiUrlCtrl = TextEditingController(text: _defaultApiUrl);
  AssistantApiClient? _api;
  int? _sessionId;
  final _questionCtrl = TextEditingController();
  final _diagramCtrl =
      TextEditingController(text: 'Right triangle a,b,c with square on c');
  // handled by assistant_audio on each platform
  bool _inLive = false;
  bool _wantLive = false;
  Timer? _autoNextTimer;
  // Timeline playback (synchronized speech-drawing)
  TimelinePlaybackController? _timelineController;
  TimelineApiClient? _timelineApi;
  // Orchestrator
  final _actionsCtrl = TextEditingController(
      text:
          '{\n  "whiteboard_actions": [\n    { "type": "heading", "text": "Sample Topic" },\n    { "type": "bullet", "level": 1, "text": "Key idea one" },\n    { "type": "bullet", "level": 1, "text": "Key idea two" }\n  ]\n}');

  // Layout state for orchestrator
  LayoutState? get _layout => _orchestrator.layout;
  set _layout(LayoutState? value) => _orchestrator.layout = value;
  // Adjustable layout config (defaults match code below)
  double _cfgMarginTop = 60,
      _cfgMarginRight = 64,
      _cfgMarginBottom = 60,
      _cfgMarginLeft = 64;
  double _cfgLineHeight = 1.25, _cfgGutterY = 14;
  double _cfgIndent1 = 32, _cfgIndent2 = 64, _cfgIndent3 = 96;
  double _cfgHeading = 60, _cfgBody = 60, _cfgTiny = 60;
  int _cfgColumnsCount = 1;
  double _cfgColumnsGutter = 48;
  // Centerline controls
  double _clThreshold = 60.0; // px
  double _clEpsilon = 0.6; // simplify tighter
  double _clResample = 0.8; // denser sampling
  double _clMergeFactor = 0.9; // merge distance = factor * font
  double _clMergeMin = 12.0; // clamp
  double _clMergeMax = 36.0; // clamp
  double _clSmoothPasses = 3.0; // 0..4
  bool _preferOutlineHeadings = true; // headings keep double outline
  bool _sketchPreferOutline = false; // sketch text: default centerline
  // Planner limits (adjustable)
  double _plMaxItems = 3;
  double _plMaxSentences = 1;
  double _plMaxWords = 10;
  // Tutor draw overrides
  bool _tutorUseSpeed = true;
  double _tutorSeconds = 60;
  double _tutorFontScale = 1.0; // multiplies heading/body when planner draws
  bool _tutorUseFixedFont = true;
  double _tutorFixedFont = 72.0;
  double _tutorMinFont = 72.0; // hard floor for any tutor-drawn text

  // ── Auto-start lesson loading state ─────────────────────────────────────
  bool _lessonLoading = false;
  String _lessonLoadingStage = '';
  double _lessonLoadingProgress = 0.0;
  String? _lessonLoadingError;
  bool _lessonAutoStarted = false;
  bool _lessonComplete = false;

  /// True when the whiteboard was opened for a lesson (auto-start or rewatch),
  /// false when the user is just using the free-draw whiteboard.
  bool get _isInLessonSession =>
      widget.autoStartTopic != null || widget.autoStartSessionId != null;

  /// Tracks the last-known pause state so we only call setState on transitions.
  bool _drawingPaused = false;

  void _onTimelinePauseChanged() {
    final paused = _timelineController?.isPaused ?? false;
    if (paused != _drawingPaused && mounted) {
      setState(() { _drawingPaused = paused; });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  /// Sync UI vectorizer/layout config to orchestrator before calling its methods.
  void _syncVectorConfigToOrchestrator() {
    final v = _orchestrator.vectorConfig;
    v.edgeMode = _edgeMode;
    v.blurK = _blurK;
    v.cannyLo = _cannyLo;
    v.cannyHi = _cannyHi;
    v.dogSigma = _dogSigma;
    v.dogK = _dogK;
    v.dogThresh = _dogThresh;
    v.epsilon = _epsilon;
    v.resample = _resample;
    v.minPerim = _minPerim;
    v.externalOnly = _externalOnly;
    v.worldScale = _worldScale;
    v.angleThreshold = _angleThreshold;
    v.angleWindow = _angleWindow;
    v.smoothPasses = _smoothPasses;
    v.mergeParallel = _mergeParallel;
    v.mergeMaxDist = _mergeMaxDist;
    v.minStrokeLen = _minStrokeLen;
    v.minStrokePoints = _minStrokePoints;
  }

  void _syncCenterlineAndTutorToOrchestrator() {
    final c = _orchestrator.centerlineParams;
    c.threshold = _clThreshold;
    c.epsilon = _clEpsilon;
    c.resample = _clResample;
    c.mergeFactor = _clMergeFactor;
    c.mergeMin = _clMergeMin;
    c.mergeMax = _clMergeMax;
    c.smoothPasses = _clSmoothPasses;
    c.sketchPreferOutline = _sketchPreferOutline;
    c.preferOutlineHeadings = _preferOutlineHeadings;
    _orchestrator.tutorConfig.minFont = _tutorMinFont;
  }

  void _syncPlaybackConfigToOrchestrator() {
    final p = _orchestrator.playbackConfig;
    p.width = _width;
    p.opacity = _opacity;
    p.passes = _passes;
    p.jitterAmp = _jitterAmp;
    p.jitterFreq = _jitterFreq;
  }

  bool _devModeChecked = false;
  
  @override
  void initState() {
    super.initState();

    // Initialize image sketch service with default base URL
    _imageSketchService = ImageSketchService(
      baseUrl: _defaultApiUrl,
    );

    // Initialize whiteboard orchestrator with current backend URL
    _orchestrator = WhiteboardOrchestrator(baseUrl: _defaultApiUrl);
    // Rebuild this widget whenever orchestrator state changes
    _orchestrator.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    // Initialize timeline controller
    _timelineController = TimelinePlaybackController();
    // Only rebuild when pause state actually changes (not on every progress tick)
    _timelineController!.addListener(_onTimelinePauseChanged);
    _timelineController!.onDrawingActionsTriggered = (actions) async {
      await _handleSyncedDrawingActions(actions);
    };
    _timelineController!.onSegmentChanged = (index) {
      debugPrint('📍 Segment $index started');
      // Clear the canvas so each segment starts fresh
      _clearBoard();
    };
    _timelineController!.onTimelineCompleted = () {
      debugPrint('✅ Timeline completed!');
      if (mounted) setState(() => _lessonComplete = true);
      // Persist completion status in the backend
      _markSessionComplete();
    };
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_devModeChecked) {
      _devModeChecked = true;
      _checkDeveloperMode();
      
      // Rewatch mode: load a saved timeline directly (no generation step)
      if (!_lessonAutoStarted && widget.autoStartSessionId != null) {
        _lessonAutoStarted = true;
        Future.microtask(() => _rewatchLesson(widget.autoStartSessionId!));
      }
      // Auto-start lesson if topic was provided via route arguments
      else if (!_lessonAutoStarted && widget.autoStartTopic != null) {
        _lessonAutoStarted = true;
        // Delay slightly so the widget tree is fully built
        Future.microtask(() => _autoStartLesson(widget.autoStartTopic!));
      }
    }
  }
  
  Future<void> _checkDeveloperMode() async {
    final devProvider = Provider.of<DeveloperModeProvider>(context, listen: false);
    devProvider.setBaseUrl(_effectiveBaseUrl);
    
    final isDeveloper = await devProvider.refreshFromBackend();
    if (mounted) {
      setState(() {
        // Only show dev panel in debug builds AND for backend-verified developers
        _showDevPanel = kDebugMode && isDeveloper;
      });
    }

    // Mirror index.html end-of-segment behavior
    setAssistantOnQueueEmpty(() async {
      // If user pressed Raise Hand, start SDK live when the current segment ends
      if (_wantLive && !_inLive) {
        setState(() {
          _inLive = true;
        });
        await startSdkLive(oneTurn: false);
        return;
      }
      // Otherwise auto-advance only when all drawing completed (text + diagram)
      if (!_inLive && _sessionId != null && _api != null) {
        try {
          _autoNextTimer?.cancel();
        } catch (_) {}
        _autoNextTimer =
            Timer.periodic(const Duration(milliseconds: 250), (t) async {
          if (_canAdvanceSegment()) {
            t.cancel();
            try {
              final data = await _api!.nextSegment(_sessionId!);
              enqueueAssistantAudioFromSession(data);
            } catch (_) {}
          }
        });
      }
    });
  }

  bool _canAdvanceSegment() {
    final now = DateTime.now();
    final textDone = _currentAnimEnd == null || !_currentAnimEnd!.isAfter(now);
    final diagramDone =
        _diagramAnimEnd == null || !_diagramAnimEnd!.isAfter(now);
    final animInactive = _plan == null; // nothing currently animating
    return !_diagramInFlight && textDone && diagramDone && animInactive;
  }

  @override
  void dispose() {
    _timelineController?.removeListener(_onTimelinePauseChanged);
    _timelineController?.stop();
    _timelineController?.dispose();
    _xCtrl.dispose();
    _yCtrl.dispose();
    _wCtrl.dispose();
    _textCtrl.dispose();
    _apiUrlCtrl.dispose();
    _questionCtrl.dispose();
    _diagramCtrl.dispose();
    try {
      _autoNextTimer?.cancel();
    } catch (_) {}
    _actionsCtrl.dispose();
    disposeAssistantAudio();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showError('Could not load image data. Try a PNG or JPG.');
      return;
    }

    _busy = true;
    try {
      await _orchestrator.loadImageBytes(bytes);

      final x = double.tryParse(_xCtrl.text.trim()) ?? 0;
      final y = double.tryParse(_yCtrl.text.trim()) ?? 0;
      final w = (double.tryParse(_wCtrl.text.trim()) ?? 800)
          .clamp(1, 100000)
          .toDouble();

      if (_orchestrator.uploadedImage != null) {
        final img = _orchestrator.uploadedImage!;
        final aspect = img.height / img.width;
        final size = Size(w, w * aspect);
        _raster = PlacedImage(
            image: img, worldCenter: Offset(x, y), worldSize: size);
      }
      _plan = null;
    } finally {
      _busy = false;
    }
  }

  Future<void> _vectorizeAndSketch() async {
    if (_uploadedBytes == null || _uploadedBytes!.isEmpty) {
      _showError('Please upload an image first.');
      return;
    }
    _syncVectorConfigToOrchestrator();
    final x = double.tryParse(_xCtrl.text.trim()) ?? 0;
    final y = double.tryParse(_yCtrl.text.trim()) ?? 0;
    final w = (double.tryParse(_wCtrl.text.trim()) ?? 800).clamp(1, 100000).toDouble();
    try {
      await _orchestrator.vectorizeAndSketch(x: x, y: y, targetWidth: w);
      if (_orchestrator.lastError != null) {
        _showError(_orchestrator.lastError!);
      }
    } catch (e, st) {
      debugPrint('Vectorize error: $e\n$st');
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _fetchAndSketchDiagram() async {
    final prompt = _diagramCtrl.text.trim();
    if (prompt.isEmpty) {
      _showError('Enter a diagram prompt first.');
      return;
    }
    _busy = true;
    try {
      final base = _effectiveBaseUrl;
      final authService = AuthService(baseUrl: base);
      final diagramUrl =
          '${base.replaceAll(RegExp(r'/+$'), '')}/api/lessons/diagram/';
      final resp = await authService.authenticatedPost(diagramUrl,
          body: jsonEncode({'prompt': prompt}));
      if (resp.statusCode ~/ 100 != 2) {
        throw StateError('Diagram error: ${resp.statusCode}');
      }
      final body =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final b64 = (body['image_b64'] ?? body['image'] ?? '') as String;
      if (b64.isEmpty) throw StateError('Empty image data');
      final bytes = base64Decode(b64);

      await _orchestrator.loadImageBytes(bytes);
      final x = double.tryParse(_xCtrl.text.trim()) ?? 0;
      final y = double.tryParse(_yCtrl.text.trim()) ?? 0;
      final w = (double.tryParse(_wCtrl.text.trim()) ?? 800)
          .clamp(1, 100000)
          .toDouble();
      if (_orchestrator.uploadedImage != null) {
        final img = _orchestrator.uploadedImage!;
        final aspect = img.height / img.width;
        _raster = PlacedImage(
            image: img, worldCenter: Offset(x, y), worldSize: Size(w, w * aspect));
      }
      _syncVectorConfigToOrchestrator();
      await _orchestrator.vectorizeAndSketch(x: x, y: y, targetWidth: w);
      if (_orchestrator.lastError != null) {
        _showError(_orchestrator.lastError!);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _sketchText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _showError('Enter some text first.');
      return;
    }
    _syncCenterlineAndTutorToOrchestrator();
    try {
      await _orchestrator.sketchText(text, fontSize: _textFontSize);
      if (_orchestrator.lastError != null) {
        _showError(_orchestrator.lastError!);
      }
    } catch (e, st) {
      debugPrint('SketchText error: $e\n$st');
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // Commit the current animated sketch to the board memory.
  void _commitCurrentSketch() {
    if (_plan == null) return;
    _syncPlaybackConfigToOrchestrator();
    _orchestrator.commitCurrentSketch();
  }

  // ========== Whiteboard Orchestrator ==========
  Future<void> _ensureLayout() async {
    _layout ??= _makeLayout();
  }

  LayoutState _makeLayout() {
    final cfg = _buildLayoutConfigForSize(
        _canvasSize?.width ?? canvasW, _canvasSize?.height ?? canvasH);
    return LayoutState(
        config: cfg,
        cursorY: cfg.page.top,
        columnIndex: 0,
        blocks: <DrawnBlock>[],
        sectionCount: 0);
  }

  LayoutConfig _buildLayoutConfigForSize(double w, double h) {
    final columns = (_cfgColumnsCount <= 1)
        ? null
        : Columns(
            count: _cfgColumnsCount.clamp(1, 4), gutter: _cfgColumnsGutter);
    return LayoutConfig(
      page: PageConfig(
        width: w,
        height: h,
        top: _cfgMarginTop,
        right: _cfgMarginRight,
        bottom: _cfgMarginBottom,
        left: _cfgMarginLeft,
      ),
      lineHeight: _cfgLineHeight,
      gutterY: _cfgGutterY,
      indent:
          Indent(level1: _cfgIndent1, level2: _cfgIndent2, level3: _cfgIndent3),
      columns: columns,
      fonts: Fonts(heading: _cfgHeading, body: _cfgBody, tiny: _cfgTiny),
    );
  }

  Map<String, dynamic> _parseJsonSafe(String src) {
    try {
      return src.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(src) as Map<String, dynamic>);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _handleWhiteboardActions(
    List actions, {
    double fontScale = 1.0,
    double? overrideSeconds,
  }) async {
    // ── DEBUG: Log action breakdown ────────────────────────────────────────
    debugPrint('📥 Processing ${actions.length} whiteboard actions:');
    final actionTypes = <String, int>{};
    int sketchImageCount = 0;
    for (final a in actions) {
      if (a is! Map) continue;
      final type = (a['type'] ?? 'unknown').toString();
      actionTypes[type] = (actionTypes[type] ?? 0) + 1;
      if (type == 'sketch_image') sketchImageCount++;
    }
    for (final entry in actionTypes.entries) {
      debugPrint('   - ${entry.key}: ${entry.value}');
    }
    if (sketchImageCount > 0) {
      debugPrint('🖼️ Contains $sketchImageCount sketch_image action(s)');
    }
    // ── END DEBUG ──────────────────────────────────────────────────────────

    final accum = <List<Offset>>[];
    for (final a in actions) {
      if (a is! Map) continue;
      final type = (a['type'] ?? '').toString();

      // ── Handle sketch_image actions ──────────────────────────────────────
      if (type == 'sketch_image') {
        final imageUrl = a['image_url'] as String?;
        final imageBase64 = a['image_base64'] as String?;
        final placement = a['placement'] as Map<String, dynamic>?;
        final metadata = a['metadata'] as Map<String, dynamic>?;

        debugPrint('🖼️ Processing sketch_image action');
        await _sketchImageFromUrl(
          imageUrl: imageUrl,
          imageBase64: imageBase64,
          placement: placement,
          metadata: metadata,
          accum: accum,
        );
        continue; // Skip to next action
      }

      // ── Handle text-based actions (heading, bullet, formula, etc.) ───────
      final text = (a['text'] ?? '').toString();
      final level = (a['level'] is num) ? (a['level'] as num).toInt() : 1;
      final style = a['style'] as Map<String, dynamic>?;
      await _placeBlock(
        _layout!,
        type: type,
        text: text,
        level: level,
        style: style,
        accum: accum,
        fontScale: fontScale,
      );
    }
    if (accum.isNotEmpty) {
      setState(() {
        if (overrideSeconds != null) _seconds = overrideSeconds;
        _planUnderlay = true; // normal text honors UI underlay toggle
        _plan = StrokePlan(accum);
        _currentAnimEnd = DateTime.now()
            .add(Duration(milliseconds: (_seconds * 1000).round()));
      });
    }
  }

  Future<void> _runPlannerAndRender(Map<String, dynamic> sessionData) async {
    try {
      await _ensureLayout();
      final planner = WhiteboardPlanner(_effectiveBaseUrl);
      final plan = await planner.planForSession(
        sessionData,
        maxItems: _plMaxItems.round(),
        maxSentencesPerItem: _plMaxSentences.round(),
        maxWordsPerSentence: _plMaxWords.round(),
      );
      if (plan == null) {
        debugPrint(
            '⚠️ PLANNER RETURNED NULL - no whiteboard actions generated');
        return;
      }
      debugPrint('✅ Planner returned: $plan');
      // Use the draw-JSON feature directly (paste equivalent) by feeding actions into our drawer
      final actions = (plan['whiteboard_actions'] as List?) ?? const [];
      debugPrint('📝 Drawing ${actions.length} actions');
      // ensure we move below any previous content before drawing a new segment
      if (_layout != null && _layout!.blocks.isNotEmpty) {
        final maxBottom = _layout!.blocks
            .map((b) => b.bbox.bottom)
            .fold<double>(0.0, (a, b) => a > b ? a : b);
        final nextStart = maxBottom + _layout!.config.gutterY * 2.0;
        _layout!.cursorY = nextStart;
      }
      final seconds = _tutorUseSpeed ? _tutorSeconds : _seconds;
      final fs = _tutorUseFixedFont
          ? (_tutorFixedFont / _cfgHeading)
          : _tutorFontScale;
      // Kick off diagram generation immediately (do not await)
      try {
        final prompt = _diagramPromptFromPlanOrTopic(plan, sessionData);
        _startDiagramPipeline(prompt, seconds);
      } catch (e) {
        debugPrint('⚠️ Diagram pipeline error: $e');
      }
      await _handleWhiteboardActions(actions,
          fontScale: fs, overrideSeconds: seconds);
      debugPrint('✅ Finished drawing actions');
    } catch (e, st) {
      debugPrint('❌ ERROR in _runPlannerAndRender: $e');
      debugPrint('Stack: $st');
    }
  }

  // ========== Lesson Pipeline Methods ==========

  Future<void> _startLessonPipeline() async {
    setState(() {
      _busy = true;
    });

    try {
      debugPrint('🎨 Starting AI Lesson Pipeline with Images...');

      final baseUrl = _effectiveBaseUrl;
      final pipelineApi = LessonPipelineApi(baseUrl: baseUrl);

      // Show progress dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const AlertDialog(
            title: Text('🎨 Generating AI Lesson'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('This may take 60-150 seconds...'),
                SizedBox(height: 8),
                Text('1. Researching images (30-60s)',
                    style: TextStyle(fontSize: 12)),
                Text('2. Generating script (10-30s)',
                    style: TextStyle(fontSize: 12)),
                Text('3. Matching images (5-10s)',
                    style: TextStyle(fontSize: 12)),
                Text('4. Transforming images (30-90s)',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      }

      // Generate lesson
      final lesson = await pipelineApi.generateLesson(
        prompt: 'Explain the Pythagorean theorem',
        subject: 'Maths',
        durationTarget: 60.0,
      );

      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      debugPrint(
          '✅ Lesson generated: ${lesson.images.length} images, topic: ${lesson.topicId}');

      // Display lesson content with actual images
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('✅ Lesson Generated!'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Images: ${lesson.images.length}'),
                    Text('Indexed: ${lesson.indexedImageCount}'),
                    const SizedBox(height: 16),
                    const Text('Content Preview:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '${lesson.content.substring(0, math.min(300, lesson.content.length))}...',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    const Text('Generated Images:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...lesson.images.map((img) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                img.tag.prompt,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              if (img.tag.style != null)
                                Text(
                                  'Style: ${img.tag.style}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                              const SizedBox(height: 8),
                              // Display actual image
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  img.finalImageUrl,
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      height: 200,
                                      alignment: Alignment.center,
                                      child: CircularProgressIndicator(
                                        value: loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                            : null,
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 200,
                                      color: Colors.grey[300],
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.error_outline,
                                              color: Colors.red, size: 40),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Failed to load image',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700]),
                                          ),
                                          const SizedBox(height: 4),
                                          SelectableText(
                                            img.finalImageUrl,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.blue[700]),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const Divider(height: 16),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }

      setState(() {
        _busy = false;
      });
    } catch (e, st) {
      debugPrint('❌ Lesson pipeline error: $e\n$st');
      if (mounted) {
        // Close progress dialog if open
        try {
          Navigator.of(context).pop();
        } catch (_) {}
        _showError('Error: $e');
      }
      setState(() {
        _busy = false;
      });
    }
  }

  // ========== Synchronized Timeline Methods ==========

  Future<void> _startSynchronizedLesson() async {
    setState(() {
      _busy = true;
    });

    try {
      debugPrint('🎬 Starting synchronized lesson...');

      // Initialize APIs
      final baseUrl = _effectiveBaseUrl;
      _api = AssistantApiClient(baseUrl);
      _timelineApi = TimelineApiClient(baseUrl);
      _timelineController!.setBaseUrl(baseUrl);

      // 1. Start lesson session
      final data = await _api!.startLesson(topic: 'Pythagorean Theorem');
      _sessionId = data['id'] as int?;
      debugPrint('✅ Session created: $_sessionId');

      // 2. Generate timeline
      debugPrint('⏱️ Generating timeline... (this may take 30-60 seconds)');
      final timeline = await _timelineApi!
          .generateTimeline(_sessionId!, durationTarget: 60.0);
      debugPrint(
          '✅ Timeline generated: ${timeline.segments.length} segments, ${timeline.totalDuration}s');

      // 3. Load timeline into controller
      await _timelineController!.loadTimeline(timeline);

      // 4. Clear busy BEFORE starting playback so animations can render!
      setState(() {
        _busy = false;
      });

      // 5. Start playback
      debugPrint('▶️ Starting synchronized playback...');
      await _timelineController!.play();
    } catch (e, st) {
      debugPrint('❌ Synchronized lesson error: $e\n$st');
      _showError('Error: $e');
      setState(() {
        _busy = false;
      });
    }
  }

  /// Auto-start the synced lesson pipeline with a given topic.
  /// Called when the user navigates here from the home/lessons page with a topic.
  Future<void> _autoStartLesson(String topic) async {
    // Show image source popup at lesson start
    final useExistingImages = await _showImageSourceDialog();
    if (!mounted) return;
    if (useExistingImages == null) {
      Navigator.of(context).pop();
      return;
    }
    // Show TTS provider choice: Google or ElevenLabs
    final useElevenlabsTts = await _showTtsDialog();
    if (!mounted) return;
    if (useElevenlabsTts == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _lessonLoading = true;
      _lessonLoadingStage = 'Connecting to server...';
      _lessonLoadingProgress = 0.0;
    });

    try {
      debugPrint('🎬 Auto-starting lesson for topic: $topic, useExistingImages: $useExistingImages, useElevenlabsTts: $useElevenlabsTts');

      // Initialize APIs
      final baseUrl = _effectiveBaseUrl;
      _api = AssistantApiClient(baseUrl);
      _timelineApi = TimelineApiClient(baseUrl);
      _timelineController!.setBaseUrl(baseUrl);

      // Step 1: Create session
      setState(() {
        _lessonLoadingStage = 'Starting lesson session...';
        _lessonLoadingProgress = 0.15;
      });
      final data = await _api!.startLesson(
        topic: topic,
        useExistingImages: useExistingImages,
        useElevenlabsTts: useElevenlabsTts,
      );
      _sessionId = data['id'] as int?;
      debugPrint('✅ Session created: $_sessionId');

      if (!mounted) return;

      // Step 2: Generate timeline (this is the slow step)
      setState(() {
        _lessonLoadingStage = 'Generating lesson content...\nThis may take 30-60 seconds';
        _lessonLoadingProgress = 0.3;
      });
      
      // Animate progress while waiting
      final progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted && _lessonLoading && _lessonLoadingProgress < 0.85) {
          setState(() {
            _lessonLoadingProgress += 0.01;
          });
        }
      });

      final timeline = await _timelineApi!
          .generateTimeline(_sessionId!, durationTarget: 60.0);
      progressTimer.cancel();
      debugPrint('✅ Timeline generated: ${timeline.segments.length} segments');

      if (!mounted) return;

      // Step 3: Load timeline
      setState(() {
        _lessonLoadingStage = 'Preparing playback...';
        _lessonLoadingProgress = 0.9;
      });
      await _timelineController!.loadTimeline(timeline);

      if (!mounted) return;

      // Step 4: Clear loading, start playback
      setState(() {
        _lessonLoading = false;
        _lessonLoadingStage = '';
        _lessonLoadingProgress = 1.0;
      });

      debugPrint('▶️ Starting synchronized playback...');
      await _timelineController!.play();
    } catch (e, st) {
      debugPrint('❌ Auto-start lesson error: $e\n$st');
      if (mounted) {
        setState(() {
          _lessonLoadingStage = 'Failed to start lesson';
          _lessonLoadingError = e.toString();
        });
      }
    }
  }

  /// Shows a dialog at lesson start: use existing DB images vs start research.
  /// Returns true = use existing, false = start research, null = cancelled.
  Future<bool?> _showImageSourceDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.image_search, size: 28),
            SizedBox(width: 12),
            Text('Image Source'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose how to get images for this lesson:',
              style: TextStyle(fontSize: 15),
            ),
            SizedBox(height: 16),
            Text(
              '• Use existing images – Faster, uses images already in the database (if available).',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 8),
            Text(
              '• Start research – Searches and indexes new images (slower, but fresh results).',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.storage, size: 18),
            label: const Text('Use existing images'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Start research'),
          ),
        ],
      ),
    );
  }

  /// Shows a dialog at lesson start: Google TTS or ElevenLabs TTS.
  /// Returns true = ElevenLabs, false = Google, null = cancelled.
  Future<bool?> _showTtsDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.record_voice_over, size: 28),
            SizedBox(width: 12),
            Text('Voice (TTS)'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose text-to-speech provider:',
              style: TextStyle(fontSize: 15),
            ),
            SizedBox(height: 16),
            Text(
              '• Google Cloud TTS – Uses Google voices (requires GOOGLE_APPLICATION_CREDENTIALS).',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 8),
            Text(
              '• ElevenLabs – Uses your voice (Netanyahu + voice_id env vars).',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: const Icon(Icons.cloud, size: 18),
            label: const Text('Google TTS'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.voice_chat, size: 18),
            label: const Text('ElevenLabs'),
          ),
        ],
      ),
    );
  }

  /// Rewatch a previously completed lesson by loading its saved timeline.
  /// Skips session creation and timeline generation.
  Future<void> _rewatchLesson(int sessionId) async {
    setState(() {
      _lessonLoading = true;
      _lessonLoadingStage = 'Loading saved lesson...';
      _lessonLoadingProgress = 0.0;
      _lessonLoadingError = null;
    });

    try {
      debugPrint('🔁 Rewatching lesson session $sessionId');

      // Initialize APIs
      final baseUrl = _effectiveBaseUrl;
      _api = AssistantApiClient(baseUrl);
      _timelineApi = TimelineApiClient(baseUrl);
      _timelineController!.setBaseUrl(baseUrl);
      _sessionId = sessionId;

      if (!mounted) return;

      // Fetch saved timeline
      setState(() {
        _lessonLoadingStage = 'Fetching timeline data...';
        _lessonLoadingProgress = 0.4;
      });

      final timeline = await _timelineApi!.getSessionTimeline(sessionId);
      debugPrint('✅ Timeline loaded: ${timeline.segments.length} segments, ${timeline.totalDuration}s');

      if (!mounted) return;

      // Load into controller
      setState(() {
        _lessonLoadingStage = 'Preparing playback...';
        _lessonLoadingProgress = 0.8;
      });
      await _timelineController!.loadTimeline(timeline);

      if (!mounted) return;

      // Clear loading, start playback
      setState(() {
        _lessonLoading = false;
        _lessonLoadingStage = '';
        _lessonLoadingProgress = 1.0;
      });

      debugPrint('▶️ Starting rewatch playback...');
      await _timelineController!.play();
    } catch (e, st) {
      debugPrint('❌ Rewatch lesson error: $e\n$st');
      if (mounted) {
        setState(() {
          _lessonLoadingStage = 'Failed to load lesson';
          _lessonLoadingError = e.toString();
        });
      }
    }
  }

  /// Persist lesson completion on the backend so it shows as "Completed"
  /// in the history page.
  Future<void> _markSessionComplete() async {
    if (_sessionId == null) return;
    try {
      final baseUrl = _effectiveBaseUrl;
      final authService = AuthService(baseUrl: baseUrl);
      await authService.authenticatedPost(
        '$baseUrl/api/lessons/$_sessionId/complete/',
      );
      debugPrint('✅ Session $_sessionId marked as completed');
    } catch (e) {
      debugPrint('⚠️ Failed to mark session complete: $e');
    }
  }

  Future<void> _handleSyncedDrawingActions(List<DrawingAction> actions) async {
    if (actions.isEmpty) {
      debugPrint('💬 Explanatory segment - no drawing');
      return;
    }

    try {
      await _ensureLayout();

      // ── DEBUG: Log action breakdown from backend ─────────────────────────
      debugPrint('📥 Received ${actions.length} drawing actions from backend:');
      final actionTypes = <String, int>{};
      for (final a in actions) {
        actionTypes[a.type] = (actionTypes[a.type] ?? 0) + 1;
      }
      for (final entry in actionTypes.entries) {
        debugPrint('   - ${entry.key}: ${entry.value}');
      }

      // Separate sketch_image actions from text actions for duration calculation
      final textActions = actions.where((a) => !a.isSketchImage).toList();
      final imageActions = actions.where((a) => a.isSketchImage).toList();

      // Log sketch_image details if any
      if (imageActions.isNotEmpty) {
        debugPrint('🖼️ Found ${imageActions.length} sketch_image action(s):');
        for (final img in imageActions) {
          final url = img.resolvedImageUrl ?? 'no URL';
          final hasPlacement = img.placement != null;
          final hasBase64 =
              img.imageBase64 != null && img.imageBase64!.isNotEmpty;
          debugPrint(
              '   - ID: ${img.text.isEmpty ? "(no alt text)" : img.text.substring(0, img.text.length.clamp(0, 30))}');
          debugPrint(
              '     URL: ${url.length > 60 ? "${url.substring(0, 60)}..." : url}');
          debugPrint(
              '     Placement: ${hasPlacement ? "yes" : "auto"}, Base64 fallback: ${hasBase64 ? "yes" : "no"}');
        }
      }

      // Calculate total chars only from text actions
      final totalChars =
          textActions.fold<int>(0, (sum, a) => sum + a.text.length);

      // Drawing duration: MUCH SLOWER - match dictation pace for formulas
      final segment = _timelineController?.currentSegment;

      // Detect formula/dictation segments: short board text with longer speech
      final isDictationSegment = segment != null &&
          segment.actualAudioDuration > 5.0 &&
          totalChars < 50;

      // Add extra time for images (each image adds ~3s)
      final imageTime = imageActions.length * 3.0;

      final drawDuration = isDictationSegment
          ? (segment.actualAudioDuration * 0.85)
              .clamp(6.0, 25.0) // SLOW: match dictation pace
          : totalChars < 10
              ? 5.0 + imageTime // Even short words take 5s
              : totalChars < 20
                  ? 7.0 + imageTime // Medium takes 7s
                  : totalChars < 40
                      ? 10.0 + imageTime // Formulas take 10s
                      : totalChars < 80
                          ? 14.0 + imageTime // Lists take 14s
                          : 18.0 + imageTime; // Very long takes 18s

      debugPrint(
          '✍️ Drawing ${textActions.length} text + ${imageActions.length} image actions over ${drawDuration}s');

      // Generate strokes
      final accum = <List<Offset>>[];
      for (final action in actions) {
        // ── Handle sketch_image actions ────────────────────────────────────
        if (action.isSketchImage) {
          debugPrint('🖼️ Processing sketch_image action (synced)');
          await _sketchImageFromUrl(
            imageUrl: action.imageUrl,
            imageBase64: action.imageBase64,
            placement: action.placement,
            metadata: action.metadata,
            accum: accum,
          );
          continue; // Skip to next action
        }

        // ── Handle text-based actions ──────────────────────────────────────
        await _placeBlock(
          _layout!,
          type: action.type,
          text: action.text,
          level: action.level ?? 1,
          style: action.style,
          accum: accum,
          fontScale: _tutorFontScale,
        );
      }

      if (accum.isEmpty) {
        debugPrint('⚠️ No strokes generated');
        return;
      }

      // Set plan and animate
      setState(() {
        _seconds = drawDuration;
        _planUnderlay = false;
        _plan = StrokePlan(accum);
        _currentAnimEnd = DateTime.now()
            .add(Duration(milliseconds: (drawDuration * 1000).round()));
      });

      // Wait for animation — pause-aware: the timer only counts down while
      // playback is active, so pausing freezes both the SketchPlayer and this
      // countdown.
      final totalWaitMs = (drawDuration * 1000 * 0.95).round();
      var elapsedMs = 0;
      const tickMs = 100;
      while (elapsedMs < totalWaitMs) {
        await Future.delayed(const Duration(milliseconds: tickMs));
        // Only count time when not paused
        if (!(_timelineController?.isPaused ?? false)) {
          elapsedMs += tickMs;
        }
      }

      // Commit to board
      if (_plan != null) {
        _commitCurrentSketch();
        debugPrint('✅ Committed to board (total: ${_board.length})');
      }
    } catch (e) {
      debugPrint('❌ Drawing error: $e');
    }
  }

  String _diagramPromptFromPlanOrTopic(
      Map<String, dynamic> plan, Map<String, dynamic> sessionData) {
    final planHint = (plan['diagram_hint'] is String)
        ? (plan['diagram_hint'] as String).trim()
        : '';
    try {
      final actions = (plan['whiteboard_actions'] as List?) ?? const [];
      for (final a in actions) {
        if (a is Map && (a['type'] ?? '') == 'heading') {
          final t = (a['text'] ?? '').toString();
          if (t.isNotEmpty) {
            return _buildDiagramPrompt(t, sessionData, planHint);
          }
        }
      }
    } catch (_) {}
    return _buildDiagramPrompt(
        (sessionData['topic'] ?? 'diagram').toString(), sessionData, planHint);
  }

  String _buildDiagramPrompt(String topic, Map<String, dynamic> sessionData,
      [String? planHint]) {
    final sessionHint = _extractTutorDiagramHint(sessionData);
    final tutorHint = (planHint != null && planHint.trim().isNotEmpty)
        ? planHint.trim()
        : sessionHint;
    // If tutor provided explicit instructions, pass ONLY that text to the image model
    if (tutorHint.isNotEmpty) return tutorHint;
    // Fallback when no explicit instructions are available
    return ('Create a diagram that is as simple as possible while preserving meaning. Minimal black-and-white line art only; no shading, no colors, no textures, no background. Use only primitive shapes (straight lines, a single arrow if helpful, circles, triangles, rectangles). Hard limits: at most 12 strokes total; do not add dots, hatching, icons, or decorative details. Absolutely no letters, numbers, or text labels anywhere. Topic: $topic. Prefer the smallest, most uncluttered composition that conveys the core idea.');
  }

  String _extractTutorDiagramHint(Map<String, dynamic> sessionData) {
    // Try common fields that might carry tutor intent
    final keys = [
      'diagram_hint',
      'diagram',
      'image_hint',
      'image_request',
      'instructions',
      'note',
      'notes',
      'prompt'
    ];
    for (final k in keys) {
      final v = sessionData[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  void _startDiagramPipeline(String prompt, double currentSeconds) async {
    try {
      final base = _effectiveBaseUrl;
      final authService = AuthService(baseUrl: base);
      final diagramUrl =
          '${base.replaceAll(RegExp(r'/+$'), '')}/api/lessons/diagram/';
      final resp = await authService.authenticatedPost(
        diagramUrl,
        body: jsonEncode(
            {'prompt': prompt, 'size': '256x256', 'quality': 'standard'}),
      );
      if (resp.statusCode ~/ 100 != 2) {
        return;
      }
      final body =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final b64 = (body['image_b64'] ?? '') as String;
      if (b64.isEmpty) return;
      final bytes = base64Decode(b64);
      // Ensure we sketch after text plan finishes. If plan end is not yet known, wait briefly for it to be set.
      int tries = 0;
      while (_currentAnimEnd == null && tries < 20) {
        // up to ~1s
        await Future.delayed(const Duration(milliseconds: 50));
        tries++;
      }
      final end = _currentAnimEnd;
      if (end != null) {
        final now = DateTime.now();
        if (end.isAfter(now)) {
          await Future.delayed(end.difference(now));
        }
      }
      // Commit the finished text so it persists before drawing the diagram
      if (_plan != null) {
        _commitCurrentSketch();
      }
      await _sketchDiagramAuto(bytes);
    } catch (_) {
    } finally {
      _diagramInFlight = false;
    }
  }

  Future<void> _sketchDiagramAuto(List<int> bytes) async {
    await _ensureLayout();
    // Decode image to compute aspect and fit
    final img = await _decodeUiImage(Uint8List.fromList(bytes));
    final st = _layout!;
    final cfg = st.config;
    double contentX0 = cfg.page.left + st.columnOffsetX();
    double cw = st.columnWidth();
    // Keep diagrams compact
    double maxW = cw * 0.5;
    double x = contentX0 + (cw - maxW) / 2.0; // centered in column
    double y = st.cursorY;
    final pageBottom = cfg.page.height - cfg.page.bottom;
    // If not enough vertical space, try next column
    if ((pageBottom - y) < 100 &&
        cfg.columns != null &&
        st.columnIndex < (cfg.columns!.count - 1)) {
      st.columnIndex += 1;
      contentX0 = cfg.page.left + st.columnOffsetX();
      cw = st.columnWidth();
      maxW = cw * 0.5;
      x = contentX0 + (cw - maxW) / 2.0;
      y = cfg.page.top;
    }
    // Compute scale respecting remaining height
    final remainH = (cfg.page.height - cfg.page.bottom) - y - cfg.gutterY;
    final scaleW = (img.width == 0) ? 1.0 : (maxW / img.width);
    final scaleH =
        (img.height == 0) ? scaleW : math.max(0.1, remainH / img.height);
    final effScale = math.min(scaleW, scaleH);
    final targetW = img.width * effScale;
    final targetH = img.height * effScale;
    // push down to avoid overlaps with previous blocks
    y = _nextNonCollidingY(st, x, targetH, y);

    // Vectorize via backend when baseUrl set, else local
    final base = _effectiveBaseUrl;
    final strokes = base.isNotEmpty
        ? await BackendVectorizer.vectorize(
            baseUrl: base,
            bytes: Uint8List.fromList(bytes),
            worldScale: _worldScale,
            sourceWidth: img.width.toDouble(),
            sourceHeight: img.height.toDouble(),
          )
        : await Vectorizer.vectorize(
            bytes: Uint8List.fromList(bytes),
            worldScale: _worldScale,
            edgeMode: 'Canny',
            blurK: 3,
            cannyLo: 35.0,
            cannyHi: 140.0,
            epsilon: 0.9,
            resampleSpacing: 1.1,
            minPerimeter: math.max(20.0, _minPerim),
            retrExternalOnly: false,
            angleThresholdDeg: 85.0,
            angleWindow: 3,
            smoothPasses: 2,
            mergeParallel: true,
            mergeMaxDist: 14.0,
            minStrokeLen: 16.0,
            minStrokePoints: 10,
          );

    // Drop tiny decorative strokes (dots/specks) to keep result simple
    final filtered =
        _strokeService.filterStrokes(strokes, minLength: 24.0, minExtent: 8.0);

    // Scale to fit targetW while preserving aspect; vectorizer uses image px→world, so scale proportionally
    // Convert top-left content-space → world center, then add center offset
    final worldTopLeft =
        Offset(x - (cfg.page.width / 2), y - (cfg.page.height / 2));
    final centerOffset = Offset(targetW / 2.0, targetH / 2.0);
    final centerWorld = worldTopLeft + centerOffset;
    final placed = filtered
        .map((s) => s.map((p) => (p * effScale) + centerWorld).toList())
        .toList();

    // Update layout blocks to prevent future overlaps and advance cursor
    final bbox = BBox(x: x, y: y, w: targetW, h: targetH);
    st.blocks.add(DrawnBlock(
        id: 'img${st.blocks.length + 1}',
        type: 'diagram',
        bbox: bbox,
        meta: {'w': img.width, 'h': img.height}));
    st.cursorY = y + targetH + cfg.gutterY * 1.25;

    setState(() {
      _planUnderlay =
          _debugAllowUnderDiagrams; // show underlay only if debug enabled
      _plan = StrokePlan(placed);
      // also set raster to the placed image so it can be displayed under the sketch
      _raster = PlacedImage(
        image: img,
        worldCenter: centerWorld,
        worldSize: Size(targetW, targetH),
      );
      // Set diagram animation end time using current _seconds
      final now = DateTime.now();
      _diagramAnimEnd =
          now.add(Duration(milliseconds: (_seconds * 1000).round()));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sketch Image from URL (for sketch_image actions)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches an image from URL, vectorizes it, and adds strokes to [accum].
  ///
  /// This method is used by sketch_image drawing actions to render remote
  /// images as hand-drawn sketches on the whiteboard.
  ///
  /// Parameters:
  /// - [imageUrl]: The URL of the image to fetch and sketch
  /// - [placement]: Optional placement data with x, y, width, height, scale
  /// - [accum]: The stroke accumulator list to add generated strokes to
  /// - [metadata]: Optional metadata (may contain fallback URL, filename, etc.)
  /// - [imageBase64]: Optional base64-encoded image data as fallback
  ///
  /// Returns true if the image was successfully sketched, false otherwise.
  Future<bool> _sketchImageFromUrl({
    required String? imageUrl,
    Map<String, dynamic>? placement,
    required List<List<Offset>> accum,
    Map<String, dynamic>? metadata,
    String? imageBase64,
  }) async {
    await _ensureLayout();
    final st = _layout!;
    final cfg = st.config;

    // ── Step 1: Resolve the image URL ──────────────────────────────────────
    String? resolvedUrl = imageUrl;

    // Try metadata fallbacks if direct URL is empty
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      resolvedUrl =
          metadata?['image_url'] as String? ?? metadata?['url'] as String?;
    }

    // ── Step 2: Get image bytes ────────────────────────────────────────────
    Uint8List? imageBytes;

    // Try fetching from URL first
    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      try {
        // Use proxy for CORS safety on web
        final baseUrl = _effectiveBaseUrl;
        final api = LessonPipelineApi(baseUrl: baseUrl);
        final proxiedUrl = api.buildProxiedImageUrl(resolvedUrl);

        debugPrint('🖼️ Fetching image: $resolvedUrl');
        debugPrint('   Proxied URL: $proxiedUrl');

        final authService = AuthService(baseUrl: baseUrl);
        final response = await authService.authenticatedGet(proxiedUrl);

        if (response.statusCode == 200) {
          imageBytes = response.bodyBytes;
          debugPrint('   ✅ Fetched ${imageBytes.length} bytes');
        } else {
          debugPrint(
              '   ❌ HTTP ${response.statusCode}: ${response.reasonPhrase}');
        }
      } catch (e) {
        debugPrint('   ❌ Image fetch failed: $e');
      }
    }

    // Fallback to base64 if URL fetch failed
    if (imageBytes == null && imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        debugPrint('🖼️ Using base64 image fallback');
        imageBytes = base64Decode(imageBase64);
        debugPrint('   ✅ Decoded ${imageBytes.length} bytes from base64');
      } catch (e) {
        debugPrint('   ❌ Base64 decode failed: $e');
      }
    }

    // If we still have no image, give up gracefully
    if (imageBytes == null || imageBytes.isEmpty) {
      debugPrint('⚠️ No image data available, skipping sketch_image');
      return false;
    }

    // ── Step 3: Decode image to get dimensions ─────────────────────────────
    ui.Image img;
    try {
      img = await _decodeUiImage(imageBytes);
    } catch (e) {
      debugPrint('❌ Image decode failed: $e');
      return false;
    }

    // ── Step 4: Calculate placement ────────────────────────────────────────
    final p = placement ?? {};
    final hasExplicitPlacement = p.containsKey('x') && p.containsKey('y');

    double contentX0 = cfg.page.left + st.columnOffsetX();
    double cw = st.columnWidth();

    // Target dimensions
    double targetW, targetH;
    double x, y;

    if (hasExplicitPlacement) {
      // Use explicit placement from action. Support:
      // 1) normalized ratios (0..1), 2) pixel values authored for 1920x1080,
      // 3) direct pixel values in current canvas space.
      double px = (p['x'] as num?)?.toDouble() ?? contentX0;
      double py = (p['y'] as num?)?.toDouble() ?? st.cursorY;
      double pw = (p['width'] as num?)?.toDouble() ?? (cw * 0.4);
      double ph = (p['height'] as num?)?.toDouble() ??
          (pw * (img.height / math.max(1, img.width)));

      final isNormalized = px >= 0 &&
          px <= 1 &&
          py >= 0 &&
          py <= 1 &&
          pw > 0 &&
          pw <= 1.2 &&
          ph > 0 &&
          ph <= 1.2;
      if (isNormalized) {
        px *= cfg.page.width;
        py *= cfg.page.height;
        pw *= cfg.page.width;
        ph *= cfg.page.height;
      } else {
        final looksLike1920Space = px >= 0 &&
            py >= 0 &&
            pw > 0 &&
            ph > 0 &&
            px <= 1920 &&
            py <= 1080 &&
            pw <= 1920 &&
            ph <= 1080;
        if (looksLike1920Space &&
            (cfg.page.width != 1920 || cfg.page.height != 1080)) {
          px = (px / 1920.0) * cfg.page.width;
          py = (py / 1080.0) * cfg.page.height;
          pw = (pw / 1920.0) * cfg.page.width;
          ph = (ph / 1080.0) * cfg.page.height;
        }
      }

      x = px;
      y = py;
      targetW = pw;
      targetH = ph;

      // Apply scale if specified
      final scale = (p['scale'] as num?)?.toDouble();
      if (scale != null && scale > 0) {
        targetW *= scale;
        targetH *= scale;
      }

      // Keep explicit placement inside drawable page bounds.
      final maxW = math.max(80.0, cfg.page.width - cfg.page.left - cfg.page.right);
      final maxH = math.max(80.0, cfg.page.height - cfg.page.top - cfg.page.bottom);
      targetW = targetW.clamp(80.0, maxW).toDouble();
      targetH = targetH.clamp(80.0, maxH).toDouble();
      x = x.clamp(cfg.page.left, cfg.page.width - cfg.page.right - targetW).toDouble();
      y = y.clamp(cfg.page.top, cfg.page.height - cfg.page.bottom - targetH).toDouble();
    } else {
      // Auto-place: similar to _sketchDiagramAuto logic
      double maxW = cw * 0.4; // 40% of column width for images

      // Center horizontally in column
      x = contentX0 + (cw - maxW) / 2.0;
      y = st.cursorY;

      // Check for column overflow
      final pageBottom = cfg.page.height - cfg.page.bottom;
      if ((pageBottom - y) < 100 &&
          cfg.columns != null &&
          st.columnIndex < (cfg.columns!.count - 1)) {
        st.columnIndex += 1;
        contentX0 = cfg.page.left + st.columnOffsetX();
        cw = st.columnWidth();
        maxW = cw * 0.4;
        x = contentX0 + (cw - maxW) / 2.0;
        y = cfg.page.top;
      }

      // Scale to fit available space
      final remainH = (cfg.page.height - cfg.page.bottom) - y - cfg.gutterY;
      final scaleW = (img.width == 0) ? 1.0 : (maxW / img.width);
      final scaleH =
          (img.height == 0) ? scaleW : math.max(0.1, remainH / img.height);
      final effScale = math.min(scaleW, scaleH);

      targetW = img.width * effScale;
      targetH = img.height * effScale;

      // Avoid overlaps with previous blocks
      y = _nextNonCollidingY(st, x, targetH, y);
    }

    debugPrint('   📐 Placement: ($x, $y) size: ${targetW}x$targetH');

    // ── Step 5: Vectorize the image (backend when baseUrl set) ───────────────
    List<List<Offset>> strokes;
    try {
      final base = _effectiveBaseUrl;
      strokes = base.isNotEmpty
          ? await BackendVectorizer.vectorize(
              baseUrl: base,
              bytes: imageBytes,
              worldScale: _worldScale,
              sourceWidth: img.width.toDouble(),
              sourceHeight: img.height.toDouble(),
            )
          : await Vectorizer.vectorize(
              bytes: imageBytes,
              worldScale: _worldScale,
              edgeMode: 'Canny',
              blurK: 3,
              cannyLo: 35.0,
              cannyHi: 140.0,
              epsilon: 0.9,
              resampleSpacing: 1.1,
              minPerimeter: math.max(20.0, _minPerim),
              retrExternalOnly: false,
              angleThresholdDeg: 85.0,
              angleWindow: 3,
              smoothPasses: 2,
              mergeParallel: true,
              mergeMaxDist: 14.0,
              minStrokeLen: 16.0,
              minStrokePoints: 10,
            );
    } catch (e) {
      debugPrint('❌ Vectorization failed: $e');
      return false;
    }

    if (strokes.isEmpty) {
      debugPrint('⚠️ Vectorization produced no strokes');
      return false;
    }

    debugPrint('   ✏️ Vectorized: ${strokes.length} strokes');

    // ── Step 6: Filter and transform strokes ───────────────────────────────
    final filtered =
        _strokeService.filterStrokes(strokes, minLength: 24.0, minExtent: 8.0);

    // Calculate scale factor for strokes (image px → target size)
    final effScale = targetW / math.max(1, img.width);

    // Convert content-space to world-space and apply scaling
    final worldTopLeft = Offset(
      x - (cfg.page.width / 2),
      y - (cfg.page.height / 2),
    );
    final centerOffset = Offset(targetW / 2.0, targetH / 2.0);
    final centerWorld = worldTopLeft + centerOffset;

    final placedStrokes = filtered
        .map((s) => s.map((p) => (p * effScale) + centerWorld).toList())
        .toList();

    // ── Step 7: Update layout state ────────────────────────────────────────
    final bbox = BBox(x: x, y: y, w: targetW, h: targetH);
    st.blocks.add(DrawnBlock(
      id: 'sketch_img_${st.blocks.length + 1}',
      type: 'sketch_image',
      bbox: bbox,
      meta: {
        'w': img.width,
        'h': img.height,
        'url': resolvedUrl,
        if (metadata != null) ...metadata,
      },
    ));

    // Advance cursor for next content
    st.cursorY = y + targetH + cfg.gutterY * 1.25;

    // ── Step 8: Add strokes to accumulator ─────────────────────────────────
    accum.addAll(placedStrokes);

    debugPrint('   ✅ Added ${placedStrokes.length} strokes to accum');
    return true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DEBUG: Test sketch_image without backend
  // ─────────────────────────────────────────────────────────────────────────

  /// Injects a test sketch_image action to verify the image sketching pipeline.
  ///
  /// This method is only available in debug mode and allows testing the
  /// sketch_image functionality without requiring a backend connection.
  ///
  /// Uses a sample image from picsum.photos (placeholder image service).
  Future<void> _debugInjectSketchImage() async {
    if (!kDebugMode) return;

    debugPrint('🧪 DEBUG: Injecting test sketch_image action...');

    setState(() {
      _busy = true;
    });

    try {
      await _ensureLayout();

      // Sample test images (reliable placeholder services)
      final testImages = [
        'https://picsum.photos/400/300', // Random placeholder
        'https://via.placeholder.com/400x300/4a90d9/ffffff?text=Test+Image',
        'https://placehold.co/400x300/3498db/ffffff?text=Sketch+Test',
      ];

      // Pick a random test image
      final randomIndex = DateTime.now().millisecond % testImages.length;
      final testImageUrl = testImages[randomIndex];

      // Create test actions: heading + sketch_image + bullet
      final testActions = [
        {
          'type': 'heading',
          'text': '🧪 Debug: sketch_image Test',
        },
        {
          'type': 'sketch_image',
          'image_url': testImageUrl,
          'placement': {
            'x': null, // Let auto-placement handle it
            'y': null,
            'width': 300.0,
            'height': 225.0,
          },
          'metadata': {
            'source': 'debug_injection',
            'test': true,
          },
        },
        {
          'type': 'bullet',
          'text': 'Image rendered via sketch_image pipeline',
          'level': 1,
        },
      ];

      debugPrint('🧪 DEBUG: Processing ${testActions.length} test actions...');

      // Pass through normal action dispatcher
      await _handleWhiteboardActions(
        testActions,
        fontScale: _tutorFontScale,
        overrideSeconds: 8.0, // Longer duration to see the sketch
      );

      debugPrint('🧪 DEBUG: Test actions processed successfully!');
    } catch (e, st) {
      debugPrint('❌ DEBUG: Error injecting sketch_image: $e');
      debugPrint('Stack: $st');
      _showError('Debug error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  /// Injects a test with explicit placement coordinates
  Future<void> _debugInjectSketchImageWithPlacement() async {
    if (!kDebugMode) return;

    debugPrint('🧪 DEBUG: Injecting positioned sketch_image...');

    setState(() {
      _busy = true;
    });

    try {
      await _ensureLayout();

      final cfg = _layout!.config;

      // Create a positioned image action
      final testActions = [
        {
          'type': 'sketch_image',
          'image_url': 'https://picsum.photos/seed/drawnout/300/200',
          'placement': {
            'x': cfg.page.left + 50.0,
            'y': cfg.page.top + 50.0,
            'width': 250.0,
            'height': 167.0,
            'scale': 1.0,
          },
          'metadata': {
            'source': 'debug_positioned',
          },
        },
      ];

      await _handleWhiteboardActions(
        testActions,
        fontScale: 1.0,
        overrideSeconds: 6.0,
      );

      debugPrint('🧪 DEBUG: Positioned image processed!');
    } catch (e) {
      debugPrint('❌ DEBUG: Error: $e');
      _showError('Debug error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _placeBlock(
    LayoutState st, {
    required String type,
    required String text,
    int level = 1,
    Map<String, dynamic>? style,
    required List<List<Offset>> accum,
    double fontScale = 1.0,
  }) async {
    final cfg = st.config;
    final contentX0 = cfg.page.left + st.columnOffsetX();
    final contentW = st.columnWidth();

    double font = _chooseFont(type, cfg.fonts, style) * fontScale;
    if (_tutorUseFixedFont) font = _tutorFixedFont;
    if (font < _tutorMinFont) font = _tutorMinFont;
    final indent = _indentFor(type, level, cfg.indent);
    final maxWidth = (contentW - indent).clamp(80.0, contentW);
    final lines = _wrapText(text, font, maxWidth);
    final height = (lines.length * font * cfg.lineHeight).ceilToDouble();

    double x = contentX0 + indent;
    double y = st.cursorY;
    // clamp within content box
    if (x < contentX0) x = contentX0;
    final rightLimit = cfg.page.width - cfg.page.right;
    final maxX = rightLimit - 1.0;
    if (x > maxX) x = maxX;
    if (y < cfg.page.top) y = cfg.page.top;
    // collision/flow: push down if intersects
    y = _nextNonCollidingY(st, x, height, y);

    // overflow handling → new column/page
    if (y + height > (cfg.page.height - cfg.page.bottom)) {
      if (cfg.columns != null && st.columnIndex < (cfg.columns!.count - 1)) {
        st.columnIndex += 1;
        st.cursorY = cfg.page.top;
        await _placeBlock(st,
            type: type, text: text, level: level, style: style, accum: accum);
        return;
      } else {
        // new page: clear board and reset layout (simple approach)
        _board.clear();
        st.columnIndex = 0;
        st.cursorY = cfg.page.top;
        st.blocks.clear();
        st.sectionCount += 1;
        await _placeBlock(st,
            type: type, text: text, level: level, style: style, accum: accum);
        return;
      }
    }

    // draw via sketch-text pipeline for consistent handwriting vibe
    // Convert content-space (pixels from top-left of canvas) to world-space (origin center)
    final worldTopLeft =
        Offset(x - (cfg.page.width / 2), y - (cfg.page.height / 2));
    final preferOutline = (type == 'heading' || type == 'formula');
    final strokes = await _drawTextLines(lines, worldTopLeft, font,
        preferOutline: preferOutline);
    accum.addAll(strokes);

    final bbox = BBox(x: x, y: y, w: maxWidth, h: height);
    st.blocks.add(DrawnBlock(
        id: 'b${st.blocks.length + 1}',
        type: type,
        bbox: bbox,
        meta: {'level': level, 'text': text}));

    // advance cursor
    final extra = (type == 'heading') ? cfg.gutterY * 1.5 : cfg.gutterY;
    st.cursorY = y + height + extra;
  }

  Future<List<List<Offset>>> _drawTextLines(
      List<String> lines, Offset topLeftWorld, double fontSize,
      {bool preferOutline = false}) async {
    // Render each line as a text image → vectorize → place inside content box using top-left anchor
    final out = <List<Offset>>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      // Scale small fonts up for legibility and then scale back in world
      final scaleUp = fontSize < 24 ? (24.0 / fontSize) : 1.0;
      final rl = await _renderTextLine(line, fontSize * scaleUp);
      final centerlineMode = !preferOutline && fontSize < _clThreshold;
      final mergeDist = centerlineMode
          ? (fontSize * _clMergeFactor).clamp(_clMergeMin, _clMergeMax)
          : 10.0;
      final base = _effectiveBaseUrl;
      final strokes = base.isNotEmpty
          ? await BackendVectorizer.vectorize(
              baseUrl: base,
              bytes: rl.bytes,
              worldScale: _worldScale,
              sourceWidth: rl.w,
              sourceHeight: rl.h,
            )
          : await Vectorizer.vectorize(
              bytes: rl.bytes,
              worldScale: _worldScale,
              edgeMode: 'Canny',
              blurK: 3,
              cannyLo: 30,
              cannyHi: 120,
              dogSigma: _dogSigma,
              dogK: _dogK,
              dogThresh: _dogThresh,
              epsilon: centerlineMode ? _clEpsilon : 0.8,
              resampleSpacing: centerlineMode ? _clResample : 1.0,
              minPerimeter: (_minPerim * 0.6).clamp(6.0, 1e9),
              retrExternalOnly: false,
              angleThresholdDeg: 85,
              angleWindow: 3,
              smoothPasses: centerlineMode ? _clSmoothPasses.round() : 1,
              mergeParallel: true,
              mergeMaxDist: mergeDist,
              minStrokeLen: 4.0,
              minStrokePoints: 3,
            );
      final lineHeight = fontSize * 1.25;
      // Center-of-image placement: vectorizer returns strokes centered at (0,0) of the image
      final centerOffset = Offset(rl.w / 2.0, rl.h / 2.0);
      final offset = topLeftWorld + Offset(0, i * lineHeight) + centerOffset;
      // If we scaled up, scale down coordinates to match intended font size
      final placed = strokes
          .map((s) => s.map((p) => (p + offset) / scaleUp).toList())
          .toList();
      out.addAll(placed);
    }
    return out;
  }

  // Render a single line to PNG and return bytes with pixel size (used to convert top-left → center coords)
  Future<RenderedLine> _renderTextLine(String text, double fontSize) async {
    final style = const TextStyle(color: Colors.black);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 10.0;
    final w = (tp.width + pad * 2).ceil();
    final h = (tp.height + pad * 2).ceil();
    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = Colors.white);
    tp.paint(canvas, Offset(pad, pad));
    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return RenderedLine(
        bytes: data!.buffer.asUint8List(), w: w.toDouble(), h: h.toDouble());
  }

  double _chooseFont(String type, Fonts fonts, Map<String, dynamic>? style) {
    if (style != null && style['fontSize'] is num) {
      return (style['fontSize'] as num).toDouble();
    }
    if (type == 'heading') return fonts.heading;
    if (type == 'formula') return fonts.heading;
    return fonts.body;
  }

  double _indentFor(String type, int level, Indent indent) {
    if (type == 'bullet') {
      if (level <= 1) return indent.level1;
      if (level == 2) return indent.level2;
      return indent.level3;
    }
    if (type == 'subbullet') {
      if (level <= 1) return indent.level2;
      if (level == 2) return indent.level3;
      return indent.level3 + 24;
    }
    return 0.0;
  }

  List<String> _wrapText(String text, double fontSize, double maxWidth) {
    // crude heuristic by average char width (~0.58em)
    final avg = fontSize * 0.55;
    final maxChars = math.max(8, (maxWidth / avg).floor());
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var cur = '';
    for (final w in words) {
      if (cur.isEmpty) {
        cur = w;
        continue;
      }
      if ((cur.length + 1 + w.length) <= maxChars) {
        cur += ' $w';
      } else {
        lines.add(cur);
        cur = w;
      }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines;
  }

  double _nextNonCollidingY(LayoutState st, double x, double h, double startY) {
    double y = startY;
    while (true) {
      bool hit = false;
      double maxBottom = y;
      for (final b in st.blocks) {
        if (b.bbox.intersects(BBox(x: x, y: y, w: st.columnWidth(), h: h))) {
          maxBottom = math.max(maxBottom, b.bbox.bottom);
          hit = true;
        }
      }
      if (!hit) return y;
      y = maxBottom + st.config.gutterY;
      if (y > st.config.page.height - st.config.page.bottom) return y;
    }
  }

  // Stroke filtering and stitching are now handled by _strokeService
  // See whiteboard/services/stroke_service.dart

  void _clearBoard() {
    _orchestrator.clearBoard();
  }

  void _undoLast() {
    _orchestrator.undoLast();
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) => c.complete(img));
    return c.future;
  }

  @override
  Widget build(BuildContext context) {
    final rightPanel = _buildRightPanel(context);

    // We layer committed objects on TOP so we don't change your existing renderer.
    Widget buildCanvas(Size size) {
      // update layout page size to reflect live canvas
      _maybeUpdateCanvasSize(size);

      final baseCanvas = _busy
          ? const Center(child: CircularProgressIndicator())
          : (_plan == null
              ? CustomPaint(painter: RasterOnlyPainter(raster: _raster))
              : SketchPlayer(
                  plan: _plan!,
                  totalSeconds: _seconds,
                  baseWidth: _width,
                  passOpacity: _opacity,
                  passes: _passes,
                  jitterAmp: _jitterAmp,
                  jitterFreq: _jitterFreq,
                  showRasterUnderlay: _planUnderlay ? _showRasterUnder : false,
                  raster: _raster,
                  isPaused: _drawingPaused,
                ));

      return Stack(children: [
        // RepaintBoundary isolates the animating canvas from the committed
        // board layer so each can repaint independently (GPU optimisation).
        Positioned.fill(
          child: RepaintBoundary(child: baseCanvas),
        ),
        if (_board.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: CommittedPainter(_board)),
            ),
          ),
      ]);
    }

    // Responsive breakpoint — use portrait-friendly layout on narrow screens
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Main content — responsive: full canvas on mobile, Row with
            // optional dev panel on desktop/tablet.
            if (isMobile)
              // ── Portrait-first mobile layout ────────────────────────────
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    return buildCanvas(size);
                  },
                ),
              )
            else
              // ── Desktop / tablet layout ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size =
                            Size(constraints.maxWidth, constraints.maxHeight);
                        return buildCanvas(size);
                      },
                    ),
                  ),
                  // Toggle button for developer panel (debug builds + developer users only)
                  if (kDebugMode && Provider.of<DeveloperModeProvider>(context).isEnabled)
                    Container(
                      width: 32,
                      color: Colors.grey[100],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              _showDevPanel ? Icons.chevron_right : Icons.developer_mode,
                              color: Colors.grey[700],
                            ),
                            tooltip: _showDevPanel ? 'Hide Developer Panel' : 'Show Developer Panel',
                            onPressed: () => setState(() => _showDevPanel = !_showDevPanel),
                          ),
                        ],
                      ),
                    ),
                // Collapsible developer panel (only for developer users)
                if (kDebugMode && _showDevPanel && Provider.of<DeveloperModeProvider>(context).isEnabled)
                  DeveloperDashboard(child: rightPanel),
                ],
              ),
            
            // ── Lesson loading overlay ──────────────────────────────────────
            if (_lessonLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.white.withOpacity(0.95),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Animated icon (decorative)
                          ExcludeSemantics(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 1200),
                              curve: Curves.easeInOut,
                              builder: (context, value, child) {
                                return Transform.scale(
                                  scale: 0.8 + (value * 0.2),
                                  child: Opacity(
                                    opacity: 0.5 + (value * 0.5),
                                    child: child,
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.school,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          // Lesson title
                          if (widget.lessonTitle != null) ...[
                            Text(
                              widget.lessonTitle!,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                          ],
                          // Stage text
                          Text(
                            _lessonLoadingStage,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          // Progress bar
                          SizedBox(
                            width: 300,
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: LinearProgressIndicator(
                                    value: _lessonLoadingProgress,
                                    minHeight: 8,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation(
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${(_lessonLoadingProgress * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Error banner
                          if (_lessonLoadingError != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _lessonLoadingError!,
                                      style: const TextStyle(fontSize: 12, color: Colors.red),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          // Action buttons
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _lessonLoading = false;
                                    _lessonLoadingStage = '';
                                    _lessonLoadingProgress = 0.0;
                                    _lessonLoadingError = null;
                                  });
                                  Navigator.of(context).pop();
                                },
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Cancel'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.grey[600],
                                ),
                              ),
                              if (_lessonLoadingError != null) ...[
                                const SizedBox(width: 12),
                                FilledButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _lessonLoadingError = null;
                                      _lessonLoadingProgress = 0.0;
                                    });
                                    _autoStartLesson(widget.autoStartTopic ?? '');
                                  },
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
            // Floating buttons on the left side
            Positioned(
              left: 12,
              top: 12,
              child: Column(
                children: [
                  // Exit button
                  FloatingActionButton.small(
                    heroTag: 'exit',
                    tooltip: 'Exit',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close),
                  ),
                  const SizedBox(height: 8),
                  // Undo button
                  FloatingActionButton.small(
                    heroTag: 'undo',
                    tooltip: 'Undo last',
                    backgroundColor: Colors.white,
                    foregroundColor: _board.isEmpty ? Colors.grey : Colors.black87,
                    onPressed: _board.isEmpty ? null : _undoLast,
                    child: const Icon(Icons.undo),
                  ),
                  const SizedBox(height: 8),
                  // Clear button
                  FloatingActionButton.small(
                    heroTag: 'clear',
                    tooltip: 'Clear board',
                    backgroundColor: Colors.white,
                    foregroundColor: _board.isEmpty ? Colors.grey : Colors.black87,
                    onPressed: _board.isEmpty ? null : _clearBoard,
                    child: const Icon(Icons.delete_sweep),
                  ),
                  // Dev panel button on mobile (opens as bottom sheet, debug builds only)
                  if (kDebugMode && isMobile && Provider.of<DeveloperModeProvider>(context).isEnabled) ...[
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'devpanel',
                      tooltip: 'Developer Panel',
                      backgroundColor: Colors.orange[50],
                      foregroundColor: Colors.orange[800],
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => DraggableScrollableSheet(
                            initialChildSize: 0.7,
                            minChildSize: 0.3,
                            maxChildSize: 0.95,
                            expand: false,
                            builder: (context, scrollController) =>
                                SingleChildScrollView(
                              controller: scrollController,
                              child: rightPanel,
                            ),
                          ),
                        );
                      },
                      child: const Icon(Icons.developer_mode, size: 20),
                    ),
                  ],
                ],
              ),
            ),

            // ── Playback bar (bottom) — only during lesson sessions ────────
            if (_isInLessonSession && _timelineController?.timeline != null && !_lessonLoading && !_lessonComplete)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LessonPlaybackBar(controller: _timelineController!),
              ),

            // ── Lesson completion overlay — only during lesson sessions ───
            if (_isInLessonSession && _lessonComplete)
              Positioned.fill(
                child: LessonCompletionOverlay(
                  lessonTitle: widget.lessonTitle,
                  segmentsCompleted: _timelineController?.segmentCount ?? 0,
                  totalDurationSeconds: _timelineController?.totalDuration ?? 0.0,
                  onReplay: () {
                    setState(() => _lessonComplete = false);
                    _timelineController?.restart();
                  },
                  onExit: () {
                    setState(() => _lessonComplete = false);
                    Navigator.of(context).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _maybeUpdateCanvasSize(Size size) {
    final baseline = _pendingCanvasSize ?? _canvasSize;
    if (!_isMeaningfulSizeChange(baseline, size)) {
      return;
    }
    _pendingCanvasSize = size;
    if (_canvasSizeUpdateScheduled) return;

    _canvasSizeUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _canvasSizeUpdateScheduled = false;
      if (!mounted) return;

      final pending = _pendingCanvasSize;
      _pendingCanvasSize = null;
      if (pending == null || !_isMeaningfulSizeChange(_canvasSize, pending)) {
        return;
      }

      _canvasSize = pending;
      _orchestrator.setCanvasSize(pending);

      // Rebuild layout config for new page size while preserving cursor/blocks.
      final currentLayout = _layout;
      if (currentLayout == null) return;

      final newCfg = _buildLayoutConfigForSize(pending.width, pending.height);
      setState(() {
        _layout = LayoutState(
          config: newCfg,
          cursorY: currentLayout.cursorY
              .clamp(newCfg.page.top, newCfg.page.height - newCfg.page.bottom),
          columnIndex: 0,
          blocks: currentLayout.blocks, // keep drawn blocks references
          sectionCount: currentLayout.sectionCount,
        );
      });
    });
  }

  bool _isMeaningfulSizeChange(Size? prev, Size next) {
    if (prev == null) return true;
    return (prev.width - next.width).abs() >= 1 ||
        (prev.height - next.height).abs() >= 1;
  }

  Widget _buildRightPanel(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: ListView(
        children: [
          Text('Source', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.upload),
                  label: const Text('Upload Image'),
                ),
              ),
            ],
          ),
          // ── DEBUG: Test sketch_image (only in debug mode) ──────────────
          if (kDebugMode) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange.shade300, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.orange.shade50,
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bug_report,
                          color: Colors.orange.shade700, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        'DEBUG: sketch_image',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _debugInjectSketchImage,
                          icon: const Icon(Icons.image, size: 16),
                          label: const Text('Auto-Place',
                              style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade100,
                            foregroundColor: Colors.orange.shade900,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy
                              ? null
                              : _debugInjectSketchImageWithPlacement,
                          icon: const Icon(Icons.place, size: 16),
                          label: const Text('Positioned',
                              style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade100,
                            foregroundColor: Colors.orange.shade900,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          // ── END DEBUG ──────────────────────────────────────────────────
          const SizedBox(height: 16),
          const Divider(height: 24),
          Text('Orchestrator Layout', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Heading size', 18, 72, _cfgHeading,
              (v) => setState(() => _cfgHeading = v)),
          _slider('Body size', 14, 48, _cfgBody,
              (v) => setState(() => _cfgBody = v)),
          _slider(
              'Line height',
              1.0,
              1.8,
              _cfgLineHeight,
              (v) => setState(
                  () => _cfgLineHeight = double.parse(v.toStringAsFixed(2)))),
          _slider('Gutter Y', 4, 40, _cfgGutterY,
              (v) => setState(() => _cfgGutterY = v)),
          _slider('Indent L1', 16, 120, _cfgIndent1,
              (v) => setState(() => _cfgIndent1 = v)),
          _slider('Indent L2', 32, 180, _cfgIndent2,
              (v) => setState(() => _cfgIndent2 = v)),
          _slider('Indent L3', 48, 240, _cfgIndent3,
              (v) => setState(() => _cfgIndent3 = v)),
          _slider('Margin Top', 0, 200, _cfgMarginTop,
              (v) => setState(() => _cfgMarginTop = v)),
          _slider('Margin Right', 0, 200, _cfgMarginRight,
              (v) => setState(() => _cfgMarginRight = v)),
          _slider('Margin Bottom', 0, 200, _cfgMarginBottom,
              (v) => setState(() => _cfgMarginBottom = v)),
          _slider('Margin Left', 0, 200, _cfgMarginLeft,
              (v) => setState(() => _cfgMarginLeft = v)),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _cfgColumnsCount,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 column')),
                  DropdownMenuItem(value: 2, child: Text('2 columns')),
                ],
                onChanged: (v) => setState(() => _cfgColumnsCount = v ?? 1),
                decoration: const InputDecoration(labelText: 'Columns'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: _slider('Col. gutter', 0, 120, _cfgColumnsGutter,
                    (v) => setState(() => _cfgColumnsGutter = v))),
          ]),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() {
                          _board.clear();
                          _plan = null;
                          _layout = _makeLayout();
                        });
                      },
                icon: const Icon(Icons.settings_backup_restore),
                label: const Text('Apply Layout (clear page)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() {
                          if (_layout != null) {
                            _layout!.cursorY = _layout!.config.page.top;
                          }
                        });
                      },
                icon: const Icon(Icons.vertical_align_top),
                label: const Text('Reset Cursor'),
              ),
            ),
          ]),
          const Divider(height: 24),
          Text('Planner Limits', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Max items per plan', 1, 5, _plMaxItems,
              (v) => setState(() => _plMaxItems = v),
              divisions: 4, display: (v) => v.toStringAsFixed(0)),
          _slider('Max sentences per item', 1, 3, _plMaxSentences,
              (v) => setState(() => _plMaxSentences = v),
              divisions: 2, display: (v) => v.toStringAsFixed(0)),
          _slider('Max words per sentence', 4, 16, _plMaxWords,
              (v) => setState(() => _plMaxWords = v),
              divisions: 12, display: (v) => v.toStringAsFixed(0)),
          const Divider(height: 24),
          Text('Tutor Draw Overrides', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _tutorUseSpeed,
            onChanged: (v) => setState(() => _tutorUseSpeed = v),
            title: const Text('Override draw speed for tutor'),
            dense: true,
          ),
          _slider('Tutor total time (s)', 5, 120, _tutorSeconds,
              (v) => setState(() => _tutorSeconds = v),
              divisions: 23, display: (v) => '${v.toStringAsFixed(0)}s'),
          SwitchListTile(
            value: _tutorUseFixedFont,
            onChanged: (v) => setState(() => _tutorUseFixedFont = v),
            title: const Text('Use fixed font size for tutor'),
            dense: true,
          ),
          if (_tutorUseFixedFont)
            _slider(
                'Tutor fixed font (px)',
                36,
                120,
                _tutorFixedFont,
                (v) => setState(() =>
                    _tutorFixedFont = v < _tutorMinFont ? _tutorMinFont : v),
                divisions: 84,
                display: (v) => v.toStringAsFixed(0))
          else
            _slider(
                'Tutor font scale',
                0.5,
                2.0,
                _tutorFontScale,
                (v) => setState(() =>
                    _tutorFontScale = double.parse(v.toStringAsFixed(2)))),
          _slider('Tutor min font (px, hard floor)', 36, 120, _tutorMinFont,
              (v) => setState(() => _tutorMinFont = v),
              divisions: 84, display: (v) => v.toStringAsFixed(0)),
          const Divider(height: 24),
          Text('Centerline (Body Text)', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Centerline threshold (px)', 20, 120, _clThreshold,
              (v) => setState(() => _clThreshold = v)),
          _slider(
              'Centerline epsilon',
              0.3,
              1.2,
              _clEpsilon,
              (v) => setState(
                  () => _clEpsilon = double.parse(v.toStringAsFixed(2)))),
          _slider(
              'Centerline resample',
              0.5,
              1.5,
              _clResample,
              (v) => setState(
                  () => _clResample = double.parse(v.toStringAsFixed(2)))),
          _slider(
              'Merge factor',
              0.3,
              1.6,
              _clMergeFactor,
              (v) => setState(
                  () => _clMergeFactor = double.parse(v.toStringAsFixed(2)))),
          Row(children: [
            Expanded(
                child: _slider('Merge min', 4, 40, _clMergeMin,
                    (v) => setState(() => _clMergeMin = v))),
            const SizedBox(width: 8),
            Expanded(
                child: _slider('Merge max', 8, 60, _clMergeMax,
                    (v) => setState(() => _clMergeMax = v))),
          ]),
          _slider('Smooth passes', 0, 4, _clSmoothPasses,
              (v) => setState(() => _clSmoothPasses = v),
              divisions: 4, display: (v) => v.toStringAsFixed(0)),
          SwitchListTile(
            value: _preferOutlineHeadings,
            onChanged: (v) => setState(() => _preferOutlineHeadings = v),
            title: const Text('Headings keep outline (double stroke)'),
            dense: true,
          ),
          const Divider(height: 24),
          Text('Whiteboard Orchestrator', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _actionsCtrl,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Paste actions JSON',
              hintText:
                  '{ "whiteboard_actions": [ {"type":"heading","text":"..."} ] }',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                        });
                        try {
                          await _ensureLayout();
                          final map = _parseJsonSafe(_actionsCtrl.text.trim());
                          final list =
                              (map['whiteboard_actions'] as List?) ?? const [];
                          await _handleWhiteboardActions(list);
                        } catch (e) {
                          _showError(e.toString());
                        } finally {
                          if (mounted) {
                            setState(() {
                              _busy = false;
                            });
                          }
                        }
                      },
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Render Actions'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() {
                          _layout = null;
                          _board.clear();
                          _plan = null;
                        });
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Clear & Reset Layout'),
              ),
            ),
          ]),
          const Divider(height: 24),
          Text('AI Tutor', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _apiUrlCtrl,
            decoration: const InputDecoration(
                labelText: 'Backend URL (e.g. http://localhost:8000)'),
          ),
          const SizedBox(height: 8),
          // NEW: Lesson Pipeline with Intelligent Images
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _startLessonPipeline,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('🎨 AI LESSON with Images'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Synchronized Timeline Lesson
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _startSynchronizedLesson,
                icon: const Icon(Icons.sync),
                label: const Text('🎯 SYNCHRONIZED Lesson'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                        });
                        try {
                          debugPrint('🎬 Starting lesson...');
                          _api = AssistantApiClient(_apiUrlCtrl.text.trim());
                          setAssistantAudioBaseUrl(_apiUrlCtrl.text.trim());
                          final data = await _api!
                              .startLesson(topic: 'Handwriting practice');
                          debugPrint('✅ Got session data: $data');
                          _sessionId = data['id'] as int?;
                          debugPrint('📢 Enqueueing audio...');
                          enqueueAssistantAudioFromSession(data);
                          debugPrint('🎨 Running planner and render...');
                          await _runPlannerAndRender(data);
                          setState(() {
                            _inLive = false;
                            _wantLive = false;
                          });
                        } catch (e, st) {
                          debugPrint('❌ Start lesson error: $e');
                          debugPrint('Stack: $st');
                          _showError(e.toString());
                        } finally {
                          setState(() {
                            _busy = false;
                          });
                        }
                      },
                icon: const Icon(Icons.play_circle),
                label: const Text('Start Lesson (Old)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy || _sessionId == null
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                        });
                        try {
                          final data = await _api!.nextSegment(_sessionId!);
                          enqueueAssistantAudioFromSession(data);
                          await _runPlannerAndRender(data);
                          setState(() {
                            _inLive = false;
                            _wantLive = false;
                          });
                        } catch (e) {
                          _showError(e.toString());
                        } finally {
                          setState(() {
                            _busy = false;
                          });
                        }
                      },
                icon: const Icon(Icons.skip_next),
                label: const Text('Next'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _questionCtrl,
            decoration: const InputDecoration(labelText: 'Ask a question'),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _sessionId == null
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                        });
                        try {
                          final data = await _api!.raiseHand(_sessionId!,
                              question: _questionCtrl.text.trim());
                          enqueueAssistantAudioFromSession(data);
                          // Do not start live immediately; mirror template: start at end of current segment
                          setState(() {
                            _wantLive = true;
                          });
                          await _runPlannerAndRender(data);
                        } catch (e) {
                          _showError(e.toString());
                        } finally {
                          setState(() {
                            _busy = false;
                          });
                        }
                      },
                icon: const Icon(Icons.record_voice_over),
                label: const Text('Ask'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy || _sessionId == null || _inLive
                    ? null
                    : () async {
                        // Raise hand for live: start live when current segment ends
                        setState(() {
                          _wantLive = true;
                        });
                        try {
                          _autoNextTimer?.cancel();
                        } catch (_) {}
                      },
                icon: const Icon(Icons.back_hand),
                label: const Text('Raise Hand (Live)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || !_inLive || _sessionId == null
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                        });
                        try {
                          await stopSdkLive();
                          setState(() {
                            _inLive = false;
                            _wantLive = false;
                          });
                          if (_api != null && _sessionId != null) {
                            final data = await _api!.nextSegment(_sessionId!);
                            enqueueAssistantAudioFromSession(data);
                          }
                        } catch (e) {
                          _showError(e.toString());
                        } finally {
                          setState(() {
                            _busy = false;
                          });
                        }
                      },
                icon: const Icon(Icons.stop_circle),
                label: const Text('Stop Live & Next'),
              ),
            ),
          ]),
          const Divider(height: 24),
          Text('Text', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            decoration: const InputDecoration(labelText: 'Enter text'),
          ),
          _slider('Font size (px)', 20.0, 400.0, _textFontSize,
              (v) => setState(() => _textFontSize = v)),
          SwitchListTile(
            value: _sketchPreferOutline,
            onChanged: (v) => setState(() => _sketchPreferOutline = v),
            title: const Text('Prefer outline for Sketch Text'),
            dense: true,
          ),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _sketchText,
                icon: const Icon(Icons.draw),
                label: const Text('Sketch Text'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Placement (world coords, origin center)',
              style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _numField(_xCtrl, 'X')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_yCtrl, 'Y')),
            ],
          ),
          const SizedBox(height: 8),
          _numField(_wCtrl, 'Width'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || _uploadedImage == null
                      ? null
                      : () {
                          final x = double.tryParse(_xCtrl.text.trim()) ?? 0;
                          final y = double.tryParse(_yCtrl.text.trim()) ?? 0;
                          final w = (double.tryParse(_wCtrl.text.trim()) ?? 800)
                              .clamp(1, 100000)
                              .toDouble();
                          if (_uploadedImage != null) {
                            final aspect =
                                _uploadedImage!.height / _uploadedImage!.width;
                            final size = Size(w, w * aspect);
                            setState(() {
                              _raster = PlacedImage(
                                  image: _uploadedImage!,
                                  worldCenter: Offset(x, y),
                                  worldSize: size);
                            });
                          }
                        },
                  icon: const Icon(Icons.my_location),
                  label: const Text('Apply Placement'),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Text('Diagram (gpt-image-1)', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _diagramCtrl,
            decoration:
                const InputDecoration(labelText: 'Describe image (prompt)'),
          ),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _fetchAndSketchDiagram,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Sketch Diagram'),
              ),
            ),
          ]),
          const Divider(height: 24),

          Text('Vectorization', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _edgeMode,
            items: const [
              DropdownMenuItem(value: 'Canny', child: Text('Canny')),
              DropdownMenuItem(
                  value: 'DoG', child: Text('DoG (Difference of Gaussians)')),
            ],
            onChanged:
                _busy ? null : (v) => setState(() => _edgeMode = v ?? 'Canny'),
            decoration: const InputDecoration(labelText: 'Edge Mode'),
          ),
          const SizedBox(height: 8),

          _slider('Gaussian ksize', 3, 13, _blurK,
              (v) => setState(() => _blurK = v.roundToDouble()),
              divisions: 5, display: (v) => v.round().toString()),
          if (_edgeMode == 'Canny') ...[
            _slider('Canny low', 10, 200, _cannyLo,
                (v) => setState(() => _cannyLo = v),
                divisions: 19),
            _slider('Canny high', 40, 300, _cannyHi,
                (v) => setState(() => _cannyHi = v),
                divisions: 26),
          ] else ...[
            _slider('DoG sigma', 0.6, 3.0, _dogSigma,
                (v) => setState(() => _dogSigma = v)),
            _slider('DoG k (sigma2 = k*sigma)', 1.2, 2.2, _dogK,
                (v) => setState(() => _dogK = v)),
            _slider('DoG threshold', 1.0, 30.0, _dogThresh,
                (v) => setState(() => _dogThresh = v)),
          ],
          _slider('Simplify epsilon (px)', 0.5, 6.0, _epsilon,
              (v) => setState(() => _epsilon = v)),
          _slider('Resample spacing (px)', 1.0, 6.0, _resample,
              (v) => setState(() => _resample = v)),
          _slider('Min perimeter (px)', 10.0, 300.0, _minPerim,
              (v) => setState(() => _minPerim = v)),
          _slider('World scale (px → world)', 0.3, 3.0, _worldScale,
              (v) => setState(() => _worldScale = v)),
          SwitchListTile(
            value: _externalOnly,
            onChanged: _busy ? null : (v) => setState(() => _externalOnly = v),
            title: const Text('External contours only'),
            dense: true,
          ),

          const Divider(height: 24),
          Text('Stroke shaping', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Angle threshold (deg)', 0.0, 90.0, _angleThreshold,
              (v) => setState(() => _angleThreshold = v),
              divisions: 90, display: (v) => v.toStringAsFixed(0)),
          _slider('Angle window (samples)', 1, 6, _angleWindow,
              (v) => setState(() => _angleWindow = v),
              divisions: 5, display: (v) => v.toStringAsFixed(0)),
          _slider('Smoothing passes', 0, 3, _smoothPasses,
              (v) => setState(() => _smoothPasses = v.roundToDouble()),
              divisions: 3, display: (v) => v.toStringAsFixed(0)),
          SwitchListTile(
            value: _mergeParallel,
            onChanged: (v) => setState(() => _mergeParallel = v),
            title: const Text('Merge parallel outlines'),
            dense: true,
          ),
          _slider('Merge max distance', 1.0, 12.0, _mergeMaxDist,
              (v) => setState(() => _mergeMaxDist = v)),
          _slider('Min stroke length', 4.0, 60.0, _minStrokeLen,
              (v) => setState(() => _minStrokeLen = v)),
          _slider('Min stroke points', 2, 20, _minStrokePoints,
              (v) => setState(() => _minStrokePoints = v),
              divisions: 18, display: (v) => v.toStringAsFixed(0)),

          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed:
                _busy || _uploadedBytes == null ? null : _vectorizeAndSketch,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Vectorize & Draw'),
          ),

          // NEW: Board actions
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _plan == null ? null : _commitCurrentSketch,
                icon: const Icon(Icons.push_pin),
                label: const Text('Commit current sketch'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _board.isEmpty ? null : _undoLast,
                icon: const Icon(Icons.undo),
                label: const Text('Undo last'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _board.isEmpty ? null : _clearBoard,
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Clear board'),
              ),
            ),
          ]),

          const Divider(height: 24),
          Text('Playback / Texture', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Total time (s)', 1.0, 30.0, _seconds,
              (v) => setState(() => _seconds = v),
              divisions: 29, display: (v) => '${v.toStringAsFixed(0)}s'),
          _slider('Base width', 0.5, 8.0, _width,
              (v) => setState(() => _width = v)),
          _slider('Passes', 1, 4, _passes.toDouble(),
              (v) => setState(() => _passes = v.round()),
              divisions: 3, display: (v) => v.round().toString()),
          _slider('Pass opacity', 0.2, 1.0, _opacity,
              (v) => setState(() => _opacity = v)),
          _slider('Jitter amp', 0.0, 3.0, _jitterAmp,
              (v) => setState(() => _jitterAmp = v)),
          _slider('Jitter freq', 0.005, 0.08, _jitterFreq,
              (v) => setState(() => _jitterFreq = v)),

          // Log everything
          ElevatedButton.icon(
            onPressed: () {
              debugPrint('--- CURRENT SETTINGS ---');
              debugPrint('edgeMode: $_edgeMode');
              debugPrint('blurK: $_blurK');
              debugPrint('cannyLo: $_cannyLo');
              debugPrint('cannyHi: $_cannyHi');
              debugPrint('dogSigma: $_dogSigma');
              debugPrint('dogK: $_dogK');
              debugPrint('dogThresh: $_dogThresh');
              debugPrint('epsilon: $_epsilon');
              debugPrint('resample: $_resample');
              debugPrint('minPerim: $_minPerim');
              debugPrint('worldScale: $_worldScale');
              debugPrint('externalOnly: $_externalOnly');

              debugPrint('angleThresholdDeg: $_angleThreshold');
              debugPrint('angleWindow: ${_angleWindow.round()}');
              debugPrint('smoothPasses: ${_smoothPasses.round()}');
              debugPrint('mergeParallel: $_mergeParallel');
              debugPrint('mergeMaxDist: $_mergeMaxDist');
              debugPrint('minStrokeLen: $_minStrokeLen');
              debugPrint('minStrokePoints: ${_minStrokePoints.round()}');

              debugPrint('seconds: $_seconds');
              debugPrint('passes: $_passes');
              debugPrint('opacity: $_opacity');
              debugPrint('width: $_width');
              debugPrint('jitterAmp: $_jitterAmp');
              debugPrint('jitterFreq: $_jitterFreq');
              debugPrint('showRasterUnder: $_showRasterUnder');

              debugPrint('placementX: ${_xCtrl.text}');
              debugPrint('placementY: ${_yCtrl.text}');
              debugPrint('placementWidth: ${_wCtrl.text}');
              debugPrint('------------------------');
            },
            icon: const Icon(Icons.bug_report),
            label: const Text('Log Current Settings'),
          ),

          SwitchListTile(
            value: _showRasterUnder,
            onChanged: (v) => setState(() => _showRasterUnder = v),
            title: const Text('Show raster under sketch'),
            dense: true,
          ),
          SwitchListTile(
            value: _debugAllowUnderDiagrams,
            onChanged: (v) => setState(() => _debugAllowUnderDiagrams = v),
            title: const Text('Debug: show raster under auto diagrams'),
            dense: true,
          ),
        ],
      ),
    );
  }

  // (removed old direct-audio helper; playback handled by assistant_audio)

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType:
          const TextInputType.numberWithOptions(signed: true, decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _slider(String label, double min, double max, double value,
      ValueChanged<double> onChanged,
      {int? divisions, String Function(double)? display}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text(display != null
              ? display(value)
              : value.toStringAsFixed((max - min) <= 10 ? 0 : 2)),
        ]),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

// RasterOnlyPainter and layout classes (LayoutConfig, LayoutState, BBox, DrawnBlock, etc.)
// are now imported from whiteboard/whiteboard.dart
