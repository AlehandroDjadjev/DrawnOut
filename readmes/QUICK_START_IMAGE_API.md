# 🚀 Quick Start: Image Researcher API

## 1. Install Dependencies (if not already done)

```bash
cd DrawnOut/backend
pip install -r requirements.txt
python -c "import nltk; nltk.download('wordnet'); nltk.download('omw-1.4')"
```

## 2. Start Django Server

```bash
cd DrawnOut/backend
python manage.py runserver
```

## 3. Test the API

### Option A: Use the test script
```bash
# In a new terminal
cd DrawnOut/backend
python test_image_api.py
```

### Option B: Manual curl commands
```bash
# Get supported subjects
curl http://localhost:8000/api/image-research/subjects/

# List available sources
curl http://localhost:8000/api/image-research/sources/

# Search for images
curl -X POST http://localhost:8000/api/image-research/search/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Pythagorean Theorem",
    "subject": "Maths",
    "limit": 5
  }'
```

## 4. Check Results

Downloaded images will be saved to:
```
DrawnOut/backend/image_researcher/ResearchImages/
```

## Available Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/image-research/subjects/` | List supported subjects |
| GET | `/api/image-research/sources/` | List available image sources |
| POST | `/api/image-research/search/` | Search for images |
| POST | `/api/image-research/ddg-search/` | DuckDuckGo image search |

## Example: Search Request

```json
{
  "query": "Prokaryotic Cells",
  "subject": "Biology",
  "limit": 10,
  "sources": ["openstax", "wikimedia"]
}
```

## Example: Response

```json
{
  "ok": true,
  "results": [
    {
      "source": "openstax",
      "images": [
        "backend/image_researcher/ResearchImages/prokaryotic_cell_1.jpg",
        "backend/image_researcher/ResearchImages/prokaryotic_cell_2.jpg"
      ],
      "count": 2
    }
  ],
  "total_images": 2,
  "query": "Prokaryotic Cells",
  "subject": "Biology"
}
```

## Troubleshooting

### "Imageresearcher module not available"
- Make sure all dependencies are installed
- Check that `Imageresearcher.py` is in `backend/image_researcher/`

### "No images found"
- Check internet connection
- Try different sources
- Increase the limit parameter

### NLTK data not found
```bash
python -c "import nltk; nltk.download('wordnet'); nltk.download('omw-1.4')"
```

---

**That's it!** 🎉 The image researcher is now accessible via REST API.

