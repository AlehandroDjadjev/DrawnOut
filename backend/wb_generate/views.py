import sys
import json
from pathlib import Path

from django.http import HttpResponseNotAllowed, JsonResponse, Http404
from django.views.decorators.csrf import csrf_exempt

# Reuse the whiteboard_backend imggen implementation via a shimmed sys.path
WB_DIR = Path(__file__).resolve().parent.parent / "whiteboard_backend"
if str(WB_DIR) not in sys.path:
    sys.path.insert(0, str(WB_DIR))

# Path to font glyph files
FONT_DIR = Path(__file__).resolve().parent.parent / "wb_vectorize" / "Font"

try:
    from imggen import views as legacy_imggen_views
except Exception as e:  # pragma: no cover
    legacy_imggen_views = None
    _IMPORT_ERROR = str(e)
else:
    _IMPORT_ERROR = None


@csrf_exempt
def generate_image(request):
    if request.method != "POST":
        return HttpResponseNotAllowed(["POST"])
    if legacy_imggen_views is None:
        from django.http import JsonResponse
        return JsonResponse({"ok": False, "error": f"imggen unavailable: {_IMPORT_ERROR}"}, status=500)
    # Delegate to the whiteboard_backend generation view
    return legacy_imggen_views.generate_images_batch(request)


def get_font_glyph(request, char_hex):
    """
    Serve font glyph JSON files for the whiteboard.
    
    The char_hex parameter is the unicode code point in lowercase hex (e.g., '0041' for 'A').
    Font files are stored in wb_vectorize/Font/{char_hex}.json
    """
    # Sanitize input - only allow valid hex characters
    if not char_hex or not all(c in '0123456789abcdef' for c in char_hex.lower()):
        raise Http404("Invalid character code")
    
    # Normalize to lowercase
    char_hex = char_hex.lower()
    
    # Build path to font file
    font_file = FONT_DIR / f"{char_hex}.json"
    
    if not font_file.exists():
        raise Http404(f"Font glyph not found: {char_hex}")
    
    try:
        with open(font_file, 'r', encoding='utf-8') as f:
            glyph_data = json.load(f)
        return JsonResponse(glyph_data, safe=False)
    except (json.JSONDecodeError, IOError) as e:
        return JsonResponse({"error": str(e)}, status=500)












