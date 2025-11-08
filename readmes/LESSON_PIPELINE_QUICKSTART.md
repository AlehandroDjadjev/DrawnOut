# 🚀 Lesson Pipeline Quick Start

## 1. Install Dependencies

```bash
cd DrawnOut/backend
pip install pinecone-client torch
```

## 2. Configure Environment

Your `.env` already has most settings. Just verify:

```bash
# Should already be set:
Pinecone-API-Key=your_key
OPENAI_API_KEY=your_key
```

## 3. Start ComfyUI (Optional - for image transformation)

```bash
cd /path/to/ComfyUI
python main.py
# Should start at http://127.0.0.1:8188
```

## 4. Start Django

```bash
cd DrawnOut/backend
python manage.py runserver
```

## 5. Test It!

### Health Check
```bash
curl http://localhost:8000/api/lesson-pipeline/health/
```

### Generate Lesson
```bash
curl -X POST http://localhost:8000/api/lesson-pipeline/generate/ \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain the Pythagorean theorem",
    "subject": "Maths",
    "duration_target": 60.0
  }'
```

---

## What to Expect

**Response Time:** 60-150 seconds

**You'll get:**
- Complete lesson script
- 2-5 contextually relevant images
- Images customized to match lesson style
- Markdown format ready for display

**Example Output:**
```json
{
  "ok": true,
  "lesson": {
    "content": "# Pythagorean Theorem\n\n...![right triangle](url)...",
    "images": [...],
    "indexed_image_count": 40
  }
}
```

---

## Troubleshooting

**"Pinecone API key not configured"**
→ Add `Pinecone-API-Key=...` to `.env`

**"ComfyUI connection refused"**
→ Start ComfyUI or it will use base images (still works!)

**"SigLIP model loading..."**
→ First run downloads model (~2GB), be patient

---

## That's It! 🎉

The pipeline is fully integrated and ready to use.


