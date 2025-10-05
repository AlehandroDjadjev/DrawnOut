import json
from django.shortcuts import render
from django.http import JsonResponse, HttpResponseBadRequest
from .openai_client import analyze_lesson_plan
from .web_search import search_image_by_keywords

def index(request):
    # Render the main page with the canvas and lesson plan input
    return render(request, "canvasapp/index.html")

def analyze_plan(request):
    if request.method != "POST":
        return HttpResponseBadRequest("POST request required.")

    try:
        data = json.loads(request.body)
        lesson_plan = data.get("lesson_plan", "")
        if not lesson_plan:
            return JsonResponse({"error": "Missing lesson_plan"}, status=400)

        # Call OpenAI to analyze the lesson plan
        analysis = analyze_lesson_plan(lesson_plan)

        # Call Bing API with keywords to get image URL
        image_result = search_image_by_keywords(analysis.get("keywords", []))
        image_url = image_result.get("image_url")

        # Prepare response with image URL and canvas text instructions
        response_data = {
            "image_url": image_url,
            "canvas_text": analysis.get("canvas_text", [])
        }

        return JsonResponse(response_data)

    except Exception as e:
        return JsonResponse({"error": str(e)}, status=500)
