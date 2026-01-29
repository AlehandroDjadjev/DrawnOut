import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/timeline.dart';

/// Controller for synchronized audio + drawing playback
class TimelinePlaybackController extends ChangeNotifier {
  SyncedTimeline? _timeline;
  int _currentSegmentIndex = 0;
  bool _isPlaying = false;
  bool _isPaused = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _progressTimer;
  double _currentTime = 0.0;
  String _baseUrl = 'http://localhost:8000';

  // Callbacks
  Future<void> Function(List<DrawingAction> actions)? onDrawingActionsTriggered;
  void Function(int segmentIndex)? onSegmentChanged;
  void Function()? onSegmentChangedCompleted;
  void Function()? onTimelineCompleted;

  SyncedTimeline? get timeline => _timeline;
  int get currentSegmentIndex => _currentSegmentIndex;
  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  double get currentTime => _currentTime;
  double get totalDuration => _timeline?.totalDuration ?? 0.0;
  TimelineSegment? get currentSegment =>
      _timeline != null && _currentSegmentIndex < _timeline!.segments.length
          ? _timeline!.segments[_currentSegmentIndex]
          : null;

  void setBaseUrl(String url) {
    _baseUrl = url.trim();
    if (_baseUrl.endsWith('/')) {
      _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
    }
  }

  Future<void> loadTimeline(SyncedTimeline timeline) async {
    _timeline = timeline;
    _currentSegmentIndex = 0;
    _currentTime = 0.0;
    _isPlaying = false;
    _isPaused = false;
    notifyListeners();
  }

  Future<void> play() async {
    if (_timeline == null || _timeline!.segments.isEmpty) {
      debugPrint('❌ Cannot play: no timeline loaded');
      return;
    }

    if (_isPaused) {
      debugPrint('▶️ Resuming playback');
      _isPaused = false;
      _isPlaying = true;
      await _audioPlayer.play();
      _startProgressTimer();
      notifyListeners();
      return;
    }

    debugPrint('▶️ Starting playback from segment $_currentSegmentIndex');
    _isPlaying = true;
    notifyListeners();

    await _playSegment(_currentSegmentIndex);
  }

  Future<void> _playSegment(int index) async {
    if (_timeline == null || index >= _timeline!.segments.length) {
      debugPrint('✅ Timeline playback completed');
      await stop();
      onTimelineCompleted?.call();
      return;
    }

    if (!_isPlaying) {
      debugPrint('⏸️ Playback stopped');
      return;
    }

    _currentSegmentIndex = index;
    final segment = _timeline!.segments[index];

    debugPrint(
        '🎬 Playing segment $index: "${segment.speechText.substring(0, segment.speechText.length > 50 ? 50 : segment.speechText.length)}..."');
    debugPrint('   📋 Segment has ${segment.drawingActions.length} drawing actions');
    debugPrint('   🔊 Audio file: ${segment.audioFile}');

    onSegmentChanged?.call(index);

    try {
      final audioUrl = _buildAudioUrl(segment.audioFile);
      debugPrint('   🔊 Full audio URL: $audioUrl');

      await _audioPlayer.setUrl(audioUrl);

      // Fire drawing actions in parallel with audio
      debugPrint('   🎨 Triggering drawing actions...');
      if (onDrawingActionsTriggered != null) {
        onDrawingActionsTriggered!(segment.drawingActions).catchError((e) {
          debugPrint('   ❌ Drawing error: $e');
        });
      }

      await _audioPlayer.play();
      debugPrint('   ✅ Audio playing, drawing animating in parallel');

      _startProgressTimer();

      // Wait for audio to complete
      await _audioPlayer.playerStateStream.firstWhere((state) =>
          state.processingState == ProcessingState.completed || !_isPlaying);

      _stopProgressTimer();

      if (!_isPlaying) {
        debugPrint('   ⏹️ Playback was stopped manually');
        return;
      }

      debugPrint('   ✅ Segment $index audio completed');

      onSegmentChangedCompleted?.call();

      // Brief pause between segments
      await Future.delayed(const Duration(milliseconds: 500));

      await _playSegment(index + 1);
    } catch (e, st) {
      debugPrint('❌ Error playing segment $index: $e');
      debugPrint('Stack: $st');
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isPlaying) {
        await _playSegment(index + 1);
      }
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final pos = _audioPlayer.position;
      final segmentStart = currentSegment?.startTime ?? 0.0;
      _currentTime = segmentStart + (pos.inMilliseconds / 1000.0);
      notifyListeners();
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> pause() async {
    if (!_isPlaying || _isPaused) return;

    debugPrint('⏸️ Pausing playback');
    await _audioPlayer.pause();
    _stopProgressTimer();
    _isPaused = true;
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> stop() async {
    debugPrint('⏹️ Stopping playback');
    await _audioPlayer.stop();
    _stopProgressTimer();
    _currentSegmentIndex = 0;
    _currentTime = 0.0;
    _isPlaying = false;
    _isPaused = false;
    notifyListeners();
  }

  Future<void> seekToSegment(int index) async {
    if (_timeline == null ||
        index < 0 ||
        index >= _timeline!.segments.length) {
      return;
    }

    debugPrint('⏭️ Seeking to segment $index');
    final wasPlaying = _isPlaying;
    await stop();
    _currentSegmentIndex = index;
    _currentTime = _timeline!.segments[index].startTime;
    notifyListeners();

    if (wasPlaying) {
      await play();
    }
  }

  String _buildAudioUrl(String? audioFile) {
    if (audioFile == null || audioFile.isEmpty) {
      throw Exception('No audio file for segment');
    }

    if (audioFile.startsWith('http://') || audioFile.startsWith('https://')) {
      return audioFile;
    }

    return '$_baseUrl$audioFile';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }
}
