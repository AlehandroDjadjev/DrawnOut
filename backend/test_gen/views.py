from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from django.conf import settings
import json

from google import genai

import re

def extract_json(text: str) -> str:
    """
    Extract the first valid JSON object from text.
    """
    match = re.search(r"\{[\s\S]*\}", text)
    if not match:
        raise ValueError("No JSON object found in AI response")
    return match.group(0)


def validate_test_structure(test: dict):
    if "part1" not in test or len(test["part1"]) != 10:
        raise ValueError("part1 must contain exactly 10 multiple-choice questions")

    if "part2" not in test or len(test["part2"]) != 5:
        raise ValueError("part2 must contain exactly 5 open-answer questions")

    for i, q in enumerate(test["part1"], start=1):
        if "question" not in q:
            raise ValueError(f"part1 question {i} missing 'question'")
        if "choices" not in q or len(q["choices"]) != 4:
            raise ValueError(f"part1 question {i} must have exactly 4 choices")
        if "correct_answer" not in q:
            raise ValueError(f"part1 question {i} missing 'correct_answer'")

    for i, q in enumerate(test["part2"], start=1):
        if "question" not in q:
            raise ValueError(f"part2 question {i} missing 'question'")
        if "expected_answer" not in q:
            raise ValueError(f"part2 question {i} missing 'expected_answer'")


@api_view(["POST"])
def generate_test_api(request):
    prompt = request.data.get("prompt")
    if not prompt:
        return Response({"error": "Prompt is required"}, status=status.HTTP_400_BAD_REQUEST)

    system_prompt = f"""
You are a test generator.

STRICT REQUIREMENTS:
- If you include ANY text outside the JSON object, the response is invalid.
- Generate EXACTLY 10 multiple-choice questions in part1
- Each multiple-choice question must have EXACTLY 4 choices
- Generate EXACTLY 5 open-answer questions in part2

Return ONLY valid JSON.
No markdown. No extra text.

JSON format:
{{
  "part1": [
    {{
      "question": "",
      "choices": ["", "", "", ""],
      "correct_answer": ""
    }}
  ],
  "part2": [
    {{
      "question": "",
      "expected_answer": ""
    }}
  ]
}}

Prompt:
{prompt}
""".strip()

    try:
        client = genai.Client(api_key=settings.GEMINI_API_KEY)

        # Pick a modern model. If you want fastest/cheapest, use a Flash model.
        # Example from Google docs uses gemini-2.0-flash in migration examples.
        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents=system_prompt,
        )
        text = response.text or ""
        json_text = extract_json(text)
        test_json = json.loads(json_text)
        print("RAW AI OUTPUT:\n", text)

        validate_test_structure(test_json)
        return Response(test_json, status=status.HTTP_200_OK)

    except json.JSONDecodeError:
        return Response(
            {"error": "AI returned invalid JSON"},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )
    except ValueError as e:
        return Response({"error": str(e)}, status=status.HTTP_400_BAD_REQUEST)
    except Exception as e:
        return Response(
            {"error": "Unexpected error", "details": str(e)},
            status=status.HTTP_500_INTERNAL_SERVER_ERROR
        )
