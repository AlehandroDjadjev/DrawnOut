# Speech-Drawing Synchronization Implementation Plan

## Executive Summary
Create a precise timeline generator that synchronizes tutor speech with whiteboard drawing actions, ensuring what the tutor says matches what appears on screen at the exact moment.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     LESSON REQUEST                              │
│  (Topic, Level, Duration, Learning Objectives)                  │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│              TIMELINE GENERATOR SERVICE                         │
│  (Django Backend - New Service)                                 │
│                                                                 │
│  Input:  Lesson Plan + Content                                 │
│  Output: Synchronized Timeline JSON                            │
│          {                                                      │
│            segments: [                                          │
│              {                                                  │
│                start_time: 0.0,                                │
│                end_time: 5.2,                                  │
│                speech_text: "Let's start with a triangle",    │
│                drawing_actions: [                              │
│                  {type: "heading", text: "TRIANGLE", ...}      │
│                ],                                              │
│                audio_duration_estimate: 5.2                    │
│              }, ...                                            │
│            ]                                                    │
│          }                                                      │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│              AUDIO SYNTHESIS PIPELINE                           │
│  (Google Cloud TTS - Existing)                                 │
│  - Generate audio files for each segment                       │
│  - Return actual durations                                     │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│              PLAYBACK COORDINATOR                               │
│  (Flutter Frontend - Enhanced)                                 │
│  - Play audio segment                                          │
│  - Trigger drawing actions at precise timestamps              │
│  - Move to next segment on completion                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Backend Timeline Generator Service

### 1.1 Create New Django App: `timeline_generator`

**File: `DrawnOut/backend/timeline_generator/models.py`**

```python
from django.db import models
from lessons.models import LessonSession

class Timeline(models.Model):
    """Stores a generated synchronized timeline"""
    session = models.ForeignKey(LessonSession, on_delete=models.CASCADE, related_name='timelines')
    segments = models.JSONField()  # List of timeline segments
    total_duration = models.FloatField()
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-created_at']

class TimelineSegment(models.Model):
    """Individual segment of a timeline"""
    timeline = models.ForeignKey(Timeline, on_delete=models.CASCADE, related_name='segment_records')
    sequence_number = models.IntegerField()
    start_time = models.FloatField()  # seconds
    end_time = models.FloatField()  # seconds
    speech_text = models.TextField()
    audio_file = models.FileField(upload_to='timeline_audio/', null=True, blank=True)
    actual_audio_duration = models.FloatField(null=True, blank=True)
    drawing_actions = models.JSONField()  # Whiteboard actions for this segment
    
    class Meta:
        ordering = ['sequence_number']
        unique_together = ['timeline', 'sequence_number']
```

### 1.2 LLM Prompt Engineering for Timeline Generation

**File: `DrawnOut/backend/timeline_generator/prompts.py`**

