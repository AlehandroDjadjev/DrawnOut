import importlib
import json
import re
import sys
import time
import traceback
from pathlib import Path
from typing import Any, Dict

from django.http import HttpResponseBadRequest, JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

APP_DIR = Path(__file__).resolve().parent


def _log(msg: str) -> None:
    ts = time.strftime("%H:%M:%S")
    print(f"[{ts}][views] {msg}", flush=True)


_pipeline_module_cache = None


def _load_pipeline_module():
    global _pipeline_module_cache
    if _pipeline_module_cache is not None:
        return _pipeline_module_cache

    _log("Loading pipeline module (first call)...")
    module_dir = str(APP_DIR)
    if module_dir not in sys.path:
        sys.path.insert(0, module_dir)

    try:
        # Legacy module name expected by ImagePipeline.py.
        if "ImageResearcher" not in sys.modules:
            _log("  Importing Imageresearcher as ImageResearcher alias...")
            sys.modules["ImageResearcher"] = importlib.import_module("Imageresearcher")

        _log("  Importing ImagePipeline...")
        pipeline = importlib.import_module("ImagePipeline")
    except Exception:
        # Clean up partial sys.modules state so next attempt starts fresh
        _log("  Import FAILED -- cleaning up partial sys.modules state")
        _log(traceback.format_exc())
        for name in ("ImageResearcher", "Imageresearcher", "ImagePipeline"):
            sys.modules.pop(name, None)
        raise

    # Ensure runtime paths resolve inside this extracted app.
    pipeline.IN_DIR_ROOT = APP_DIR / "ResearchImages" / "UniqueImages"
    pipeline.METADATA_CONTEXT_PATH = (
        pipeline.IN_DIR_ROOT / "image_metadata_context.json"
    )
    _log(f"  IN_DIR_ROOT = {pipeline.IN_DIR_ROOT}")
    _log("Pipeline module loaded successfully.")
    _pipeline_module_cache = pipeline
    return pipeline


def _coerce_int(body: Dict[str, Any], key: str, default: int, min_value: int) -> int:
    raw = body.get(key, default)
    try:
        value = int(raw)
    except (TypeError, ValueError):
        raise ValueError(f"'{key}' must be an integer")
    if value < min_value:
        raise ValueError(f"'{key}' must be >= {min_value}")
    return value


def _coerce_float(
    body: Dict[str, Any], key: str, default: float, min_value: float, max_value: float
) -> float:
    raw = body.get(key, default)
    try:
        value = float(raw)
    except (TypeError, ValueError):
        raise ValueError(f"'{key}' must be a number")
    if value < min_value or value > max_value:
        raise ValueError(f"'{key}' must be between {min_value} and {max_value}")
    return value


def _parse_prompt_map(body: Dict[str, Any]) -> Dict[str, str]:
    prompts = body.get("prompts")
    if isinstance(prompts, dict):
        cleaned: Dict[str, str] = {}
        for prompt, subject in prompts.items():
            prompt_text = str(prompt or "").strip()
            subject_text = str(subject or "").strip()
            if prompt_text and subject_text:
                cleaned[prompt_text] = subject_text
        if cleaned:
            return cleaned

    query = str(body.get("query") or "").strip()
    subject = str(body.get("subject") or "").strip()
    if query and subject:
        return {query: subject}

    raise ValueError(
        "Provide either 'prompts' as {prompt: subject} or both 'query' and 'subject'."
    )


