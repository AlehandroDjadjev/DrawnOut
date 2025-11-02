# 🧪 Test the Fix Now!

## What Was Fixed

**Problem**: `Object of type bytes is not JSON serializable`

**Root Cause**: Audio content (bytes) was being stored in the segment dictionary, which Django tried to serialize to JSON.

**Solution**: 
1. Store audio bytes separately in `audio_contents` dict
2. Extract before JSON serialization with `timeline_data.pop('_audio_contents', {})`
3. Use extracted bytes only for saving files to disk
4. Timeline dict now only contains strings and numbers (JSON-safe)

---

## Test Right Now

### Option 1: Full Test (With Audio)

**Requirements**: 
- `OPENAI_API_KEY` set
- `GOOGLE_APPLICATION_CREDENTIALS` set

```bash
# Make sure backend is running
cd DrawnOut/backend
python manage.py runserver
```

Then in Flutter app, click **"🎯 SYNCHRONIZED Lesson"**

---

### Option 2: Quick Test (No Audio, Just Timeline)

```bash
cd DrawnOut/backend
python test_timeline.py
```

This will:
- ✅ Test GPT-4 timeline generation
- ✅ Show generated segments
- ⏭️ Skip audio synthesis (faster)

---

## Expected Output (Success)

### Backend Console:
```
INFO Generating timeline for session 116, topic: Pythagorean Theorem
INFO Timeline generated with 8 segments
INFO Synthesizing audio for segments...
INFO Synthesized segment 1: 4.2s
INFO Synthesized segment 2: 5.1s
...
INFO Timeline 1 created successfully with 8 segments
```

### Frontend Console:
```
🎬 Starting synchronized lesson...
✅ Session created: 116
⏱️ Generating timeline... (this may take 30-60 seconds)
✅ Timeline generated: 8 segments, 62.3s
▶️ Starting synchronized playback...
🎬 Playing segment 0: "Let's start by understanding..."
🎨 Drawing 1 synchronized actions
```

---

## If Still Getting Errors

### Check Django Logs

Look for detailed error in terminal running Django:

```bash
python manage.py runserver
# Watch for ERROR or WARNING messages
```

### Common Issues:

**"OPENAI_API_KEY not set"**
```bash
# Add to DrawnOut/backend/.env
OPENAI_API_KEY=sk-proj-...
```

**"Google TTS initialization failed"**
```bash
# Add to DrawnOut/backend/.env
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
```

**Still getting bytes error**
- Clear Django cache: `python manage.py migrate --run-syncdb`
- Restart Django server
- Check that you pulled latest changes

---

## Verify Fix Applied

Check that `services.py` line ~235 has:

```python
# Store audio contents separately for the view to access
timeline['_audio_contents'] = audio_contents

return timeline
```

And `views.py` line ~79 has:

```python
# Extract audio contents (stored separately to avoid JSON serialization issues)
audio_contents = timeline_data.pop('_audio_contents', {})
```

---

## 🎯 Test Now!

1. Save all files
2. Restart Django: `Ctrl+C` then `python manage.py runserver`
3. Click green button in Flutter app
4. Should work! ✅

---

**The JSON serialization error is now fixed!** 🎉