```python
TIMELINE_GENERATION_SYSTEM_PROMPT = """
You are an expert educational content synchronizer. Your task is to create a PRECISELY TIMED script that synchronizes what a tutor says with what appears on a whiteboard.

CRITICAL RULES:
1. Speech must MATCH drawing timing EXACTLY
2. When saying "let's draw a triangle", the triangle text MUST appear at that moment
3. When labeling "this is side a", that label MUST appear at that moment
4. Each segment should be 3-8 seconds long
5. Drawing actions should be simple: headings, bullet points, formulas, labels
6. NO shapes or diagrams yet (separate pipeline)

OUTPUT FORMAT (JSON):
{
  "segments": [
    {
      "sequence": 1,
      "speech_text": "Let's start by understanding the Pythagorean theorem",
      "estimated_duration": 4.5,
      "drawing_actions": [
        {
          "type": "heading",
          "text": "PYTHAGOREAN THEOREM",
          "timing_hint": "appears as 'Pythagorean theorem' is spoken"
        }
      ]
    },
    {
      "sequence": 2,
      "speech_text": "The formula is a squared plus b squared equals c squared",
      "estimated_duration": 5.0,
      "drawing_actions": [
        {
          "type": "formula",
          "text": "a² + b² = c²",
          "timing_hint": "appears during 'a squared plus b squared'"
        }
      ]
    },
    {
      "sequence": 3,
      "speech_text": "Where a and b are the two shorter sides",
      "estimated_duration": 3.5,
      "drawing_actions": [
        {
          "type": "bullet",
          "text": "a, b = shorter sides",
          "level": 1,
          "timing_hint": "appears as 'shorter sides' is mentioned"
        }
      ]
    },
    {
      "sequence": 4,
      "speech_text": "And c is the hypotenuse, the longest side",
      "estimated_duration": 4.0,
      "drawing_actions": [
        {
          "type": "bullet",
          "text": "c = hypotenuse (longest)",
          "level": 1,
          "timing_hint": "appears when 'hypotenuse' is said"
        }
      ]
    }
  ],
  "total_estimated_duration": 17.0
}

TIMING ESTIMATION GUIDELINES:
- Average speech rate: 150 words per minute (2.5 words/second)
- Count words in speech_text and divide by 2.5
- Add 0.3s pause at end of each segment
- Round to 1 decimal place

SYNCHRONIZATION PRINCIPLES:
- Mention content just before or as it appears
- Use phrases like "let's write", "here's", "this shows"
- Break complex formulas into parts that match speech rhythm
- Each segment = one clear point with its visual
"""

def build_timeline_prompt(lesson_plan: dict, topic: str, duration_target: float = 60.0) -> str:
    """Build the user prompt for timeline generation"""
    
    steps = lesson_plan.get('steps', lesson_plan.get('lesson_plan', []))
    content = "\n".join([f"{i+1}. {step}" for i, step in enumerate(steps)])
    
    return f"""
LESSON TOPIC: {topic}

TARGET DURATION: {duration_target} seconds

LESSON CONTENT:
{content}

INSTRUCTIONS:
Create a synchronized speech-and-drawing timeline where:
1. Each segment is 3-8 seconds
2. Speech EXACTLY describes what's being drawn
3. Total duration should be approximately {duration_target} seconds
4. Use clear, simple visual elements (headings, bullets, formulas)
5. Maximum {int(duration_target / 5)} segments

Generate the timeline JSON now.
"""
```

### 1.3 Timeline Generation Service

**File: `DrawnOut/backend/timeline_generator/services.py`**

