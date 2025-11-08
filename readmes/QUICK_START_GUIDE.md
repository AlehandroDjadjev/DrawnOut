# Quick Start Guide: Synchronized Speech-Drawing System

## Overview
This system ensures the tutor's speech EXACTLY matches what appears on the whiteboard, eliminating confusion from divergent audio and visual content.

## How It Works (Simple Version)

```
1. Input: Lesson topic + content
   ↓
2. GPT-4 generates synchronized timeline:
   - "Let's draw a triangle" → [Draw: TRIANGLE heading]
   - "This is side a" → [Draw: label "a"]
   ↓
3. Google TTS creates audio for each segment
   ↓
4. Flutter plays audio + triggers drawing at exact moments
```

## Implementation Steps (For Cursor)

### Step 1: Install Backend Dependencies (5 min)

```bash
cd DrawnOut/backend
pip install librosa soundfile
```

Add to `requirements.txt`:
```
librosa==0.10.1
soundfile==0.12.1
```

### Step 2: Create Timeline Generator App (10 min)

```bash
python manage.py startapp timeline_generator
```

Add to `settings.py`:
```python
INSTALLED_APPS = [
    # ...
    'timeline_generator',
]
```

Copy files from `IMPLEMENTATION_PLAN.md` Phase 1:
- `models.py`
- `services.py`
- `prompts.py`
- `views.py`
- `urls.py`

### Step 3: Run Migrations (2 min)

```bash
python manage.py makemigrations timeline_generator
python manage.py migrate
```

### Step 4: Update Main URLs (2 min)

In `backend/urls.py`:
```python
urlpatterns = [
    # ...
    path('api/timeline/', include('timeline_generator.urls')),
]
```

### Step 5: Add Frontend Models (5 min)

Create `DrawnOut/whiteboard_demo/lib/models/timeline.dart` with code from plan.

### Step 6: Add Playback Controller (10 min)

Create `DrawnOut/whiteboard_demo/lib/controllers/timeline_playback_controller.dart`

Add to `pubspec.yaml`:
```yaml
dependencies:
  just_audio: ^0.9.36
```

Run:
```bash
flutter pub get
```

### Step 7: Integrate into Main App (10 min)

Add timeline controller and button to `main.dart` (see Phase 2.3 in plan).

### Step 8: Test! (5 min)

1. Start Django: `python manage.py runserver`
2. Start Flutter: `flutter run -d chrome`
3. Click "Start Synchronized Lesson"
4. Watch speech and drawing sync perfectly!

---

## API Endpoints

### Generate Timeline
```http
POST /api/timeline/generate/<session_id>/
Content-Type: application/json

{
  "duration_target": 60.0
}
```

**Response:**
```json
{
  "timeline_id": 123,
  "segments": [
    {
      "sequence": 1,
      "start_time": 0.0,
      "end_time": 4.5,
      "speech_text": "Let's start with the Pythagorean theorem",
      "audio_file": "segment_1_123456.mp3",
      "actual_audio_duration": 4.3,
      "drawing_actions": [
        {
          "type": "heading",
          "text": "PYTHAGOREAN THEOREM"
        }
      ]
    }
  ],
  "total_duration": 62.5
}
```

---

## Testing Checklist

- [ ] Timeline generates in < 10 seconds
- [ ] Audio files are created
- [ ] Flutter plays audio smoothly
- [ ] Text appears AS tutor says it (not before/after)
- [ ] Multiple segments transition smoothly
- [ ] Pause/resume works
- [ ] Timeline survives app restart

---

## Troubleshooting

**Problem**: "Timeline returned null"  
**Fix**: Check `OPENAI_API_KEY` in backend `.env`

**Problem**: "Audio won't play"  
**Fix**: Check CORS settings, ensure media files are accessible

**Problem**: "Drawing happens too early/late"  
**Fix**: Adjust `overrideSeconds` in `_handleSyncedDrawingActions`

**Problem**: "GPT-4 generates poor timelines"  
**Fix**: Improve prompt in `prompts.py`, add examples

---

## Performance Tips

1. **Cache timelines**: Don't regenerate for same lesson
2. **Preload audio**: Load next segment while current plays
3. **Batch TTS**: Generate all audio in parallel
4. **Use CDN**: Serve audio files from CDN for faster loading

---

## Cost Optimization

- Use `gpt-4o-mini` instead of `gpt-4-turbo` → Save 90%
- Cache popular lesson timelines → Save API calls
- Use cheaper TTS (AWS Polly) → Save 50% on audio

---

## Next Steps After MVP

1. ✅ Get basic sync working
2. Add diagram generation pipeline
3. Add user controls (speed, pause)
4. A/B test with real students
5. Optimize timing based on feedback
6. Add multi-language support

---

## Key Files Reference

**Backend:**
- `backend/timeline_generator/services.py` - Core generation logic
- `backend/timeline_generator/prompts.py` - LLM prompt engineering
- `backend/timeline_generator/views.py` - API endpoints

**Frontend:**
- `lib/models/timeline.dart` - Data models
- `lib/controllers/timeline_playback_controller.dart` - Playback logic
- `lib/main.dart` - Integration point

---

## Example Timeline JSON

```json
{
  "segments": [
    {
      "sequence": 1,
      "speech_text": "Let's explore the Pythagorean theorem",
      "start_time": 0.0,
      "end_time": 3.8,
      "drawing_actions": [
        {"type": "heading", "text": "PYTHAGOREAN THEOREM"}
      ]
    },
    {
      "sequence": 2,
      "speech_text": "The formula is a squared plus b squared equals c squared",
      "start_time": 3.8,
      "end_time": 8.2,
      "drawing_actions": [
        {"type": "formula", "text": "a² + b² = c²"}
      ]
    },
    {
      "sequence": 3,
      "speech_text": "Where a and b are the legs",
      "start_time": 8.2,
      "end_time": 10.5,
      "drawing_actions": [
        {"type": "bullet", "text": "a, b = legs", "level": 1}
      ]
    }
  ]
}
```

Notice how:
- Speech timing is cumulative
- Each segment has exactly ONE audio clip
- Drawing actions trigger at segment start
- Speech describes what's being drawn

---

## Success Metrics

Track these after deployment:

1. **Sync Accuracy**: Measure time between speech mention and visual appearance (target: < 300ms)
2. **User Comprehension**: Test quiz scores (target: +20% vs old system)
3. **Engagement**: Track how long students watch (target: watch 80%+ of lesson)
4. **Generation Time**: Timeline + audio creation (target: < 45s)
5. **Error Rate**: % of timelines that fail (target: < 2%)

---

**Ready to implement? Start with Step 1 above! 🚀**




