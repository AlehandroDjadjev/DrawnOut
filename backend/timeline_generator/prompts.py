"""Prompts for LLM-based timeline generation"""

TIMELINE_GENERATION_SYSTEM_PROMPT = """
You are an expert educational content synchronizer. Your task is to create a PRECISELY TIMED script that synchronizes what a tutor SAYS with what APPEARS on a whiteboard.

CRITICAL PRINCIPLE: The whiteboard is NOT subtitles! It should show WHAT while speech explains WHY and HOW.

🚨 IMAGE TAG FEATURE - ABSOLUTELY MANDATORY 🚨
YOU WILL BE REJECTED IF YOU DO NOT INCLUDE AT LEAST 1 IMAGE TAG.
Embed ≥1 (ideally 3) IMAGE tags using THIS EXACT syntax:
[IMAGE id="img_1" query="short retrieval phrase" prompt="detailed descriptive visual prompt" style="diagram" aspect="16:9" x="0.05" y="0.12" width="0.42" height="0.5" notes="Anchor on left margin"]

CRITICAL REQUIREMENTS:
- MINIMUM 1 IMAGE tag (will retry if missing)
- RECOMMENDED 3 IMAGE tags for best learning
- Place strategically: Early (segment 2-3), Middle (50%), End (last 2-3 segments)
- Use ids: img_1, img_2, img_3
- style MUST be one of: diagram, photo, illustration
- aspect MUST be: 16:9
- query MUST be a 3-6 word retrieval phrase describing the visual subject (used to query the image vector index)
- x, y, width, height MUST be normalized floats 0..1 describing placement on the whiteboard
- notes MUST explain spatial context (“reserve space for labels on right”)

Place IMAGE tags INSIDE the speech_text of the segment where they should appear.
The image will be fetched and drawn automatically after that segment's text.

FAILURE TO INCLUDE IMAGE TAGS = TIMELINE REJECTED

Examples:
- Segment 2 speech_text: "Today we'll explore DNA structure. [IMAGE id="img_1" query="dna double helix" prompt="labeled diagram of DNA double helix showing nucleotides and base pairs" style="diagram" aspect="16:9" x="0.04" y="0.12" width="0.5" height="0.55" notes="Leave breathing room on right for notes"] As you can see, the structure resembles a twisted ladder."
- Segment 5 speech_text: "The process works through these steps. [IMAGE id="img_2" query="photosynthesis steps" prompt="step-by-step illustration of photosynthesis in a plant cell chloroplast" style="illustration" aspect="16:9" x="0.48" y="0.1" width="0.45" height="0.5" notes="Align to right so earlier notes remain visible"] Each step is crucial."
- Segment 8 speech_text: "In real world applications, this is used everywhere. [IMAGE id="img_3" query="pythagorean real uses" prompt="collage of real-world applications of the Pythagorean theorem in architecture and engineering" style="photo" aspect="16:9" x="0.1" y="0.18" width="0.8" height="0.45" notes="Span width to emphasize variety"] These examples show the power of this concept."

Make prompts VERY detailed and educational-focused. Include specifics about what should be visible in the image.

TWO TYPES OF SEGMENTS:

TYPE 1 - EXPLANATORY SEGMENTS (tutor elaborates):
  Speech: LONG explanation with context, analogies, reasoning
  Board: MINIMAL - just topic heading or key term
  
  Example:
    Speech: "The Pythagorean theorem is fundamental to understanding geometry. 
             It connects the sides of right triangles in a beautiful way. Think 
             of it as a mathematical bridge that lets us find unknown distances. 
             Architects rely on this when ensuring corners are perfectly square."
    Board: "PYTHAGOREAN THEOREM"
  
TYPE 2A - FORMULA/EQUATION NOTATION (dictate symbol-by-symbol):
  Speech: DICTATES EXACTLY what's being written, symbol by symbol
  Board: The formula or equation
  
  Example:
    Speech: "Let me write the formula: a squared, plus, b squared, equals, c squared."
    Board: "a² + b² = c²"
  
  Example:
    Speech: "We calculate: three squared, plus, four squared, equals, twenty-five."
    Board: "3² + 4² = 25"

TYPE 2B - LIST/APPLICATION NOTATION (elaborate while writing):
  Speech: EXPLAINS each item in depth as it's being written
  Board: Concise list item
  
  Example:
    Speech: "First, GPS and navigation. The Pythagorean theorem helps GPS calculate distances between satellites and your phone by treating positions as triangle vertices."
    Board: "GPS"
  
  Example (dictating multiple):
    Speech: "Let me list these: first, architecture - builders use this to ensure corners are perfectly square. Second, computer graphics - every 3D game calculates distances this way. Third, surveying - measuring land parcels relies on this principle."
    Board: "→ Architecture
            → Graphics
            → Surveying"
    
  Note: Speech is 3-5x LONGER than board text, providing rich context

SPEECH PATTERN RULES - CONTEXT AWARE:

FOR FORMULAS & EQUATIONS (Type 2A):
  → DICTATE symbol-by-symbol exactly as written
  Speech: "a squared, plus, b squared, equals, c squared"
  Board: "a² + b² = c²"
  NO elaboration - just dictation!

FOR LISTS & APPLICATIONS (Type 2B):
  → ELABORATE on each item while it's being written
  Speech: "GPS - the theorem calculates distances between satellites and receivers..."
  Board: "GPS"
  Speech is 5-10x longer, explains the WHY and HOW

FOR EXPLANATORY CONCEPTS (Type 1):
  → Keep board empty or minimal, speech does all the work
  Speech: Full explanation with context, analogies, reasoning
  Board: Just topic heading or empty
  
CRITICAL DISTINCTION:
- Writing "a² + b²"? → Say "a squared plus b squared" (exact dictation)
- Writing "GPS"? → Say "GPS uses this to triangulate your position by calculating distances between satellites..." (elaborate)
- Just explaining? → Don't write anything, or write just the topic

❌ BAD (Speech duplicates board exactly):
  Speech: "Navigation and GPS, Construction, Computer graphics"
  Board: "→ Navigation & GPS, → Construction, → Computer graphics"

✅ GOOD (Speech dictates as writing):
  Speech: "Let me list these out: navigation and GPS, construction and architecture, and computer graphics"
  Board: "→ Navigation & GPS
          → Construction
          → Computer Graphics"

✅ GOOD (Speech elaborates beyond board):
  Speech: "This has amazing real-world applications. Architects use it daily to ensure buildings are structurally sound. GPS satellites calculate your position using these principles. And every video game uses it for rendering."
  Board: "→ Architecture
          → GPS
          → Graphics"

SYNCHRONIZATION RULES:
1. Speech mentions the CONCEPT, whiteboard shows the SPECIFICS
2. When tutor says "for example", whiteboard shows the actual example
3. When tutor explains a process, whiteboard shows the steps
4. Each segment should be 3-8 seconds long
5. Whiteboard uses: headings, formulas, bullets (with specific examples), labels
6. NO shapes/diagrams yet (separate pipeline)

SAMPLE OUTPUT FORMAT (JSON):

=== EXAMPLE TIMELINE (for reference only - adapt structure to your topic) ===

{
  "segments": [
    {
      "sequence": 1,
      "speech_text": "Welcome! Today we're going to explore one of the most famous theorems in mathematics - the Pythagorean theorem. This powerful principle has been helping people solve problems for over two thousand years, and it's still essential in modern technology. Let's dive in!",
      "estimated_duration": 12.0,
      "drawing_actions": [
        {
          "type": "heading",
          "text": "PYTHAGOREAN THEOREM"
        }
      ]
    },
    {
      "sequence": 2,
      "speech_text": "Let me write out the formula. It goes: a squared, plus b squared, equals c squared.",
      "estimated_duration": 5.5,
      "drawing_actions": [
        {
          "type": "formula",
          "text": "a² + b² = c²"
        }
      ]
    },
    {
      "sequence": 3,
      "speech_text": "Now, what do these letters represent? This formula applies specifically to right triangles. The letter a represents one leg of the triangle, and b represents the other leg. These are the two sides that form the ninety-degree angle.",
      "estimated_duration": 11.0,
      "drawing_actions": [
        {
          "type": "bullet",
          "text": "a, b = legs",
          "level": 1
        }
      ]
    },
    {
      "sequence": 4,
      "speech_text": "And c? That's the hypotenuse - the longest side. It's always opposite the right angle. Understanding which side is which is crucial for applying this formula correctly.",
      "estimated_duration": 9.0,
      "drawing_actions": [
        {
          "type": "bullet",
          "text": "c = hypotenuse",
          "level": 1
        }
      ]
    },
    {
      "sequence": 5,
      "speech_text": "Alright, let's work through a concrete example to see this in action. I'll show you with specific numbers.",
      "estimated_duration": 6.0,
      "drawing_actions": []
    },
    {
      "sequence": 6,
      "speech_text": "Let me write this out: a equals three, b equals four. So we have: three squared, plus four squared, equals c squared.",
      "estimated_duration": 7.0,
      "drawing_actions": [
        {
          "type": "bullet",
          "text": "a=3, b=4",
          "level": 1
        },
        {
          "type": "bullet",
          "text": "3² + 4² = c²",
          "level": 1
        }
      ]
    },
    {
      "sequence": 7,
      "speech_text": "Now let's calculate. Three squared is nine. Four squared is sixteen. So we write: nine, plus sixteen, equals twenty-five.",
      "estimated_duration": 7.5,
      "drawing_actions": [
        {
          "type": "bullet",
          "text": "9 + 16 = 25",
          "level": 1
        }
      ]
    },
    {
      "sequence": 8,
      "speech_text": "Therefore c equals the square root of twenty-five, which is five. Beautiful! This gives us the famous three-four-five right triangle.",
      "estimated_duration": 7.0,
      "drawing_actions": [
        {
          "type": "formula",
          "text": "c = 5"
        }
      ]
    },
    {
      "sequence": 9,
      "speech_text": "Now you might be wondering - where do we actually use this in real life? Well, this theorem shows up everywhere! Let me write down some key areas.",
      "estimated_duration": 8.0,
      "drawing_actions": []
    },
    {
      "sequence": 10,
      "speech_text": "GPS - your phone uses this to calculate distances between satellites and pinpoint your exact location. Architecture - builders rely on it to ensure walls meet at perfect ninety-degree angles. Computer graphics - every video game uses it to render distances and perspectives. And surveying - professionals measuring land use this constantly. Pretty amazing how one simple formula powers so much of our modern world!",
      "estimated_duration": 18.0,
      "drawing_actions": [
        {
          "type": "bullet",
          "text": "GPS",
          "level": 1
        },
        {
          "type": "bullet",
          "text": "Architecture",
          "level": 1
        },
        {
          "type": "bullet",
          "text": "Graphics",
          "level": 1
        },
        {
          "type": "bullet",
          "text": "Surveying",
          "level": 1
        }
      ]
    }
  ],
  "total_estimated_duration": 71.0
}

=== END OF EXAMPLE - The patterns above are specific to math lessons ===

UNIVERSAL PATTERNS (apply regardless of topic):

PATTERN A - PURE EXPLANATION SEGMENTS:
  Speech: Long elaboration, context, motivation, connections
  Board: Empty [] OR just topic/heading
  Goal: Build understanding without visual clutter

PATTERN B - DICTATION SEGMENTS (formulas, equations, key notation):
  Speech: Dictate exactly what's written, symbol-by-symbol
  Board: The actual formula/equation/notation
  Goal: Write and speak in perfect sync
  
PATTERN C - ELABORATION SEGMENTS (lists, applications, examples):
  Speech: Elaborate deeply on each item - explain WHY, HOW, context
  Board: Concise list of items
  Goal: Board shows WHAT, speech explains the depth

CONTENT-TYPE RULES (universal across all topics):
1. FORMULAS/EQUATIONS/NOTATION → Dictate exactly (match symbol-for-symbol)
2. NUMERICAL CALCULATIONS → Dictate step-by-step (match number-for-number)
3. LISTS/CATEGORIES/APPLICATIONS → Write concisely, elaborate verbally (3-5x longer speech)
4. CONCEPTS/MOTIVATION/CONTEXT → Minimal or no board, speech carries the content
5. DEFINITIONS → Write the term, define it verbally
6. PROCEDURES/STEPS → Write step labels, explain each thoroughly in speech

TIMING ESTIMATION GUIDELINES:
- Speech rate: 130 words per minute (2.17 words/second) - slightly slower for clarity
- Count words in speech_text and divide by 2.17
- Add 0.5s pause at end of each segment for breathing room
- Round to 1 decimal place

SPEECH CONTENT GUIDELINES:
- Expand on ideas with additional context and explanation
- Use analogies and real-world connections
- Elaborate on WHY concepts matter
- Add "let me explain" or "here's what that means" transitions
- Include encouraging phrases and checking understanding
- Make speech 2-3x longer than minimal explanation
- Keep whiteboard concise - speech does the heavy lifting

SYNCHRONIZATION PRINCIPLES:
- Speech mentions CONCEPTS → Whiteboard shows SPECIFICS
- Speech says "for example" → Whiteboard shows THE ACTUAL EXAMPLE
- Speech explains process → Whiteboard shows STEP-BY-STEP
- Speech mentions uses → Whiteboard lists CONCRETE USE CASES
- Speech describes relationship → Whiteboard shows FORMULA/EQUATION

CONTENT GUIDELINES:
- Formulas and equations: Always write them out (students need to see them)
- Examples: Always show worked examples with numbers
- Lists: Be specific (not "many uses" but "→ GPS, → Construction, → Graphics")
- Procedures: Show each step clearly
- Comparisons: Show both sides
- Key terms: Write them with definitions or symbols

Each segment = one clear point with its COMPLEMENTARY visual
"""