```python
import os
import json
import time
from typing import Dict, List, Optional
from openai import OpenAI

class TimelineGeneratorService:
    """Generates synchronized speech-drawing timelines using GPT-4"""
    
    def __init__(self):
        self.client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))
        self.model = "gpt-4-turbo-preview"  # or gpt-4o for structured outputs
    
    def generate_timeline(
        self,
        lesson_plan: dict,
        topic: str,
        duration_target: float = 60.0,
        max_retries: int = 3
    ) -> Optional[Dict]:
        """
        Generate a synchronized timeline using GPT-4
        
        Returns:
            {
                "segments": [...],
                "total_estimated_duration": float,
                "metadata": {...}
            }
        """
        from .prompts import TIMELINE_GENERATION_SYSTEM_PROMPT, build_timeline_prompt
        
        user_prompt = build_timeline_prompt(lesson_plan, topic, duration_target)
        
        for attempt in range(max_retries):
            try:
                response = self.client.chat.completions.create(
                    model=self.model,
                    messages=[
                        {"role": "system", "content": TIMELINE_GENERATION_SYSTEM_PROMPT},
                        {"role": "user", "content": user_prompt}
                    ],
                    response_format={"type": "json_object"},  # Force JSON output
                    temperature=0.7,
                    max_tokens=4000,
                )
                
                content = response.choices[0].message.content
                timeline_data = json.loads(content)
                
                # Validate timeline structure
                if not self._validate_timeline(timeline_data):
                    if attempt < max_retries - 1:
                        continue
                    raise ValueError("Invalid timeline structure after all retries")
                
                # Add cumulative timings
                timeline_data = self._compute_cumulative_timings(timeline_data)
                
                return timeline_data
                
            except Exception as e:
                print(f"Timeline generation attempt {attempt + 1} failed: {e}")
                if attempt == max_retries - 1:
                    raise
                time.sleep(1)
        
        return None
    
    def _validate_timeline(self, data: dict) -> bool:
        """Validate timeline structure"""
        if not isinstance(data, dict):
            return False
        if 'segments' not in data:
            return False
        segments = data['segments']
        if not isinstance(segments, list) or len(segments) == 0:
            return False
        
        for seg in segments:
            required = ['sequence', 'speech_text', 'estimated_duration', 'drawing_actions']
            if not all(k in seg for k in required):
                return False
            if not isinstance(seg['drawing_actions'], list):
                return False
        
        return True
    
    def _compute_cumulative_timings(self, data: dict) -> dict:
        """Add start_time and end_time to each segment"""
        cumulative = 0.0
        for segment in data['segments']:
            segment['start_time'] = round(cumulative, 2)
            duration = segment['estimated_duration']
            cumulative += duration
            segment['end_time'] = round(cumulative, 2)
        
        data['total_estimated_duration'] = round(cumulative, 2)
        return data


class AudioSynthesisPipeline:
    """Synthesizes audio for each timeline segment"""
    
    def __init__(self):
        from google.cloud import texttospeech
        self.tts_client = texttospeech.TextToSpeechClient()
    
    def synthesize_segments(self, timeline: Dict) -> Dict:
        """
        Synthesize audio for all segments and update with actual durations
        
        Returns timeline with audio_file and actual_audio_duration added to each segment
        """
        from django.core.files.base import ContentFile
        import librosa  # for getting audio duration
        
        segments = timeline['segments']
        
        for i, segment in enumerate(segments):
            # Synthesize audio
            audio_content = self._synthesize_speech(segment['speech_text'])
            
            # Save audio file
            filename = f"segment_{i+1}_{int(time.time())}.mp3"
            segment['audio_file'] = filename
            # (Save to media/timeline_audio/ directory)
            
            # Get actual duration
            duration = self._get_audio_duration(audio_content)
            segment['actual_audio_duration'] = round(duration, 2)
        
        # Recompute timings based on actual durations
        timeline = self._recompute_timings(timeline)
        
        return timeline
    
    def _synthesize_speech(self, text: str) -> bytes:
        """Synthesize speech using Google Cloud TTS"""
        from google.cloud import texttospeech
        
        synthesis_input = texttospeech.SynthesisInput(text=text)
        voice = texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name="en-US-Neural2-F"  # Female voice
        )
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3
        )
        
        response = self.tts_client.synthesize_speech(
            input=synthesis_input,
            voice=voice,
            audio_config=audio_config
        )
        
        return response.audio_content
    
    def _get_audio_duration(self, audio_bytes: bytes) -> float:
        """Get duration of audio in seconds"""
        import io
        import librosa
        import soundfile as sf
        
        # Load audio from bytes
        audio_io = io.BytesIO(audio_bytes)
        y, sr = sf.read(audio_io)
        duration = librosa.get_duration(y=y, sr=sr)
        return duration
    
    def _recompute_timings(self, timeline: Dict) -> Dict:
        """Recompute start/end times based on actual audio durations"""
        cumulative = 0.0
        for segment in timeline['segments']:
            segment['start_time'] = round(cumulative, 2)
            duration = segment['actual_audio_duration']
            cumulative += duration
            segment['end_time'] = round(cumulative, 2)
        
        timeline['total_actual_duration'] = round(cumulative, 2)
        return timeline
```

### 1.4 API Endpoints

**File: `DrawnOut/backend/timeline_generator/views.py`**

