# Image Researcher API Integration ✅

The `image_researcher` folder has been successfully integrated into the Django backend with REST API endpoints.

## What Was Done

### 1. **Files Copied**
- ✅ `Imageresearcher.py` → `backend/image_researcher/`
- ✅ `source_urls/*.json` → `backend/image_researcher/source_urls/`
- ✅ `requirements.txt` → `backend/image_researcher/`

### 2. **Django App Created**
- ✅ Created `backend/image_researcher/` as a Django app
- ✅ Added to `INSTALLED_APPS` in `backend/settings.py`
- ✅ URL routing configured at `/api/image-research/`

### 3. **Path Configuration Fixed**
- ✅ Replaced hardcoded Windows paths with relative paths
- ✅ Auto-creates `ResearchImages/` and `source_urls/` directories

### 4. **Dependencies Installed**
```bash
pip install beautifulsoup4 duckduckgo_search nltk tldextract lxml transformers tokenizers
python -c "import nltk; nltk.download('wordnet'); nltk.download('omw-1.4')"
```

## API Endpoints

### 1. **Search Images**
```bash
POST http://localhost:8000/api/image-research/search/
Content-Type: application/json

{
  "query": "Prokaryotic Cells",
  "subject": "Biology",
  "limit": 10,
  "sources": ["openstax", "wikimedia"]  // optional
}
```

**Response:**
```json
{
  "ok": true,
  "results": [
    {
      "source": "openstax",
      "images": ["path/to/image1.jpg", "path/to/image2.jpg"],
      "count": 2
    }
  ],
  "total_images": 2
}
```

### 2. **List Sources**
```bash
GET http://localhost:8000/api/image-research/sources/
```

Returns available sources (openstax, wikimedia, plos, usgs, openverse).

### 3. **Get Subjects**
```bash
GET http://localhost:8000/api/image-research/subjects/
```

Returns: `["Maths", "Physics", "Biology", "Chemistry", "Geography"]`

### 4. **DuckDuckGo Search**
```bash
POST http://localhost:8000/api/image-research/ddg-search/
Content-Type: application/json

{
  "query": "Biology Prokaryotic Cells diagram",
  "max_results": 100
}
```

## Testing

### Run the test script:
```bash
# Terminal 1: Start Django server
cd DrawnOut/backend
python manage.py runserver

# Terminal 2: Run tests
python test_image_api.py
```

### Manual test with curl:
```bash
# Get subjects
curl http://localhost:8000/api/image-research/subjects/

# Search images
curl -X POST http://localhost:8000/api/image-research/search/ \
  -H "Content-Type: application/json" \
  -d '{"query": "Pythagorean Theorem", "subject": "Maths", "limit": 5}'
```

## File Structure

```
backend/
├── image_researcher/
│   ├── __init__.py
│   ├── apps.py
│   ├── models.py
│   ├── admin.py
│   ├── views.py              # API endpoint implementations
│   ├── urls.py               # URL routing
│   ├── Imageresearcher.py    # Core logic (copied & adapted)
│   ├── source_urls/          # Source configurations
│   │   ├── openstax.json
│   │   ├── wikimedia.json
│   │   ├── plos.json
│   │   ├── usgs.json
│   │   └── openverse.json
│   ├── ResearchImages/       # Downloaded images (auto-created)
│   └── README.md
├── backend/
│   ├── settings.py          # Added 'image_researcher' to INSTALLED_APPS
│   └── urls.py              # Added path('api/image-research/', ...)
├── requirements.txt         # Updated with new dependencies
└── test_image_api.py        # Test script
```

## How It Works

1. **API Request** → Django view (`views.py`)
2. **Import Imageresearcher module** → Call functions like `read_sources()`, `send_request()`, `handle_result_no_api()`
3. **Process & Download Images** → Save to `ResearchImages/`
4. **Return JSON Response** → List of image paths

## Integration with Flutter

Update your Flutter app to call these endpoints:

```dart
// Example: Search for images
final response = await http.post(
  Uri.parse('http://localhost:8000/api/image-research/search/'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'query': 'Pythagorean Theorem',
    'subject': 'Maths',
    'limit': 10,
  }),
);

final data = jsonDecode(response.body);
if (data['ok']) {
  final images = data['results'];
  // Use images...
}
```

## Next Steps

1. ✅ **Test the API** using `test_image_api.py`
2. **Integrate with timeline generation** - Add image search to lesson creation
3. **Frontend integration** - Call from Flutter app
4. **Image caching** - Implement caching to avoid re-downloading
5. **Error handling** - Add retry logic for failed downloads

---

**Status:** ✅ Complete and ready to use!

