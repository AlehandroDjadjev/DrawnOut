import json
from django.shortcuts import render
from django.http import JsonResponse, HttpResponseBadRequest
from .openai_Client import analyze_lesson_plan
from .web_Search import search_image_by_keywords

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

        # Call Bing API with keywords to get image URL and info
        image_result = search_image_by_keywords(analysis.get("keywords", []))
        image_url = image_result.get("image_url")
        image_attribution = image_result.get("attribution", "")
        image_name = image_result.get("name", "")

        # Insert the found image URL into the first image command, if present
        canvas_commands = analysis.get("canvas_commands", [])
        for cmd in canvas_commands:
            if cmd.get("type") == "image" and cmd.get("url") == "":
                cmd["url"] = image_url
                cmd["attribution"] = image_attribution
                cmd["name"] = image_name

        response_data = {
            "image_description": analysis.get("image_description", ""),
            "keywords": analysis.get("keywords", []),
            "canvas_commands": canvas_commands
        }

        return JsonResponse(response_data)

    except Exception as e:
        return JsonResponse({"error": str(e)}, status=500)