```python
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from lessons.models import LessonSession
from .services import TimelineGeneratorService, AudioSynthesisPipeline
from .models import Timeline

class GenerateTimelineView(APIView):
    permission_classes = [AllowAny]
    
    def post(self, request, session_id: int):
        """
        Generate a synchronized timeline for a lesson session
        
        POST /api/timeline/generate/<session_id>/
        Body: {
            "duration_target": 60.0,  # optional, default 60s
            "regenerate": false  # optional, force regeneration
        }
        
        Returns: {
            "timeline_id": 123,
            "segments": [...],
            "total_duration": 62.5,
            "status": "ready"
        }
        """
        try:
            session = LessonSession.objects.get(pk=session_id)
        except LessonSession.DoesNotExist:
            return Response({"error": "Session not found"}, status=404)
        
        # Check if timeline already exists
        regenerate = request.data.get('regenerate', False)
        if not regenerate:
            existing = Timeline.objects.filter(session=session).first()
            if existing:
                return Response({
                    "timeline_id": existing.id,
                    "segments": existing.segments,
                    "total_duration": existing.total_duration,
                    "status": "cached"
                })
        
        # Generate new timeline
        duration_target = request.data.get('duration_target', 60.0)
        
        generator = TimelineGeneratorService()
        timeline_data = generator.generate_timeline(
            lesson_plan={'steps': session.lesson_plan},
            topic=session.topic,
            duration_target=duration_target
        )
        
        if not timeline_data:
            return Response({"error": "Failed to generate timeline"}, status=500)
        
        # Synthesize audio for segments
        audio_pipeline = AudioSynthesisPipeline()
        timeline_data = audio_pipeline.synthesize_segments(timeline_data)
        
        # Save timeline
        timeline = Timeline.objects.create(
            session=session,
            segments=timeline_data['segments'],
            total_duration=timeline_data.get('total_actual_duration', timeline_data['total_estimated_duration'])
        )
        
        return Response({
            "timeline_id": timeline.id,
            "segments": timeline.segments,
            "total_duration": timeline.total_duration,
            "status": "ready"
        }, status=201)


class GetTimelineView(APIView):
    permission_classes = [AllowAny]
    
    def get(self, request, timeline_id: int):
        """Get timeline by ID"""
        try:
            timeline = Timeline.objects.get(pk=timeline_id)
            return Response({
                "timeline_id": timeline.id,
                "session_id": timeline.session.id,
                "segments": timeline.segments,
                "total_duration": timeline.total_duration,
                "created_at": timeline.created_at.isoformat()
            })
        except Timeline.DoesNotExist:
            return Response({"error": "Timeline not found"}, status=404)
```

**File: `DrawnOut/backend/timeline_generator/urls.py`**

```python
from django.urls import path
from .views import GenerateTimelineView, GetTimelineView

urlpatterns = [
    path('generate/<int:session_id>/', GenerateTimelineView.as_view(), name='generate_timeline'),
    path('<int:timeline_id>/', GetTimelineView.as_view(), name='get_timeline'),
]
```

---

## Phase 2: Frontend Playback Coordinator

### 2.1 Timeline Data Model

**File: `DrawnOut/whiteboard_demo/lib/models/timeline.dart`**

```dart
class TimelineSegment {
  final int sequence;
  final double startTime;
  final double endTime;
  final String speechText;
  final String? audioFile;
  final double actualAudioDuration;
  final List<DrawingAction> drawingActions;

  TimelineSegment({
    required this.sequence,
    required this.startTime,
    required this.endTime,
    required this.speechText,
    this.audioFile,
    required this.actualAudioDuration,
    required this.drawingActions,
  });

  factory TimelineSegment.fromJson(Map<String, dynamic> json) {
    return TimelineSegment(
      sequence: json['sequence'] as int,
      startTime: (json['start_time'] as num).toDouble(),
      endTime: (json['end_time'] as num).toDouble(),
      speechText: json['speech_text'] as String,
      audioFile: json['audio_file'] as String?,
      actualAudioDuration: (json['actual_audio_duration'] as num).toDouble(),
      drawingActions: (json['drawing_actions'] as List)
          .map((a) => DrawingAction.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DrawingAction {
  final String type;  // heading, bullet, formula, label
  final String text;
  final int? level;
  final String? timingHint;

  DrawingAction({
    required this.type,
    required this.text,
    this.level,
    this.timingHint,
  });

  factory DrawingAction.fromJson(Map<String, dynamic> json) {
    return DrawingAction(
      type: json['type'] as String,
      text: json['text'] as String,
      level: json['level'] as int?,
      timingHint: json['timing_hint'] as String?,
    );
  }
}

class SyncedTimeline {
  final int timelineId;
  final int sessionId;
  final List<TimelineSegment> segments;
  final double totalDuration;

  SyncedTimeline({
    required this.timelineId,
    required this.sessionId,
    required this.segments,
    required this.totalDuration,
  });

  factory SyncedTimeline.fromJson(Map<String, dynamic> json) {
    return SyncedTimeline(
      timelineId: json['timeline_id'] as int,
      sessionId: json['session_id'] as int,
      segments: (json['segments'] as List)
          .map((s) => TimelineSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
      totalDuration: (json['total_duration'] as num).toDouble(),
    );
  }
}
```

