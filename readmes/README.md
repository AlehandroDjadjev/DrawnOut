# DrawnOut  Local Dev Setup

This guide covers setting up API keys, environment variables, and running the Django backend with the built-in test UI.

## Prerequisites
- Python 3.11+ installed and on PATH
- Windows PowerShell (instructions use Windows paths)
- A Google Cloud service account JSON with Text-to-Speech enabled
- Optional: OpenAI API key (improves natural language explanations and audio transcription)

## 1) Place your Google service account JSON
Put your JSON inside `backend/` (example):

- `backend/drawnout-1df5ef7d6899.json`

Make sure Text-to-Speech API is enabled for the project and the service account has permission to use it.

## 2) Create the backend .env
Create `backend/.env` with the following content. Update the JSON path to match your machine.

```ini
# Environment variables for the Django backend
OPENAI_API_KEY=
GOOGLE_APPLICATION_CREDENTIALS="C:\\Users\\<you>\\Documents\\GitHub\\DrawnOut\\DrawnOut\\backend\\drawnout-1df5ef7d6899.json"
DJANGO_DEBUG=True
```

Notes:
- `OPENAI_API_KEY` is optional. If set, the tutor produces more natural kid-friendly speech and can transcribe recorded questions.
- `GOOGLE_APPLICATION_CREDENTIALS` must be an absolute path to your service account JSON.

## 3) Create and activate a virtual environment
From the project backend directory:

```powershell
cd C:\\Users\\<you>\\Documents\\GitHub\\DrawnOut\\DrawnOut\\backend
python -m venv .venv
.\\.venv\\Scripts\\Activate.ps1
python -m pip install -U pip
```

If PowerShell blocks activation, temporarily allow it:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

## 4) Install dependencies
If you don't have a requirements file, install directly:

```powershell
pip install Django djangorestframework djangorestframework-simplejwt django-cors-headers pillow openai google-cloud-texttospeech python-dotenv
```

## 5) Run migrations and start the server
```powershell
python manage.py migrate
python manage.py runserver
```

Then open `http://127.0.0.1:8000/` for the test UI.

## 6) Using the test UI
- Start Lesson: begins a session and speaks the first segment
- Raise Hand: opens a short window to ask a typed or recorded question; the tutor answers, then continues
- It auto-advances if you dont raise your hand

Audio notes:
- Google TTS voice is set to a natural female voice. If Google TTS isnt available, the browser will use a female fallback voice.
- Ensure your system output and browser tab arent muted.

## 7) Environment variables summary
- `OPENAI_API_KEY`: Optional. Enables richer, kid-friendly text and transcription.
- `GOOGLE_APPLICATION_CREDENTIALS`: Absolute path to your Google service account JSON with TTS enabled.
- `DJANGO_DEBUG`: Optional. `True` for local dev (default in `.env`).

## 8) Repository ignores under backend
The repo is configured to keep only Python files under `backend/` in Git. Local files like `.env`, `*.sqlite3`, media, and HTML templates remain untracked for development convenience.
