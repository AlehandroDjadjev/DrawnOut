# ✅ ImgGen App Integration Complete

## Summary

The `imggen` app from `image_researcher/whiteboard/imggen/` has been **successfully copied** into the Django backend and **integrated as a Django app**.

---

## What Was Done

### 1. **Files Copied** ✅
```
image_researcher/whiteboard/imggen/  →  backend/imggen/
├── __init__.py
├── admin.py
├── apps.py
├── models.py
├── tests.py
├── urls.py
├── views.py
└── migrations/
    └── __init__.py

image_researcher/whiteboard/Model_Fasr.json  →  backend/imggen/Model_Fasr.json
```

### 2. **Django Integration** ✅
- ✅ Added `'imggen'` to `INSTALLED_APPS` in `backend/settings.py`
- ✅ Added URL routing: `path('api/imggen/', include('imggen.urls'))`
- ✅ Fixed `_base_dir()` to point to imggen directory (not parent.parent)
- ✅ Verified with `python manage.py check` - no errors

### 3. **Configuration Updates** ✅
**Fixed path in views.py:**
```python
# Before
def _base_dir() -> Path:
    return Path(__file__).resolve().parent.parent

# After
def _base_dir() -> Path:
    return Path(__file__).resolve().parent
```

This ensures `Model_Fasr.json` is found in the imggen directory.

---

## API Endpoint

### POST `/api/imggen/generate/`

Generate images using ComfyUI workflows.

**Request:**
```json
{
  "prompts": ["a cat", "a dog", "a mountain landscape"],
  "path_out": "outputs",           // optional
  "seed": 12345,                    // optional (increments per prompt)
  "steps": 4,                       // optional
  "cfg": 1.0                        // optional
}
```

**Response:**
```json
{
  "ok": true,
  "results": [
    {
      "prompt": "a cat",
      "saved": ["backend/outputs/gen_1699000000_abc123.png"]
    },
    {
      "prompt": "a dog",
      "saved": ["backend/outputs/gen_1699000001_def456.png"]
    },
    {
      "prompt": "a mountain landscape",
      "saved": ["backend/outputs/gen_1699000002_ghi789.png"]
    }
  ]
}
```

---

## Requirements

### External Service: ComfyUI
The app requires **ComfyUI** to be running locally:
```bash
# ComfyUI must be accessible at:
http://127.0.0.1:8188
```

### Python Dependencies (Already Installed)
- `transformers` ✅
- `tokenizers` ✅
- `requests` ✅

---

## Testing

### Manual Test
```bash
# 1. Start ComfyUI (in separate terminal)
# Make sure it's running at http://127.0.0.1:8188

# 2. Start Django server
cd DrawnOut/backend
python manage.py runserver

# 3. Test the endpoint
curl -X POST http://localhost:8000/api/imggen/generate/ \
  -H "Content-Type: application/json" \
  -d '{
    "prompts": ["a beautiful sunset", "a cat"],
    "seed": 42,
    "steps": 4,
    "cfg": 1.0
  }'
```

### Python Test
```python
import requests

response = requests.post(
    'http://localhost:8000/api/imggen/generate/',
    json={
        'prompts': ['educational diagram of DNA structure'],
        'seed': 42,
        'steps': 20
    }
)

result = response.json()
print(result)
```

---

## How It Works

```
┌──────────────┐
│   Client     │
│  (Flutter)   │
└──────┬───────┘
       │ POST /api/imggen/generate/
       │ {"prompts": [...]}
       ▼
┌─────────────────────────────────┐
│    Django Backend (imggen)      │
│  ┌───────────────────────────┐  │
│  │  views.py                 │  │
│  │  - Pad prompts (77 tokens)│  │
│  │  - Load Model_Fasr.json   │  │
│  │  - Set prompt & sampler   │  │
│  └───────────┬───────────────┘  │
└──────────────┼──────────────────┘
               │
               ▼
┌─────────────────────────────────┐
│       ComfyUI (localhost:8188)  │
│  - Process workflow             │
│  - Generate images              │
│  - Return via /history & /view  │
└───────────────┬─────────────────┘
                │
                ▼
┌─────────────────────────────────┐
│   Save to backend/outputs/      │
│   - gen_<timestamp>_<uuid>.png  │
└───────────────┬─────────────────┘
                │
                ▼
        ┌───────────────┐
        │ Return paths  │
        │ in JSON       │
        └───────────────┘
```

---

## File Structure

