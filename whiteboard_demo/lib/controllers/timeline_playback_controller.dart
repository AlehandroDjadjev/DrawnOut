import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/timeline.dart';

class TimelinePlaybackController extends ChangeNotifier {
  SyncedTimeline? _timeline;
  int _currentSegmentIndex = 0;
  bool _isPlaying = false;   // True while the segment loop is active (including paused)
  bool _isPaused = false;    // True while audio is paused (subset of _isPlaying)
  bool _isDisposed = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _progressTimer;
  double _currentTime = 0.0;
  String _baseUrl = 'http://localhost:8000';

  /// Incremented every time a new playback sequence starts (play, seek, restart).
  /// Old _playSegment loops check this and exit when superseded.
  int _playbackGeneration = 0;
  int _lastStartedSegmentGeneration = -1;
  int? _lastStartedSegmentIndex;
  int _sameSegmentStartCount = 0;

  // Callbacks
  Future<void> Function(List<DrawingAction> actions)? onDrawingActionsTriggered;
  void Function(int segmentIndex)? onSegmentChanged;
  void Function()? onSegmentChangedCompleted;
  void Function()? onTimelineCompleted;

  SyncedTimeline? get timeline => _timeline;
  int get currentSegmentIndex => _currentSegmentIndex;
  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  /// True when audio is actively progressing (playing and not paused).
  bool get isActive => _isPlaying && !_isPaused;
  double get currentTime => _currentTime;
  double get totalDuration => _timeline?.totalDuration ?? 0.0;
  double get progress =>
      totalDuration > 0 ? (currentTime / totalDuration).clamp(0.0, 1.0) : 0.0;
  int get segmentCount => _timeline?.segments.length ?? 0;
  TimelineSegment? get currentSegment =>
      _timeline != null && _currentSegmentIndex < _timeline!.segments.length
          ? _timeline!.segments[_currentSegmentIndex]
          : null;

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void setBaseUrl(String url) {
    _baseUrl = url.trim();
    if (_baseUrl.endsWith('/')) {
      _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
    }
  }

  Future<void> loadTimeline(SyncedTimeline timeline) async {
    if (_isDisposed) return;
    _playbackGeneration++;
    _lastStartedSegmentGeneration = -1;
    _lastStartedSegmentIndex = null;
    _sameSegmentStartCount = 0;
    await _audioPlayer.stop();
    if (_isDisposed) return;
    _stopProgressTimer();

    _timeline = timeline;
    _currentSegmentIndex = 0;
    _currentTime = 0.0;
    _isPlaying = false;
    _isPaused = false;
    _safeNotifyListeners();
  }

  Future<void> play() async {
    if (_isDisposed) return;
    if (_timeline == null || _timeline!.segments.isEmpty) {
      debugPrint('Cannot play: no timeline loaded');
      return;
    }

    if (_isPaused) {
      // Resume from pause — the _playSegment loop is still alive and waiting
      debugPrint('Resuming playback');
      _isPaused = false;
      // Don't await — just fire the play command so the existing loop picks up
      // the completion event when the audio finishes.
      _audioPlayer.play();
      _startProgressTimer();
      _safeNotifyListeners();
      return;
    }

    if (_isPlaying) {
      // Already playing — nothing to do.
      return;
    }

    debugPrint('Starting playback from segment $_currentSegmentIndex');
    _isPlaying = true;
    _isPaused = false;
    _playbackGeneration++;
    _lastStartedSegmentGeneration = -1;
    _lastStartedSegmentIndex = null;
    _sameSegmentStartCount = 0;
    _safeNotifyListeners();

    await _playSegment(_currentSegmentIndex, _playbackGeneration);
  }

