/// Timeline data models for synchronized speech-drawing playback
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
      actualAudioDuration: (json['actual_audio_duration'] as num?)?.toDouble() ?? 
                          (json['estimated_duration'] as num).toDouble(),
      drawingActions: (json['drawing_actions'] as List)
          .map((a) => DrawingAction.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sequence': sequence,
      'start_time': startTime,
      'end_time': endTime,
      'speech_text': speechText,
      'audio_file': audioFile,
      'actual_audio_duration': actualAudioDuration,
      'drawing_actions': drawingActions.map((a) => a.toJson()).toList(),
    };
  }
}

class DrawingAction {
  /// Action type: heading, bullet, formula, label, subbullet, sketch_image
  final String type;
  
  /// Text content (empty string for sketch_image actions)
  final String text;
  
  /// Indentation level for bullets/subbullets
  final int? level;
  
  /// Timing hint for animation pacing
  final String? timingHint;
  
  /// Style overrides (fontSize, color, etc.)
  final Map<String, dynamic>? style;
  
  /// URL for sketch_image actions (primary source)
  final String? imageUrl;
  
  /// Base64-encoded image data (fallback for sketch_image)
  final String? imageBase64;
  
  /// Layout placement for sketch_image: {x, y, width, height, scale}
  final Map<String, dynamic>? placement;
  
  /// Additional metadata from backend (may contain image_url, filename, etc.)
  final Map<String, dynamic>? metadata;

  DrawingAction({
    required this.type,
    required this.text,
    this.level,
    this.timingHint,
    this.style,
    this.imageUrl,
    this.imageBase64,
    this.placement,
    this.metadata,
  });

  factory DrawingAction.fromJson(Map<String, dynamic> json) {
    // Extract metadata map if present
    final meta = json['metadata'] as Map<String, dynamic>?;
    
    // For sketch_image, text may be empty or contain alt text
    final textValue = json['text'];
    final text = textValue is String ? textValue : '';
    
    return DrawingAction(
      type: json['type'] as String,
      text: text,
      level: json['level'] as int?,
      timingHint: json['timing_hint'] as String?,
      style: json['style'] as Map<String, dynamic>?,
      imageUrl: json['image_url'] as String?,
      imageBase64: json['image_base64'] as String?,
      placement: json['placement'] as Map<String, dynamic>?,
      metadata: meta,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'text': text,
      if (level != null) 'level': level,
      if (timingHint != null) 'timing_hint': timingHint,
      if (style != null) 'style': style,
      if (imageUrl != null) 'image_url': imageUrl,
      if (imageBase64 != null) 'image_base64': imageBase64,
      if (placement != null) 'placement': placement,
      if (metadata != null) 'metadata': metadata,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper getters for sketch_image actions
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the best available image URL, checking imageUrl first, then metadata
  String? get resolvedImageUrl =>
      imageUrl ?? metadata?['image_url'] as String? ?? metadata?['url'] as String?;

  /// Returns filename hint from metadata if available
  String? get filename => metadata?['filename'] as String?;

  /// Whether this action is a sketch_image type
  bool get isSketchImage => type == 'sketch_image';

  /// Returns placement as typed values, with defaults if not specified
  ({double x, double y, double width, double height, double? scale}) get placementValues {
    final p = placement ?? {};
    return (
      x: (p['x'] as num?)?.toDouble() ?? 0.0,
      y: (p['y'] as num?)?.toDouble() ?? 0.0,
      width: (p['width'] as num?)?.toDouble() ?? 200.0,
      height: (p['height'] as num?)?.toDouble() ?? 200.0,
      scale: (p['scale'] as num?)?.toDouble(),
    );
  }
}

class SyncedTimeline {
  final int timelineId;
  final int sessionId;
  final List<TimelineSegment> segments;
  final double totalDuration;
  final String? status;

  SyncedTimeline({
    required this.timelineId,
    required this.sessionId,
    required this.segments,
    required this.totalDuration,
    this.status,
  });

  factory SyncedTimeline.fromJson(Map<String, dynamic> json) {
    return SyncedTimeline(
      timelineId: json['timeline_id'] as int,
      sessionId: json['session_id'] as int,
      segments: (json['segments'] as List)
          .map((s) => TimelineSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
      totalDuration: (json['total_duration'] as num).toDouble(),
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timeline_id': timelineId,
      'session_id': sessionId,
      'segments': segments.map((s) => s.toJson()).toList(),
      'total_duration': totalDuration,
      if (status != null) 'status': status,
    };
  }
}



