import os
import openai
import json

openai.api_key = os.getenv("OPENAI_API_KEY")

def analyze_lesson_plan(plan_text):
    """
    Given a lesson plan, use OpenAI to decide:
    - What image to show (with a creative, relevant description)
    - What keywords to search for that image
    - What to draw on the whiteboard: text, shapes, symbols, and their properties
    """

    prompt = f"""
You are a creative and insightful teaching assistant for a digital whiteboard app.
The teacher gave you this lesson plan:

\"\"\"{plan_text}\"\"\"

Your job:
1. Imagine the most relevant and visually engaging image that would help students understand this lesson. Describe it in detail.
2. Pick 3-5 specific search keywords for that image.
3. Decide what should be drawn on the whiteboard to best support the lesson. This can include:
   - Text labels (with color, font, position)
   - Shapes (circle, rectangle, triangle, polygon, star, arrow, etc. with position, size, color)
   - Symbols (math or logic symbols, e.g. plus, minus, check, cross, etc.)
   - Images (with position, width, height)
4. For each drawing command, specify all required properties (type, position, size, color, text, etc.) so the frontend can render it directly.

Return STRICT JSON in this format (no explanation):

{{
  "image_description": "...",
  "keywords": ["...", "..."],
  "canvas_commands": [
    {{
      "type": "text" | "circle" | "rect" | "triangle" | "polygon" | "star" | "arrow" | "symbol" | "image",
      // For text: "content", "color", "font", "position": {{"x": ..., "y": ...}}
      // For shapes: "position"/"center"/"points", "radius"/"width"/"height", "strokeColor", "fillColor", etc.
      // For symbol: "name", "position": {{"x": ..., "y": ...}}, "size", "color"
      // For image: "url" (leave blank), "position": {{"x": ..., "y": ...}}, "width", "height"
      // Example:
      // {{"type": "text", "content": "Photosynthesis", "color": "green", "font": "20px Arial", "position": {{"x": 200, "y": 50}}}}
      // {{"type": "circle", "center": {{"x": 300, "y": 200}}, "radius": 40, "strokeColor": "blue", "fillColor": "lightblue"}}
      // {{"type": "symbol", "name": "plus", "position": {{"x": 100, "y": 100}}, "size": 30, "color": "red"}}
      // {{"type": "image", "url": "", "position": {{"x": 400, "y": 100}}, "width": 120, "height": 80}}
    }},
    ...
  ]
}}
Only return valid JSON. Do not include any explanation or extra text.
"""

    response = openai.ChatCompletion.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=600,
        temperature=0.8
    )

    try:
        json_text = response['choices'][0]['message']['content']
        return json.loads(json_text)
    except Exception as e:
        print("Error parsing OpenAI response:", e)
        # Fallback example
        return {
            "image_description": "A diagram showing the process of photosynthesis with sunlight, leaves, and arrows.",
            "keywords": ["photosynthesis", "plant", "sunlight", "diagram"],
            "canvas_commands": [
                {"type": "text", "content": "Photosynthesis", "color": "green", "font": "20px Arial", "position": {"x": 200, "y": 50}},
                {"type": "circle", "center": {"x": 300, "y": 200}, "radius": 40, "strokeColor": "blue", "fillColor": "lightblue"},
                {"type": "symbol", "name": "plus", "position": {"x": 100, "y": 100}, "size": 30, "color": "red"},
                {"type": "image", "url": "", "position": {"x": 400, "y": 100}, "width": 120, "height": 80}
            ]
        }