import 'package:flutter_test/flutter_test.dart';
import 'package:whiteboard_demo/models/timeline.dart';

void main() {
  group('DrawingAction', () {
    group('fromJson parsing', () {
      test('parses standard text action (heading)', () {
        final json = {
          'type': 'heading',
          'text': 'Introduction to Photosynthesis',
          'level': 1,
          'timing_hint': 'slow',
          'style': {'fontSize': 24.0, 'bold': true},
        };

        final action = DrawingAction.fromJson(json);

        expect(action.type, 'heading');
        expect(action.text, 'Introduction to Photosynthesis');
        expect(action.level, 1);
        expect(action.timingHint, 'slow');
        expect(action.style?['fontSize'], 24.0);
        expect(action.style?['bold'], true);
        expect(action.isSketchImage, false);
      });

      test('parses bullet action with level', () {
        final json = {
          'type': 'bullet',
          'text': 'Chlorophyll absorbs sunlight',
          'level': 2,
        };

        final action = DrawingAction.fromJson(json);

        expect(action.type, 'bullet');
        expect(action.text, 'Chlorophyll absorbs sunlight');
        expect(action.level, 2);
        expect(action.isSketchImage, false);
      });

      test('parses sketch_image with image_url and placement', () {
        final json = {
          'type': 'sketch_image',
          'text': '',
          'image_url': 'https://example.com/diagram.png',
          'placement': {
            'x': 100.0,
            'y': 200.0,
            'width': 300.0,
            'height': 250.0,
            'scale': 1.5,
          },
        };

        final action = DrawingAction.fromJson(json);

        expect(action.type, 'sketch_image');
        expect(action.text, '');
        expect(action.imageUrl, 'https://example.com/diagram.png');
        expect(action.isSketchImage, true);

        // Check placement values
        expect(action.placement?['x'], 100.0);
        expect(action.placement?['y'], 200.0);
        expect(action.placement?['width'], 300.0);
        expect(action.placement?['height'], 250.0);
        expect(action.placement?['scale'], 1.5);

        // Check helper getter
        final pv = action.placementValues;
        expect(pv.x, 100.0);
        expect(pv.y, 200.0);
        expect(pv.width, 300.0);
        expect(pv.height, 250.0);
        expect(pv.scale, 1.5);
      });

      test('parses sketch_image with base64 fallback', () {
        final json = {
          'type': 'sketch_image',
          'text': 'Alt text for accessibility',
          'image_base64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
          'placement': {
            'x': 50.0,
            'y': 75.0,
            'width': 400.0,
            'height': 300.0,
          },
        };

        final action = DrawingAction.fromJson(json);

        expect(action.type, 'sketch_image');
        expect(action.text, 'Alt text for accessibility');
        expect(action.imageUrl, isNull);
        expect(action.imageBase64, isNotNull);
        expect(action.imageBase64!.startsWith('iVBORw0KGgo'), true);
        expect(action.isSketchImage, true);

        // No scale specified
        final pv = action.placementValues;
        expect(pv.scale, isNull);
      });

      test('parses sketch_image with metadata containing image_url', () {
        final json = {
          'type': 'sketch_image',
          'text': '',
          'metadata': {
            'image_url': 'https://cdn.example.com/images/chloroplast.jpg',
            'filename': 'chloroplast.jpg',
            'source': 'openverse',
            'license': 'CC-BY-4.0',
          },
        };

        final action = DrawingAction.fromJson(json);

        expect(action.type, 'sketch_image');
        expect(action.imageUrl, isNull); // Direct field is null
        expect(action.resolvedImageUrl, 'https://cdn.example.com/images/chloroplast.jpg');
        expect(action.filename, 'chloroplast.jpg');
        expect(action.metadata?['source'], 'openverse');
        expect(action.metadata?['license'], 'CC-BY-4.0');
      });

      test('resolvedImageUrl prefers imageUrl over metadata', () {
        final json = {
          'type': 'sketch_image',
          'text': '',
          'image_url': 'https://primary.example.com/image.png',
          'metadata': {
            'image_url': 'https://fallback.example.com/image.png',
          },
        };

        final action = DrawingAction.fromJson(json);

        // imageUrl field takes precedence
        expect(action.resolvedImageUrl, 'https://primary.example.com/image.png');
      });

      test('handles missing placement with defaults', () {
        final json = {
          'type': 'sketch_image',
          'text': '',
          'image_url': 'https://example.com/image.png',
          // No placement specified
        };

        final action = DrawingAction.fromJson(json);

        expect(action.placement, isNull);

        // Defaults from helper getter
        final pv = action.placementValues;
        expect(pv.x, 0.0);
        expect(pv.y, 0.0);
        expect(pv.width, 200.0);
        expect(pv.height, 200.0);
        expect(pv.scale, isNull);
      });

      test('handles missing text field gracefully', () {
        final json = {
          'type': 'sketch_image',
          // text field is missing entirely
          'image_url': 'https://example.com/image.png',
        };

        final action = DrawingAction.fromJson(json);

        expect(action.text, ''); // Defaults to empty string
        expect(action.imageUrl, 'https://example.com/image.png');
      });

      test('handles null text field gracefully', () {
        final json = <String, dynamic>{
          'type': 'sketch_image',
          'text': null,
          'image_url': 'https://example.com/image.png',
        };

        final action = DrawingAction.fromJson(json);

        expect(action.text, ''); // Defaults to empty string
      });
    });

    group('toJson serialization', () {
      test('serializes standard action', () {
        final action = DrawingAction(
          type: 'heading',
          text: 'Test Heading',
          level: 1,
        );

        final json = action.toJson();

        expect(json['type'], 'heading');
        expect(json['text'], 'Test Heading');
        expect(json['level'], 1);
        expect(json.containsKey('image_url'), false);
        expect(json.containsKey('placement'), false);
      });

      test('serializes sketch_image action', () {
        final action = DrawingAction(
          type: 'sketch_image',
          text: '',
          imageUrl: 'https://example.com/image.png',
          placement: {'x': 100.0, 'y': 200.0, 'width': 300.0, 'height': 250.0},
        );

        final json = action.toJson();

        expect(json['type'], 'sketch_image');
        expect(json['text'], '');
        expect(json['image_url'], 'https://example.com/image.png');
        expect(json['placement']['x'], 100.0);
        expect(json['placement']['width'], 300.0);
      });

      test('round-trip serialization preserves data', () {
        final original = DrawingAction(
          type: 'sketch_image',
          text: 'Diagram of photosynthesis',
          imageUrl: 'https://example.com/photo.jpg',
          imageBase64: 'base64data...',
          placement: {'x': 10.0, 'y': 20.0, 'width': 100.0, 'height': 80.0, 'scale': 2.0},
          metadata: {'source': 'openverse', 'filename': 'photo.jpg'},
          timingHint: 'medium',
          style: {'opacity': 0.9},
        );

        final json = original.toJson();
        final restored = DrawingAction.fromJson(json);

        expect(restored.type, original.type);
        expect(restored.text, original.text);
        expect(restored.imageUrl, original.imageUrl);
        expect(restored.imageBase64, original.imageBase64);
        expect(restored.placement?['x'], original.placement?['x']);
        expect(restored.placement?['scale'], original.placement?['scale']);
        expect(restored.metadata?['source'], original.metadata?['source']);
        expect(restored.timingHint, original.timingHint);
        expect(restored.style?['opacity'], original.style?['opacity']);
      });
    });

    group('TimelineSegment with sketch_image actions', () {
      test('parses segment containing mixed action types', () {
        final json = {
          'sequence': 1,
          'start_time': 0.0,
          'end_time': 15.0,
          'speech_text': 'Let me show you photosynthesis...',
          'audio_file': '/media/audio/segment_1.wav',
          'actual_audio_duration': 14.5,
          'drawing_actions': [
            {'type': 'heading', 'text': 'Photosynthesis'},
            {
              'type': 'sketch_image',
              'text': '',
              'image_url': 'https://example.com/chloroplast.png',
              'placement': {'x': 400.0, 'y': 100.0, 'width': 300.0, 'height': 200.0},
            },
            {'type': 'bullet', 'text': 'Light reaction', 'level': 1},
          ],
        };

        final segment = TimelineSegment.fromJson(json);

        expect(segment.drawingActions.length, 3);
        expect(segment.drawingActions[0].type, 'heading');
        expect(segment.drawingActions[1].type, 'sketch_image');
        expect(segment.drawingActions[1].isSketchImage, true);
        expect(segment.drawingActions[1].imageUrl, 'https://example.com/chloroplast.png');
        expect(segment.drawingActions[2].type, 'bullet');
      });
    });
  });
}