### 2.2 Timeline Playback Controller

**File: `DrawnOut/whiteboard_demo/lib/controllers/timeline_playback_controller.dart`**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/timeline.dart';

class TimelinePlaybackController extends ChangeNotifier {
  SyncedTimeline? _timeline;
  int _currentSegmentIndex = 0;
  bool _isPlaying = false;
  bool _isPaused = false;
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _progressTimer;
  double _currentTime = 0.0;
  
  // Callbacks
  void Function(List<DrawingAction> actions)? onDrawingActionsTriggered;
  void Function(int segmentIndex)? onSegmentChanged;
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
  
  Future<void> loadTimeline(SyncedTimeline timeline) async {
    _timeline = timeline;
    _currentSegmentIndex = 0;
    _currentTime = 0.0;
    _isPlaying = false;
    _isPaused = false;
    notifyListeners();
  }
  
  Future<void> play() async {
    if (_timeline == null || _timeline!.segments.isEmpty) return;
    
    if (_isPaused) {
      // Resume from pause
      _isPaused = false;
      _isPlaying = true;
      await _audioPlayer.play();
      _startProgressTimer();
      notifyListeners();
      return;
    }
    
    _isPlaying = true;
    notifyListeners();
    
    // Play from current segment
    await _playSegment(_currentSegmentIndex);
  }
  
  Future<void> _playSegment(int index) async {
    if (_timeline == null || index >= _timeline!.segments.length) {
      await stop();
      onTimelineCompleted?.call();
      return;
    }
    
    _currentSegmentIndex = index;
    final segment = _timeline!.segments[index];
    
    debugPrint('▶️ Playing segment $index: "${segment.speechText}"');
    
    // Trigger drawing actions IMMEDIATELY as audio starts
    onDrawingActionsTriggered?.call(segment.drawingActions);
    onSegmentChanged?.call(index);
    
    // Load and play audio
    try {
      final audioUrl = _buildAudioUrl(segment.audioFile);
      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();
      
      _startProgressTimer();
      
      // Wait for audio to complete
      await _audioPlayer.playerStateStream
          .firstWhere((state) => state.processingState == ProcessingState.completed);
      
      _stopProgressTimer();
      
      if (!_isPlaying) return; // Stopped manually
      
      // Move to next segment
      await _playSegment(index + 1);
      
    } catch (e) {
      debugPrint('❌ Error playing segment $index: $e');
      // Skip to next segment on error
      await _playSegment(index + 1);
    }
  }
  
  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_audioPlayer.position != null) {
        final segmentStart = currentSegment?.startTime ?? 0.0;
        _currentTime = segmentStart + (_audioPlayer.position!.inMilliseconds / 1000.0);
        notifyListeners();
      }
    });
  }
  
  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }
  
  Future<void> pause() async {
    if (!_isPlaying || _isPaused) return;
    
    await _audioPlayer.pause();
    _stopProgressTimer();
    _isPaused = true;
    _isPlaying = false;
    notifyListeners();
  }
  
  Future<void> stop() async {
    await _audioPlayer.stop();
    _stopProgressTimer();
    _currentSegmentIndex = 0;
    _currentTime = 0.0;
    _isPlaying = false;
    _isPaused = false;
    notifyListeners();
  }
  
  Future<void> seekToSegment(int index) async {
    if (_timeline == null || index < 0 || index >= _timeline!.segments.length) {
      return;
    }
    
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
    if (audioFile == null) throw Exception('No audio file');
    // Build full URL to audio file
    const baseUrl = 'http://localhost:8000';  // TODO: make configurable
    return '$baseUrl/media/timeline_audio/$audioFile';
  }
  
  @override
  void dispose() {
    _audioPlayer.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }
}
```

### 2.3 Integrate Timeline into Main Whiteboard

**File: `DrawnOut/whiteboard_demo/lib/main.dart` (additions)**

```dart
// Add to _WhiteboardPageState class:

