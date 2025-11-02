# Setup Instructions for Synchronized Timeline System

## 🚀 Quick Start

### Step 1: Install Backend Dependencies

```bash
cd DrawnOut/backend
pip install pydub
```

### Step 2: Run Django Migrations

```bash
python manage.py makemigrations timeline_generator
python manage.py migrate
```

### Step 3: Verify Environment Variables

Make sure your `DrawnOut/backend/.env` file contains:

```env
OPENAI_API_KEY=sk-...  # For GPT-4 timeline generation
GOOGLE_APPLICATION_CREDENTIALS=/path/to/google-credentials.json  # For TTS
GOOGLE_AI_API_KEY=...  # For Gemini (optional, for planner fallback)
```

### Step 4: Start Django Server

```bash
cd DrawnOut/backend
python manage.py runserver
```

### Step 5: Start Flutter App

```bash
cd DrawnOut/whiteboard_demo
flutter run -d chrome
```

### Step 6: Test Synchronized Lesson

1. Open the whiteboard app in Chrome
2. Make sure Backend URL is set to `http://localhost:8000`
3. Click the green **"🎯 SYNCHRONIZED Lesson"** button
4. Wait 30-60 seconds for timeline generation
5. Watch the tutor speak and draw in perfect sync!

---

## ✅ Verification Checklist

- [ ] Django migrations ran successfully
- [ ] `timeline_generator` app appears in Django admin
- [ ] `OPENAI_API_KEY` is set in `.env`
- [ ] Django server starts without errors
- [ ] Flutter app compiles and runs
- [ ] Green "SYNCHRONIZED Lesson" button appears in UI
- [ ] Clicking button shows "Generating timeline..." message
- [ ] Timeline generates successfully
- [ ] Audio plays and text appears simultaneously

---

## 🐛 Troubleshooting

### Error: "OPENAI_API_KEY not set"
**Fix**: Add `OPENAI_API_KEY=sk-...` to `DrawnOut/backend/.env`

### Error: "No module named 'pydub'"
**Fix**: Run `pip install pydub`

### Error: "Timeline generation failed"
**Check**: 
1. OpenAI API key is valid
2. You have GPT-4 API access
3. Check Django console for detailed errors

### Error: "Audio won't play"
**Check**:
1. Audio files were generated (check `DrawnOut/backend/media/timeline_audio/`)
2. Django is serving media files correctly
3. CORS is enabled in Django settings

### Timeline generates but nothing draws
**Check**:
1. Browser console for JavaScript errors
2. Flutter console for Dart errors
3. Verify `_handleSyncedDrawingActions` is being called

### Audio and drawing are out of sync
**Adjust**: In `main.dart`, change `overrideSeconds: 2.0` to a different value in `_handleSyncedDrawingActions`

---

## 📊 How It Works

```
User clicks "SYNCHRONIZED Lesson"
    ↓
Frontend calls /api/lessons/start → Create session
    ↓
Frontend calls /api/timeline/generate/<session_id>
    ↓
Backend: GPT-4 generates synchronized script
    ↓
Backend: Google TTS synthesizes audio for each segment
    ↓
Backend: Returns timeline JSON with audio URLs
    ↓
Frontend: Loads timeline into playback controller
    ↓
Frontend: Plays segment audio + triggers drawing actions
    ↓
When segment ends → Auto-play next segment
    ↓
Timeline complete!
```

---

## 🎯 Expected Behavior

**Good synchronization** looks like:
- Tutor says "Let's start with the Pythagorean theorem"
- Text "PYTHAGOREAN THEOREM" appears AS she says it
- Tutor says "The formula is a squared plus b squared equals c squared"
- Formula "a² + b² = c²" appears DURING the speech
- No lag between speech and visual

**Bad synchronization** (what we're fixing):
- ❌ Tutor talks about triangles while drawing formulas
- ❌ Text appears before it's mentioned
- ❌ Audio finishes but text still drawing

---

## 📝 Next Steps

1. **Test with different topics**: Modify topic in `_startSynchronizedLesson()`
2. **Adjust duration**: Change `durationTarget: 60.0` for longer/shorter lessons
3. **Fine-tune prompts**: Edit `DrawnOut/backend/timeline_generator/prompts.py`
4. **Add pause/resume**: Use `_timelineController!.pause()` and `play()`
5. **Add diagram generation**: Integrate with existing diagram pipeline

---

## 💰 Cost Estimate

Per synchronized lesson (60 seconds):
- GPT-4 API: ~$0.05
- Google TTS: ~$0.02
- **Total**: ~$0.07 per lesson

For 100 lessons/day = ~$7/day = ~$210/month

---

## 🔧 Development Tips

### To test timeline generation alone:
```python
# In Django shell
from timeline_generator.services import TimelineGeneratorService
from lessons.models import LessonSession

session = LessonSession.objects.first()
generator = TimelineGeneratorService()
timeline = generator.generate_timeline(
    lesson_plan={'lesson_plan': session.lesson_plan},
    topic=session.topic,
    duration_target=30.0
)
print(timeline)
```

### To test a single segment:
```dart
// In Flutter
final segment = TimelineSegment(
  sequence: 1,
  startTime: 0.0,
  endTime: 3.0,
  speechText: "Test speech",
  actualAudioDuration: 3.0,
  drawingActions: [
    DrawingAction(type: 'heading', text: 'TEST')
  ],
);
_handleSyncedDrawingActions(segment.drawingActions);
```

---

## 📚 Further Reading

- [Full Implementation Plan](IMPLEMENTATION_PLAN.md)
- [Quick Start Guide](QUICK_START_GUIDE.md)
- [OpenAI Realtime API Docs](https://platform.openai.com/docs/guides/realtime)
- [Google Cloud TTS](https://cloud.google.com/text-to-speech/docs)

---

**🎉 You're all set! Click that green button and watch the magic happen!**



