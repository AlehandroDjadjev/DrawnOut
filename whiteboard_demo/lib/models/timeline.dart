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
  final String type;  // heading, bullet, formula, label, subbullet
  final String text;
  final int? level;
  final String? timingHint;
  final Map<String, dynamic>? style;

  DrawingAction({
    required this.type,
    required this.text,
    this.level,
    this.timingHint,
    this.style,
  });

  factory DrawingAction.fromJson(Map<String, dynamic> json) {
    return DrawingAction(
      type: json['type'] as String,
      text: json['text'] as String,
      level: json['level'] as int?,
      timingHint: json['timing_hint'] as String?,
      style: json['style'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'text': text,
      if (level != null) 'level': level,
      if (timingHint != null) 'timing_hint': timingHint,
      if (style != null) 'style': style,
    };
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



