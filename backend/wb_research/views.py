"""
Endpoints exposing the whiteboard image researcher logic.
"""
import json
import sys
from pathlib import Path

from django.http import JsonResponse, HttpResponseBadRequest, HttpResponseNotAllowed
from django.views.decorators.csrf import csrf_exempt

# Import local wrapper which re-exports the whiteboard_backend implementation
try:
    from . import Imageresearcher as ir
except Exception as e:  # pragma: no cover - defensive
    ir = None
    _IMPORT_ERROR = str(e)
else:
    _IMPORT_ERROR = None


def _module_check():
    if ir:
        return None
    return JsonResponse({"ok": False, "error": f"Imageresearcher unavailable: {_IMPORT_ERROR}"}, status=500)


@csrf_exempt
def search_images(request):
    if request.method != "POST":
        return HttpResponseNotAllowed(["POST"])
    err = _module_check()
    if err:
        return err

    try:
        body = json.loads((request.body or b"{}").decode("utf-8"))
    except json.JSONDecodeError:
        return HttpResponseBadRequest("Invalid JSON")

    query = (body.get("query") or "").strip()
    subject = (body.get("subject") or "").strip()
    limit = body.get("limit", 10)
    requested_sources = body.get("sources", [])

    if not query:
        return HttpResponseBadRequest("'query' is required")
    if not subject:
        return HttpResponseBadRequest("'subject' is required")

    settings_dict = {
        "query_field": query,
        "limit_field": limit,
        "pagination_field": 1,
        "format_field": "json",
    }

    sources = ir.read_sources()
    results = []
    total_images = 0

    for src in sources:
        if requested_sources and src.name not in requested_sources:
            continue
        try:
            if src.type == "API":
                status, data, _ = ir.send_request(src, settings_dict)
                if status == 200 and data is not None:
                    parse_fn = ir.PARSERS.get(src.name)
                    if parse_fn:
                        parse_fn(src, data)
            else:
                ir.handle_result_no_api(src, query, subject, hard_image_cap=limit)

            images = getattr(src, "img_paths", [])
            results.append(
                {
                    "source": src.name,
                    "images": images,
                    "count": len(images),
                }
            )
            total_images += len(images)
        except Exception as e:  # pragma: no cover - runtime fallback
            results.append(
                {
                    "source": src.name,
                    "images": [],
                    "count": 0,
                    "error": str(e),
                }
            )

    return JsonResponse(
        {
            "ok": True,
            "results": results,
            "total_images": total_images,
            "query": query,
            "subject": subject,
        }
    )


def list_sources(request):
    err = _module_check()
    if err:
        return err
    try:
        sources = ir.read_sources()
        data = [
            {"name": src.name, "type": src.type, "url": src.url}
            for src in sources
        ]
        return JsonResponse({"ok": True, "sources": data})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)


def get_subjects(request):
    err = _module_check()
    if err:
        return err
    return JsonResponse({"ok": True, "subjects": ir.SUBJECTS})


@csrf_exempt
def search_duckduckgo(request):
    if request.method != "POST":
        return HttpResponseNotAllowed(["POST"])
    err = _module_check()
    if err:
        return err

    try:
        body = json.loads((request.body or b"{}").decode("utf-8"))
    except json.JSONDecodeError:
        return HttpResponseBadRequest("Invalid JSON")

    query = (body.get("query") or "").strip()
    max_results = body.get("max_results", 100)
    if not query:
        return HttpResponseBadRequest("'query' is required")

    try:
        from duckduckgo_search import DDGS

        with DDGS() as ddgs:
            results = list(ddgs.images(query, max_results=max_results, safesearch="moderate"))
        return JsonResponse({"ok": True, "results": results, "count": len(results)})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