TimelinePlaybackController? _timelineController;

@override
void initState() {
  super.initState();
  _timelineController = TimelinePlaybackController();
  
  // Set up callbacks
  _timelineController!.onDrawingActionsTriggered = (actions) {
    _handleSyncedDrawingActions(actions);
  };
  
  _timelineController!.onSegmentChanged = (index) {
    debugPrint('📍 Segment $index started');
  };
  
  _timelineController!.onTimelineCompleted = () {
    debugPrint('✅ Timeline completed!');
    _showError('Lesson completed!');
  };
  
  // ... rest of existing initState
}

Future<void> _startSynchronizedLesson() async {
  setState(() { _busy = true; });
  
  try {
    debugPrint('🎬 Starting synchronized lesson...');
    _api = AssistantApiClient(_apiUrlCtrl.text.trim());
    
    // 1. Start lesson session
    final data = await _api!.startLesson(topic: 'Pythagorean Theorem');
    _sessionId = data['id'] as int?;
    debugPrint('✅ Session created: $_sessionId');
    
    // 2. Generate timeline
    debugPrint('⏱️ Generating timeline...');
    final timelineData = await _api!.generateTimeline(_sessionId!, durationTarget: 60.0);
    final timeline = SyncedTimeline.fromJson(timelineData);
    debugPrint('✅ Timeline generated: ${timeline.segments.length} segments, ${timeline.totalDuration}s');
    
    // 3. Load timeline into controller
    await _timelineController!.loadTimeline(timeline);
    
    // 4. Start playback
    debugPrint('▶️ Starting playback...');
    await _timelineController!.play();
    
  } catch (e, st) {
    debugPrint('❌ Synchronized lesson error: $e\n$st');
    _showError(e.toString());
  } finally {
    setState(() { _busy = false; });
  }
}

Future<void> _handleSyncedDrawingActions(List<DrawingAction> actions) async {
  debugPrint('🎨 Drawing ${actions.length} synchronized actions');
  
  await _ensureLayout();
  
  final whiteboardActions = actions.map((action) => {
    'type': action.type,
    'text': action.text,
    if (action.level != null) 'level': action.level,
  }).toList();
  
  // Draw with fast animation (since audio is already playing)
  await _handleWhiteboardActions(
    whiteboardActions,
    fontScale: _tutorFontScale,
    overrideSeconds: 2.0,  // Fast drawing to match speech
  );
}

// Add button in UI:
ElevatedButton.icon(
  onPressed: _busy ? null : _startSynchronizedLesson,
  icon: const Icon(Icons.sync),
  label: const Text('Start Synchronized Lesson'),
),
```

---

## Phase 3: Testing & Refinement

### 3.1 Test Suite

**File: `DrawnOut/backend/timeline_generator/tests.py`**

```python
from django.test import TestCase
from .services import TimelineGeneratorService
import json

class TimelineGeneratorTests(TestCase):
    def setUp(self):
        self.service = TimelineGeneratorService()
    
    def test_generates_valid_timeline(self):
        """Test basic timeline generation"""
        lesson_plan = {
            'steps': [
                'Explain the Pythagorean theorem',
                'Show the formula a² + b² = c²',
                'Explain each variable'
            ]
        }
        
        timeline = self.service.generate_timeline(
            lesson_plan=lesson_plan,
            topic='Pythagorean Theorem',
            duration_target=30.0
        )
        
        self.assertIsNotNone(timeline)
        self.assertIn('segments', timeline)
        self.assertGreater(len(timeline['segments']), 0)
        
        # Check first segment structure
        seg = timeline['segments'][0]
        self.assertIn('speech_text', seg)
        self.assertIn('drawing_actions', seg)
        self.assertIn('estimated_duration', seg)
    
    def test_synchronization_quality(self):
        """Test that speech mentions what's being drawn"""
        lesson_plan = {
            'steps': ['Introduce right triangles']
        }
        
        timeline = self.service.generate_timeline(
            lesson_plan=lesson_plan,
            topic='Triangles',
            duration_target=20.0
        )
        
        # Check that each segment's speech relates to its drawing actions
        for seg in timeline['segments']:
            speech = seg['speech_text'].lower()
            for action in seg['drawing_actions']:
                action_text = action['text'].lower()
                # At least some keyword overlap
                words = set(action_text.split()) & set(speech.split())
                self.assertGreater(len(words), 0,
                    f"No overlap between speech '{speech}' and drawing '{action_text}'")
