import numpy as np
import cv2
from django.http import JsonResponse, HttpResponseBadRequest
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

try:
    from . import ImageVectorizer as iv
    from . import ImageSkeletonizer as isk
except Exception as e:  # pragma: no cover
    iv = None
    isk = None
    _IMPORT_ERROR = str(e)
else:
    _IMPORT_ERROR = None


@csrf_exempt
@require_http_methods(["POST"])
def vectorize_image(request):
    """Full in-memory vectorization pipeline: preprocess -> skeletonize -> vectorize.

    Accepts an image upload, returns stroke JSON directly (no temp files).
    """
    if iv is None or isk is None:
        return JsonResponse({"ok": False, "error": f"Vectorizer unavailable: {_IMPORT_ERROR}"}, status=500)

    upload = request.FILES.get("image")
    if not upload:
        return HttpResponseBadRequest("Upload an image as 'image'")

    file_bytes = upload.read()
    arr = np.frombuffer(file_bytes, dtype=np.uint8)
    img_bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img_bgr is None:
        return JsonResponse({"ok": False, "error": "Could not decode image"}, status=400)

    try:
        from wb_preprocess import ImagePreprocessor as pre
    except ImportError:
        return JsonResponse({"ok": False, "error": "ImagePreprocessor unavailable"}, status=500)

    text_item = {"idx": 0, "masked_bgr": img_bgr}
    preproc = pre.process_images_in_memory([text_item])
    skels = isk.skeletonize_in_memory(preproc)
    vectors = iv.vectorize_in_memory(skels)

    result = vectors.get(0, {})
    return JsonResponse({"ok": True, "result": result})