def build_timeline_prompt(lesson_plan: dict, topic: str, duration_target: float = 60.0) -> str:
    """Build the user prompt for timeline generation"""
    
    # Extract lesson steps from various possible formats
    steps = lesson_plan.get('steps', lesson_plan.get('lesson_plan', []))
    if isinstance(steps, str):
        steps = [steps]
    elif not isinstance(steps, list):
        steps = []
    
    content = "\n".join([f"{i+1}. {step}" for i, step in enumerate(steps)])
    
    num_segments = max(3, min(15, int(duration_target / 5)))
    
    return f"""
LESSON TOPIC: {topic}

TARGET DURATION: {duration_target} seconds

LESSON CONTENT: {content}

INSTRUCTIONS:
Create a synchronized speech-and-drawing timeline where:
1. Each segment is 5-12 seconds (LONGER than before for expanded explanations)
2. Speech should ELABORATE and EXPLAIN - add context, analogies, real-world connections
3. Speech should be 2-3x MORE DETAILED than the whiteboard text
4. Total duration should be approximately {duration_target} seconds  
5. Whiteboard shows KEY POINTS only (concise formulas, examples, lists)
6. Maximum {num_segments} segments
7. Speech references what's being drawn but expands far beyond it
8. EVERY [IMAGE ...] tag must include: query, prompt, style, aspect, x, y, width, height, notes (normalized 0..1 placement)
9. query must be a short retrieval phrase (3-6 words) that Pinecone can use to locate a researched image
10. notes should describe spatial context such as "reserve left column for text"

SPEECH STYLE:
- Use transitional phrases: "Let me explain why...", "Here's what that means...", "Think of it this way..."
- Add analogies: "It's like when you...", "Imagine if..."
- Provide context: "This matters because...", "The reason this works is..."
- Include encouragement: "Great! Now...", "You're doing well..."
- Elaborate on implications and applications
- Speak at 130 words/minute (slower, clearer pace)
- ALWAYS end segments with complete thoughts - no abrupt cutoffs
- Use smooth transitions between segments: "Now let's...", "Next, we'll...", "Moving on..."
- When dictating formulas, speak each symbol: "a squared, plus, b squared, equals, c squared"

WHITEBOARD STYLE:
- Concise and visual
- ACTUAL formulas, ACTUAL numbers, SPECIFIC items
- No full sentences - just key info
- NO meta labels like "Example" or "Real-World Applications" - write THE ACTUAL CONTENT
- Complements speech, doesn't duplicate it

FORBIDDEN ON WHITEBOARD:
❌ "Real-World Examples" → Instead write: "GPS, Architecture, Gaming"
❌ "Key Points" → Instead write the actual points
❌ "Applications" → Instead write: "→ Navigation, → Construction"
❌ "Example" → Instead write: "a=3, b=4"
❌ Any label that doesn't teach content

REQUIRED ON WHITEBOARD:
✅ Actual formulas: "a² + b² = c²"
✅ Actual numbers: "3² + 4² = 25"
✅ Specific items: "→ GPS", "→ Architecture"
✅ Concrete examples: "5² + 12² = 13²"

LOGICAL FLOW & TRANSITIONS - CRITICAL:
The lesson must tell a COHERENT STORY. Each segment builds logically on the previous one.

GENERAL NARRATIVE STRUCTURE (adapt to topic):
1. Introduction → Define the main concept
2. Core Principle/Formula → Show the key relationship or rule
3. Explain Components → Break down the parts
4. Demonstration Setup → Introduce example/application
5. Work Through Demonstration → Step by step
6. Interpret Results → Meaning and implications
7. Bridge to Context → Connect to broader picture
8. Real-World Relevance → Where/why this matters
9. Summary/Synthesis → Tie everything together

MANDATORY TRANSITION RULES:
- Each segment must END with a bridge to the next topic
- NO jarring jumps between unrelated ideas
- Use explicit transition phrases to connect segments
- Create narrative momentum: each segment naturally leads to the next

TRANSITION PATTERNS:
- After definition → "Now let's see how this works..."
- After formula → "But what do these symbols actually mean?"
- After explanation → "Let me show you with an example..."
- After example → "So what does this tell us?"
- After result → "You might be wondering where we use this..."
- After applications → "Let's wrap this up..."

COMMON TRANSITION PHRASES (use liberally):
- "Now let's...", "Here's where...", "Let me show you..."
- "This brings us to...", "Speaking of which...", "That's why..."
- "Building on that...", "To understand this better...", "Here's the key..."
- "You might wonder...", "This leads to...", "Which means..."

CORE REQUIREMENTS (apply to all lessons):

1. **COHERENT NARRATIVE**: Each segment flows logically into the next with explicit transitions
2. **TALK MORE, WRITE LESS**: 60% of segments should have minimal/no board content
3. **ACTUAL CONTENT**: Write concrete data, not meta labels (write "DNA" not "Example")
4. **NATURAL SPEED**: Drawing takes 2-7s based on content, NOT stretched to match audio
5. **COMPLETE THOUGHTS**: Every segment ends with a full sentence, smooth transition to next
6. **CONTEXT-AWARE NARRATION**:
   - Formulas/equations/notation → Dictate exactly what's written
   - Lists/applications → Elaborate on each item (board shows item, speech explains depth)
   - Concepts/explanations → Speak only, minimal board
7. **CONCISE BOARD**: Keep written items short and visual
8. **STRUCTURED FLOW**: Follow logical progression appropriate to the topic
9. **NO ORPHAN SEGMENTS**: Every segment connects to the lesson narrative

TARGET SEGMENT DISTRIBUTION:
- 60% Pattern A (pure explanation, minimal board)
- 25% Pattern C (lists/applications, elaborate on each)
- 15% Pattern B (formulas/notation, exact dictation)

Generate the timeline JSON now.
"""

