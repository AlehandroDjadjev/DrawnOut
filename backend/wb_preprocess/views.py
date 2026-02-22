import numpy as np
import cv2
from django.http import JsonResponse, HttpResponseBadRequest
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

try:
    from . import ImagePreprocessor as pre
except Exception as e:  # pragma: no cover
    pre = None
    _IMPORT_ERROR = str(e)
else:
    _IMPORT_ERROR = None


@csrf_exempt
@require_http_methods(["POST"])
def run_preprocess(request):
    """In-memory preprocessing: accepts an image upload, returns preprocessed pass info."""
    if pre is None:
        return JsonResponse({"ok": False, "error": f"ImagePreprocessor unavailable: {_IMPORT_ERROR}"}, status=500)

    upload = request.FILES.get("image")
    if not upload:
        return HttpResponseBadRequest("Upload an image file as 'image'")

    file_bytes = upload.read()
    arr = np.frombuffer(file_bytes, dtype=np.uint8)
    img_bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img_bgr is None:
        return JsonResponse({"ok": False, "error": "Could not decode image"}, status=400)

    text_item = {"idx": 0, "masked_bgr": img_bgr}
    result = pre.process_images_in_memory([text_item])

    pass_names = {}
    for idx, data in result.items():
        pass_names[idx] = list(data.get("passes", {}).keys())

    return JsonResponse({"ok": True, "processed_count": len(result), "passes": pass_names})
