# 🧪 Lesson Pipeline Test Guide

## Quick Test Instructions

### 1. Start Backend Services

```bash
# Terminal 1: Start Django
cd DrawnOut/backend
python manage.py runserver

# Terminal 2: (Optional) Start ComfyUI for img2img
cd /path/to/ComfyUI
python main.py
```

### 2. Start Flutter App

```bash
cd DrawnOut/whiteboard_demo
flutter run
```

### 3. Test the Pipeline

1. **In the Flutter app**, enter backend URL: `http://localhost:8000`
2. Click the **purple button**: `🎨 AI LESSON with Images`
3. Wait 60-150 seconds (progress dialog will show)
4. See results dialog with:
   - Generated lesson content
   - List of matched/transformed images
   - Image prompts and URLs

---

## What Happens Behind the Scenes

### Step 1: Research (30-60s)
```
- Searches openstax, wikimedia, plos, usgs, openverse
- Finds ~40 educational images
- Embeds with SigLIP2 Giant OPT (1536-dim)
- Stores in Pinecone
```

### Step 2: Script Generation (10-30s)
```
- GPT-4 generates lesson script
- Adds [IMAGE ...] tags for visuals
- Returns structured content
```

### Step 3: Image Matching (5-10s)
```
- Parses IMAGE tags from script
- Embeds tag prompts with SigLIP2
- Queries Pinecone for best matches
- Returns base images
```

### Step 4: Transformation (30-90s)
```
- For each matched image:
  - Loads base image
  - Applies tag prompt + style via ComfyUI
  - Generates final customized image
```

### Step 5: Assembly (<1s)
```
- Injects images into script as markdown
- Returns complete lesson
```

---

## Expected Output

### Success Dialog
```
✅ Lesson Generated!

Images: 3
Indexed: 40

Content:
# Pythagorean Theorem

The Pythagorean theorem is fundamental...

![right triangle diagram](https://...){.lesson-image}

...

Images:
• right triangle with labeled sides a, b, c
  Style: scientific diagram
  Final: backend/lesson_pipeline_outputs/gen_....png

• Pythagorean theorem proof visualization
  Style: educational illustration
  Final: backend/lesson_pipeline_outputs/gen_....png

• real-world application of Pythagorean theorem
  Style: photo
  Final: backend/lesson_pipeline_outputs/gen_....png
```

---

## Troubleshooting

### Progress Dialog Stuck
- Check Django console for errors
- Look for: `❌ Lesson pipeline error:`
- Common issues:
  - Pinecone API key not set
  - No internet connection (for image research)
  - SigLIP model download in progress

### "Connection refused"
- Verify Django is running: `curl http://localhost:8000/api/lesson-pipeline/health/`
- Check backend URL in Flutter app

### "ComfyUI connection refused"
- Pipeline will work without ComfyUI
- Base images will be used instead of transformed ones
- Or start ComfyUI at `http://127.0.0.1:8188`

### Images list is empty
- Check image research succeeded
- Try different subject or prompt
- Verify internet connection

---

## Testing Different Topics

Edit `main.dart` line ~901:

```dart
// Change topic here
final lesson = await pipelineApi.generateLesson(
  prompt: 'Explain DNA structure',  // ← Change this
  subject: 'Biology',                // ← And this
  durationTarget: 60.0,
);
```

**Supported subjects:**
- Maths
- Physics
- Biology
- Chemistry
- Geography
- General (default)

---

## Viewing Generated Images

Images are saved to:
```
DrawnOut/backend/lesson_pipeline_outputs/gen_<timestamp>_<uuid>.png
```

Or if using imggen:
```
DrawnOut/backend/outputs/gen_<timestamp>_<uuid>.png
```

---

## Health Check

Before testing, verify all services:

```bash
curl http://localhost:8000/api/lesson-pipeline/health/
```

Should return:
```json
{
  "ok": true,
  "services": {
    "embeddings": {"available": true, "model": "google/siglip2-giant-opt-patch16-384"},
    "vector_store": {"available": true, "stats": {...}},
    "image_researcher": {"available": true},
    "script_writer": {"available": true},
    "image_to_image": {"available": true/false}
  }
}
```

---

## Performance Expectations

| Stage | Time | Notes |
|-------|------|-------|
| Image research | 30-60s | Network dependent |
| Script generation | 10-30s | GPT-4 latency |
| Image matching | 5-10s | SigLIP + Pinecone |
| Transformation | 30-90s | ComfyUI (optional) |
| **Total** | **75-180s** | With all services |

Without ComfyUI: **45-100s**

---

## Next Steps

After successful test:
1. Render images on whiteboard (display generated images)
2. Parse markdown content (show text with images)
3. Add prompt input field (custom topics)
4. Cache results (avoid regenerating)

---

## Success Criteria

✅ Button appears and is clickable
✅ Progress dialog shows
✅ Backend processes request (check Django logs)
✅ Success dialog appears with content
✅ Images list is populated
✅ No errors in console

**If all checks pass, the pipeline is working!** 🎉


