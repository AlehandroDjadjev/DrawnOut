# 🚀 Quick Reference - Synchronized Timeline System

## One-Command Setup

```bash
# From DrawnOut/backend directory
python manage.py makemigrations timeline_generator && python manage.py migrate && pip install pydub
```

## Start Everything

```bash
# Terminal 1 - Backend
cd DrawnOut/backend && python manage.py runserver

# Terminal 2 - Frontend  
cd DrawnOut/whiteboard_demo && flutter run -d chrome
```

## Test

1. Open app in Chrome
2. Click **"🎯 SYNCHRONIZED Lesson"** (green button)
3. Wait ~45 seconds
4. Watch synchronized magic!

## Key Files

| File | Purpose |
|------|---------|
| `backend/timeline_generator/services.py` | GPT-4 timeline generation |
| `backend/timeline_generator/prompts.py` | LLM prompts |
| `whiteboard_demo/lib/controllers/timeline_playback_controller.dart` | Playback logic |
| `whiteboard_demo/lib/main.dart` | UI integration |

## API Endpoints

```
POST /api/timeline/generate/<session_id>/
GET  /api/timeline/<timeline_id>/
GET  /api/timeline/session/<session_id>/
```

## Environment Variables Needed

```env
OPENAI_API_KEY=sk-...
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Timeline generation failed" | Check OPENAI_API_KEY |
| "No audio" | Check GOOGLE_APPLICATION_CREDENTIALS |
| "Out of sync" | Adjust `overrideSeconds` in `_handleSyncedDrawingActions` |
| Migration errors | `python manage.py migrate --run-syncdb` |

## Cost

~$0.07 per 60-second lesson

## All Done! ✅

All 8 implementation tasks completed successfully!