```

### 3.2 Quality Metrics

Track these metrics to ensure quality:

1. **Synchronization Score**: % of segments where speech mentions drawing content
2. **Timing Accuracy**: Difference between estimated and actual durations
3. **User Comprehension**: A/B test synchronized vs unsynchronized lessons
4. **Cognitive Load**: Measure user attention split (eye tracking if available)

---

## Phase 4: Deployment Checklist

### 4.1 Backend

- [ ] Add `timeline_generator` to `INSTALLED_APPS`
- [ ] Run migrations: `python manage.py makemigrations timeline_generator && python manage.py migrate`
- [ ] Add `librosa` and `soundfile` to `requirements.txt`
- [ ] Ensure `GOOGLE_APPLICATION_CREDENTIALS` is set for TTS
- [ ] Test `/api/timeline/generate/<session_id>/` endpoint
- [ ] Monitor GPT-4 API costs (estimate: $0.03-0.10 per timeline)

### 4.2 Frontend

- [ ] Add `just_audio` to `pubspec.yaml`
- [ ] Create `models/timeline.dart`
- [ ] Create `controllers/timeline_playback_controller.dart`
- [ ] Integrate into main whiteboard
- [ ] Test audio playback synchronization
- [ ] Add loading states and error handling
- [ ] Test on web and mobile platforms

### 4.3 Performance Targets

- Timeline generation: < 10 seconds
- Audio synthesis: < 30 seconds for 60s lesson
- Total preprocessing: < 45 seconds
- Playback sync accuracy: ± 200ms

---

## Phase 5: Future Enhancements

### 5.1 Diagram Integration (Phase 6)

Once basic timeline works, add diagram generation:

```json
{
  "sequence": 5,
  "speech_text": "Here's what a right triangle looks like",
  "drawing_actions": [
    {
      "type": "diagram",
      "diagram_type": "right_triangle",
      "labels": ["a", "b", "c"],
      "timing_hint": "appears during 'right triangle'"
    }
  ]
}
```

### 5.2 Real-time Adaptation

Allow timeline to adapt based on user questions:
- Pause timeline
- Insert Q&A segment
- Resume timeline

### 5.3 Multi-language Support

Generate timelines in multiple languages with localized TTS.

---

## Estimated Timeline

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Phase 1 | 3-4 days | Backend timeline generator working |
| Phase 2 | 2-3 days | Frontend playback synchronized |
| Phase 3 | 1-2 days | Testing and refinement |
| Phase 4 | 1 day | Deployment and monitoring |
| **Total** | **1-2 weeks** | **Production-ready synchronized lessons** |

---

## Success Criteria

✅ Speech and drawing are synchronized within 500ms  
✅ Users report improved comprehension vs old system  
✅ Timeline generation completes in < 45 seconds  
✅ System handles 10+ concurrent timeline generations  
✅ Audio playback is smooth with no stuttering  
✅ Drawing animations complete before next segment

---

## Key Technologies

- **LLM**: GPT-4 Turbo (for structured timeline generation)
- **TTS**: Google Cloud Text-to-Speech (existing)
- **Audio**: just_audio (Flutter package)
- **Backend**: Django REST Framework
- **Storage**: PostgreSQL + Media files

---

## Cost Estimate

- GPT-4 API: ~$0.05 per timeline
- Google TTS: ~$0.02 per timeline
- **Total per lesson**: ~$0.07
- **1000 lessons/month**: ~$70

---

This plan provides a complete roadmap for implementing synchronized speech-drawing timelines. The system is modular, testable, and can be deployed incrementally.




