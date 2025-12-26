import sys
import time
from pathlib import Path

from django.http import JsonResponse, HttpResponseNotAllowed, HttpResponseBadRequest
from django.views.decorators.csrf import csrf_exempt

try:
    from . import ImageVectorizer as iv
except Exception as e:  # pragma: no cover
    iv = None
    _IMPORT_ERROR = str(e)
else:
    _IMPORT_ERROR = None


@csrf_exempt
def vectorize_image(request):
    if request.method != "POST":
        return HttpResponseNotAllowed(["POST"])
    if iv is None:
        return JsonResponse({"ok": False, "error": f"ImageVectorizer unavailable: {_IMPORT_ERROR}"}, status=500)

    upload = request.FILES.get("image")
    if not upload:
        return HttpResponseBadRequest("Upload a skeleton/edges image as 'image'")

    in_dir = Path(iv.IN_DIR)
    out_dir = Path(iv.OUT_DIR)
    in_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    ts = int(time.time() * 1000)
    upload_path = in_dir / f"skel_{ts}_{upload.name}"
    with open(upload_path, "wb") as f:
        for chunk in upload.chunks():
            f.write(chunk)

    src, meta = iv._process_single(upload_path, out_dir)
    json_path = out_dir / f"{Path(src).stem}.json"

    return JsonResponse(
        {
            "ok": True,
            "input": str(upload_path),
            "vector_json": str(json_path),
            "strokes": len(meta.get("strokes", [])),
            "stats": meta.get("stats", {}),
        }
    )