  Future<void> _playSegment(int index, int generation) async {
    if (_isDisposed) return;
    if (_timeline == null || index >= _timeline!.segments.length) {
      debugPrint('Timeline playback completed');
      _stopPlaybackState();
      if (!_isDisposed) {
        onTimelineCompleted?.call();
      }
      return;
    }

    // Check if this loop has been superseded
    if (_isDisposed || generation != _playbackGeneration) return;

    // Safety guard: if the same segment keeps restarting in the same playback
    // generation, advance once to avoid an infinite repeat loop.
    if (_lastStartedSegmentGeneration == generation &&
        _lastStartedSegmentIndex == index) {
      _sameSegmentStartCount += 1;
      if (_sameSegmentStartCount >= 2) {
        debugPrint(
            'Repeat guard: segment $index restarted $_sameSegmentStartCount times; advancing');
        await _playSegment(index + 1, generation);
        return;
      }
    } else {
      _lastStartedSegmentGeneration = generation;
      _lastStartedSegmentIndex = index;
      _sameSegmentStartCount = 0;
    }

    _currentSegmentIndex = index;
    final segment = _timeline!.segments[index];

    debugPrint(
        'Playing segment $index: "${segment.speechText.substring(0, segment.speechText.length > 50 ? 50 : segment.speechText.length)}..."');

    onSegmentChanged?.call(index);

    try {
      final audioFile = segment.audioFile;
      if (audioFile == null || audioFile.isEmpty) {
        debugPrint('   No audio file for segment $index, advancing after delay');
        await Future.delayed(
            Duration(
                milliseconds: (segment.actualAudioDuration * 1000).round().clamp(1000, 15000)),
        );
        if (_isDisposed || generation != _playbackGeneration) return;
        onSegmentChangedCompleted?.call();
        await Future.delayed(const Duration(milliseconds: 500));
        if (_isDisposed || generation != _playbackGeneration) return;
        await _playSegment(index + 1, generation);
        return;
      }

      final audioUrl = _buildAudioUrl(audioFile);
      debugPrint('   Audio URL: $audioUrl');

      // Reset any prior state and enforce non-looping playback per segment.
      await _audioPlayer.stop();
      await _audioPlayer.setLoopMode(LoopMode.off);
      await _audioPlayer.setUrl(audioUrl);
      if (_isDisposed || generation != _playbackGeneration) return;

      // Fire drawing and audio in parallel; wait for BOTH before advancing.
      // Previously we only waited for audio, so we could clear and advance
      // while drawing was still animating — causing random deletions and stuttering.
      debugPrint('   Triggering drawing actions...');
      Future<void> drawFuture = Future.value();
      if (onDrawingActionsTriggered != null &&
          segment.drawingActions.isNotEmpty) {
        drawFuture = onDrawingActionsTriggered!(segment.drawingActions);
      }
      drawFuture = drawFuture.catchError((e) {
        debugPrint('   Drawing error: $e');
      });

      _startProgressTimer();
      final playFuture = _audioPlayer.play();
      debugPrint('   Audio playing, drawing animating in parallel');

      final maxWaitSec = (segment.endTime - segment.startTime).ceil() + 15;
      var timedOut = false;
      await Future.wait([
        drawFuture,
        playFuture.timeout(
          Duration(seconds: maxWaitSec),
          onTimeout: () async {
            timedOut = true;
            debugPrint('   Segment $index: audio timeout');
            await _audioPlayer.stop();
          },
        ),
      ]);

      if (timedOut) {
        debugPrint('   Segment $index advanced after timeout');
      }

      _stopProgressTimer();

      if (_isDisposed || generation != _playbackGeneration) return;

      debugPrint('   Segment $index audio and drawing completed');
      onSegmentChangedCompleted?.call();

      // Brief pause between segments
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isDisposed || generation != _playbackGeneration) return;

      // Advance to next segment
      await _playSegment(index + 1, generation);
    } catch (e, st) {
      debugPrint('Error playing segment $index: $e');
      debugPrint('Stack: $st');
      if (_isDisposed || generation != _playbackGeneration) return;
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isDisposed || generation != _playbackGeneration) return;
      await _playSegment(index + 1, generation);
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isDisposed) {
        _progressTimer?.cancel();
        return;
      }
      if (_isPaused) return; // Don't update time while paused
      final segmentStart = currentSegment?.startTime ?? 0.0;
      _currentTime =
          segmentStart + (_audioPlayer.position.inMilliseconds / 1000.0);
      _safeNotifyListeners();
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> pause() async {
    if (_isDisposed) return;
    if (!_isPlaying || _isPaused) return;

    debugPrint('Pausing playback');
    await _audioPlayer.pause();
    _stopProgressTimer();
    _isPaused = true;
    // Keep _isPlaying = true so the _playSegment loop stays alive and
    // resumes properly when play() is called again.
    _safeNotifyListeners();
  }

  /// Stop everything and reset to the beginning.
  Future<void> stop() async {
    if (_isDisposed) return;
    debugPrint('Stopping playback');
    _playbackGeneration++; // Invalidate any active _playSegment loop
    _lastStartedSegmentGeneration = -1;
    _lastStartedSegmentIndex = null;
    _sameSegmentStartCount = 0;
    await _audioPlayer.stop();
    if (_isDisposed) return;
    _stopProgressTimer();
    _currentSegmentIndex = 0;
    _currentTime = 0.0;
    _isPlaying = false;
    _isPaused = false;
    _safeNotifyListeners();
  }

  /// Helper to stop playback state without resetting position
  /// (used when timeline naturally completes).
  void _stopPlaybackState() {
    _stopProgressTimer();
    _isPlaying = false;
    _isPaused = false;
    _safeNotifyListeners();
  }

  Future<void> restart() async {
    await stop();
    await play();
  }

  Future<void> seekToSegment(int index) async {
    if (_isDisposed) return;
    if (_timeline == null ||
        index < 0 ||
        index >= _timeline!.segments.length) {
      return;
    }

    debugPrint('Seeking to segment $index');

    // Invalidate the old playback loop and stop audio
    _playbackGeneration++;
    _lastStartedSegmentGeneration = -1;
    _lastStartedSegmentIndex = null;
    _sameSegmentStartCount = 0;
    final gen = _playbackGeneration;
    await _audioPlayer.stop();
    if (_isDisposed) return;
    _stopProgressTimer();

    _currentSegmentIndex = index;
    _currentTime = _timeline!.segments[index].startTime;
    _isPlaying = true;
    _isPaused = false;
    _safeNotifyListeners();

    // Start a fresh playback loop from the new segment
    await _playSegment(index, gen);
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
    _isDisposed = true;
    _playbackGeneration++;
    _progressTimer?.cancel();
    _progressTimer = null;
    _audioPlayer.dispose();
    super.dispose();
  }
}
