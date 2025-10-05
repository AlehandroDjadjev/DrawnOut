import os
import openai

openai.api_key = os.getenv("OPENAI_API_KEY")

def analyze_lesson_plan(plan_text):
    """
    Given a lesson plan, use OpenAI to decide:
    - What image to show
    - What keywords to search
    - What text and color to draw on canvas (with optional positions)
    """

    prompt = f"""
You are a helpful teaching assistant building a digital whiteboard.
The teacher gave you this lesson plan:

"{plan_text}"

Your task is to:
1. Decide what image should go on the board
2. Pick search keywords for that image
3. Choose simple text/labels/symbols to draw on the whiteboard
4. Choose a color for each text item
5. Provide (x, y) positions (in pixels) for each text item

Return STRICT JSON in the format:

{{
  "image_description": "...",
  "keywords": ["...", "..."],
  "canvas_text": [
    {{"text": "...", "color": "...", "x": ..., "y": ...}},
    ...
  ]
}}

Only return the JSON. No explanation.
"""

    response = openai.ChatCompletion.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=300,
        temperature=0.7
    )

    import json
    try:
        json_text = response['choices'][0]['message']['content']
        return json.loads(json_text)
    except Exception as e:
        print("Error parsing OpenAI response:", e)
        return {
            "image_description": "default image",
            "keywords": ["education", "lesson"],
            "canvas_text": [
                {"text": "Hello", "color": "black", "x": 50, "y": 50}
            ]
        }