@csrf_exempt
@require_http_methods(["POST"])
def run_image_pipeline(request):
    _log("=== run_image_pipeline: request received ===")

    try:
        body = json.loads((request.body or b"{}").decode("utf-8"))
    except json.JSONDecodeError:
        _log("ERROR: invalid JSON in request body")
        return HttpResponseBadRequest("Invalid JSON")

    if not isinstance(body, dict):
        _log("ERROR: body is not a JSON object")
        return HttpResponseBadRequest("JSON body must be an object")

    try:
        prompt_map = _parse_prompt_map(body)
        top_n_per_prompt = _coerce_int(body, "top_n_per_prompt", 2, 1)
        min_modalities = _coerce_int(body, "min_modalities", 3, 1)
        top_k_per_modality = _coerce_int(body, "top_k_per_modality", 50, 1)
        gpu_index = _coerce_int(body, "gpu_index", 0, 0)
        min_final_score = _coerce_float(body, "min_final_score", 0.78, 0.0, 1.0)
    except ValueError as exc:
        _log(f"ERROR: parameter validation failed: {exc}")
        return HttpResponseBadRequest(str(exc))

    model_id = str(body.get("model_id") or "Qwen/Qwen3-VL-2B-Instruct").strip()
    if not model_id:
        _log("ERROR: model_id is empty")
        return HttpResponseBadRequest("'model_id' cannot be empty")

    _log(f"  prompts={list(prompt_map.keys())}")
    _log(f"  top_n_per_prompt={top_n_per_prompt}, min_modalities={min_modalities}")
    _log(f"  top_k_per_modality={top_k_per_modality}, min_final_score={min_final_score}")
    _log(f"  model_id={model_id}, gpu_index={gpu_index}")

    try:
        _log("Loading pipeline module...")
        pipeline = _load_pipeline_module()
        _log("Calling pipeline.get_images_full()...")
        t0 = time.time()
        result = pipeline.get_images_full(
            prompt_map,
            top_n_per_prompt=top_n_per_prompt,
            min_final_score=min_final_score,
            min_modalities=min_modalities,
            top_k_per_modality=top_k_per_modality,
            model_id=model_id,
            gpu_index=gpu_index,
        )
        elapsed = time.time() - t0
        _log(f"get_images_full() returned in {elapsed:.1f}s")
        for prompt, entries in result.items():
            _log(f"  prompt='{prompt}': {len(entries)} result(s)")
    except Exception as exc:
        _log(f"EXCEPTION in pipeline: {type(exc).__name__}: {exc}")
        _log(traceback.format_exc())
        return JsonResponse(
            {
                "ok": False,
                "error": f"{type(exc).__name__}: {exc}",
            },
            status=500,
        )

    # Build a summary so callers can quickly see what was found without
    # needing to parse the full payload.
    summary: Dict[str, Any] = {}
    for prompt, entries in result.items():
        summary[prompt] = [
            {
                "id": e.get("id"),
                "has_image": e.get("image_b64") is not None,
                "has_embedding": e.get("embedding") is not None,
                "has_strokes": e.get("strokes") is not None,
                "stroke_count": len((e.get("strokes") or {}).get("strokes", [])),
            }
            for e in entries
        ]

    _log(f"=== run_image_pipeline: returning ok=True, {len(result)} prompt(s) ===")
    return JsonResponse({"ok": True, "result": result, "summary": summary})


# ── Font glyph API ──────────────────────────────────────────────────────────

FONT_DIR = APP_DIR / "Font"
_HEX4_RE = re.compile(r"^[0-9a-fA-F]{4}$")


@csrf_exempt
@require_http_methods(["GET"])
def get_font_metrics(request):
    """Return the font metrics JSON from whiteboard_backend/Font/font_metrics.json."""
    path = FONT_DIR / "font_metrics.json"
    if not path.exists():
        return JsonResponse(
            {"ok": False, "error": "font_metrics.json not found"}, status=404
        )
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return JsonResponse({"ok": True, "metrics": data})
    except Exception as exc:
        return JsonResponse({"ok": False, "error": str(exc)}, status=500)


@csrf_exempt
@require_http_methods(["GET"])
def get_font_glyph(request, hex_code: str):
    """Return the cubic Bézier stroke JSON for a single glyph.

    URL pattern: font/glyph/<hex4>/   e.g. font/glyph/0041/ for 'A'
    """
    if not _HEX4_RE.match(hex_code):
        return HttpResponseBadRequest(
            "hex_code must be exactly 4 hex characters (e.g. 0041)"
        )
    path = FONT_DIR / f"{hex_code.lower()}.json"
    if not path.exists():
        return JsonResponse(
            {"ok": False, "error": f"Glyph '{hex_code}' not found"}, status=404
        )
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return JsonResponse({"ok": True, "glyph": data})
    except Exception as exc:
        return JsonResponse({"ok": False, "error": str(exc)}, status=500)
