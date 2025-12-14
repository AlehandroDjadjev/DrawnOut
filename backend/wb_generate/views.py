import sys
from pathlib import Path

from django.http import HttpResponseNotAllowed
from django.views.decorators.csrf import csrf_exempt

# Reuse the whiteboard_backend imggen implementation via a shimmed sys.path
WB_DIR = Path(__file__).resolve().parent.parent / "whiteboard_backend"
if str(WB_DIR) not in sys.path:
    sys.path.insert(0, str(WB_DIR))

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

