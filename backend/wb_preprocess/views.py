import os
import time
import sys
from pathlib import Path

from django.http import JsonResponse, HttpResponseNotAllowed, HttpResponseBadRequest
from django.views.decorators.csrf import csrf_exempt

try:
    from . import ImagePreproccessor as pre
except Exception as e:  # pragma: no cover - defensive import handling
    pre = None
    _IMPORT_ERROR = str(e)
else:
    _IMPORT_ERROR = None


@csrf_exempt
def run_preprocess(request):
    if request.method != "POST":
        return HttpResponseNotAllowed(["POST"])

    if pre is None:
        return JsonResponse({"ok": False, "error": f"ImagePreproccessor unavailable: {_IMPORT_ERROR}"}, status=500)

    upload = request.FILES.get("image")
    if not upload:
        return HttpResponseBadRequest("Upload an image file as 'image'")

    # Persist upload into the expected input directory
    in_dir = Path(pre.IN_DIR)
    in_dir.mkdir(parents=True, exist_ok=True)
    ts = int(time.time() * 1000)
    upload_path = in_dir / f"upload_{ts}_{upload.name}"
    with open(upload_path, "wb") as f:
        for chunk in upload.chunks():
            f.write(chunk)

    # Track files before processing to identify new outputs
    out_dir = Path(pre.OUT_DIR)
    out_dir.mkdir(parents=True, exist_ok=True)
    before = set(p.name for p in out_dir.glob("*"))

    pre.process_one(upload_path)

    after = set(p.name for p in out_dir.glob("*"))
    new_files = sorted(list(after - before))

    processed = None
    edges = None
    meta = None
    for name in new_files:
        if name.startswith("processed_") and name.endswith(".png") and not processed:
            processed = str(out_dir / name)
        elif name.startswith("edges_") and name.endswith(".png") and not edges:
            edges = str(out_dir / name)
        elif name.startswith("processed_") and name.endswith("_labels.json") and not meta:
            meta = str(out_dir / name)

    return JsonResponse(
        {
            "ok": True,
            "input": str(upload_path),
            "processed_image": processed,
            "edges_image": edges,
            "labels_json": meta,
            "generated_files": new_files,
        }
    )