```
backend/
├── imggen/                      # ✅ NEW Django app
│   ├── __init__.py
│   ├── apps.py                  # ImggenConfig
│   ├── models.py                # No models (stateless)
│   ├── admin.py                 # No admin
│   ├── views.py                 # generate_images_batch()
│   ├── urls.py                  # path("generate/", ...)
│   ├── Model_Fasr.json          # ComfyUI workflow
│   ├── migrations/
│   └── README.md                # Documentation
├── outputs/                     # Generated images (auto-created)
├── backend/
│   ├── settings.py              # Added 'imggen' to INSTALLED_APPS
│   └── urls.py                  # Added path('api/imggen/', ...)
└── manage.py
```

---

## Configuration

### Workflow File
- **Location**: `backend/imggen/Model_Fasr.json`
- **Node IDs** (can be customized in `views.py`):
  - `POS_NODE_ID = "8"` - Text encoder node
  - `KS_NODE_ID = "14"` - Sampler node

### Prompt Tokenization
```python
PAD_PROMPTS = True
TOKENIZER_NAME = "openai/clip-vit-base-patch32"
TARGET_TOKENS = 77  # CLIP token limit
```

Prompts are automatically padded/truncated to 77 tokens to ensure consistent model behavior.

---

## Integration Examples

### Generate Lesson Diagrams
```python
# In timeline_generator or lessons app
import requests

def generate_educational_image(topic: str) -> str:
    """Generate an educational diagram for a topic"""
    prompt = f"Educational diagram showing {topic}, textbook style, clear, simple"
    
    response = requests.post(
        'http://localhost:8000/api/imggen/generate/',
        json={
            'prompts': [prompt],
            'seed': 42,
            'steps': 20,
            'cfg': 7.5
        }
    )
    
    result = response.json()['results'][0]
    if 'saved' in result and result['saved']:
        return result['saved'][0]
    else:
        raise Exception(f"Image generation failed: {result.get('error')}")
```

### Flutter Integration
```dart
class ImageGenService {
  final String baseUrl = 'http://localhost:8000/api/imggen';
  
  Future<List<String>> generateImages({
    required List<String> prompts,
    int? seed,
    int? steps,
    double? cfg,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/generate/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'prompts': prompts,
        if (seed != null) 'seed': seed,
        if (steps != null) 'steps': steps,
        if (cfg != null) 'cfg': cfg,
      }),
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['results']
        .map((r) => r['saved'] as List)
        .expand((l) => l)
        .cast<String>()
        .toList();
    }
    throw Exception('Failed to generate images');
  }
}
```

---

## Troubleshooting

### ❌ Connection Error
**Error**: `Connection refused` or `Failed to connect to ComfyUI`

**Solution**: Make sure ComfyUI is running at `http://127.0.0.1:8188`

### ❌ Workflow Not Found
**Error**: `Workflow not found: .../Model_Fasr.json`

**Solution**: 
- Check that `Model_Fasr.json` exists in `backend/imggen/`
- Run: `dir DrawnOut\backend\imggen\Model_Fasr.json` (Windows)

### ❌ Node ID Mismatch
**Error**: `Workflow missing node id '8'`

**Solution**:
1. Open `Model_Fasr.json` in a text editor
2. Find your CLIPTextEncode node ID
3. Update `POS_NODE_ID` in `views.py`

### ❌ Timeout
**Error**: `Timeout waiting for outputs`

**Solution**:
- ComfyUI might be processing a heavy workflow
- Increase `POLL_MAX_S` in `views.py` (default: 300s)
- Check ComfyUI console for errors

---

## Key Features

✅ **Batch Processing** - Generate multiple images from multiple prompts  
✅ **Token Padding** - Ensures consistent model behavior  
✅ **Seed Incrementing** - Automatic variation in batch generations  
✅ **Flexible Output** - Custom output directory support  
✅ **Error Handling** - Per-prompt error reporting  
✅ **CSRF Exempt** - Ready for API access  

---

## Next Steps

1. **Test with ComfyUI** ✅
   - Start ComfyUI
   - Test the endpoint with curl or Python

2. **Integrate with Timeline Generation**
   - Add image generation to lesson creation workflow
   - Generate diagrams for educational content

3. **Flutter Integration**
   - Create Flutter service to call the API
   - Display generated images in lessons

4. **Optimization**
   - Implement caching for repeated prompts
   - Add image compression
   - Store generation metadata

---

## Status: ✅ **COMPLETE**

The imggen app is fully integrated and ready to use!

**Requirements:**
- ✅ Django app configured
- ✅ URL routing set up
- ⚠️ **Requires ComfyUI running at `http://127.0.0.1:8188`**

**Test it:**
```bash
python manage.py check  # Verify configuration
# Start ComfyUI, then:
curl -X POST http://localhost:8000/api/imggen/generate/ \
  -H "Content-Type: application/json" \
  -d '{"prompts": ["a cat"]}'
```

🎉 **Done!**

