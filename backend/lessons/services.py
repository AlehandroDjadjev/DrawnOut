import io
import os
from dataclasses import dataclass
from typing import List, Tuple

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage

from google.cloud import texttospeech
from openai import OpenAI


OPENAI_API_KEY = os.getenv('OPENAI_API_KEY', '')
GOOGLE_APPLICATION_CREDENTIALS = os.getenv('GOOGLE_APPLICATION_CREDENTIALS', '')


@dataclass
class TutorResponse:
    text: str
    audio_path: str


class TutorEngine:
    """Handles GPT planning/dialogue and TTS/STT IO."""

    def __init__(self):
        self.openai = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None
        # Google TTS client credentials are read from env via default credentials
        try:
            self.tts_client = texttospeech.TextToSpeechClient()  # relies on GOOGLE_APPLICATION_CREDENTIALS
        except Exception:
            self.tts_client = None

    # --- Lesson Planning ---
    def build_lesson_plan(self, topic: str) -> List[str]:
        # Hardcoded topic for now per request; topic arg kept for future
        hardcoded_topic = "Introduction to the Pythagorean Theorem"
        if self.openai:
            prompt = (
                f"Create a short 5-step lesson plan to teach: {hardcoded_topic}. "
                "Each step should be one clear sentence, suitable for spoken delivery."
            )
            try:
                chat = self.openai.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[{"role": "user", "content": prompt}],
                    temperature=0.3,
                )
                text = chat.choices[0].message.content
                steps = [s.strip("- ") for s in text.split("\n") if s.strip()]
                return steps[:5] if steps else [
                    "We will learn what the Pythagorean Theorem states.",
                    "We will visualize a right triangle and label its sides.",
                    "We will derive the relationship a^2 + b^2 = c^2.",
                    "We will solve a numerical example.",
                    "We will summarize and discuss common pitfalls.",
                ]
            except Exception:
                pass
        # Fallback static plan
        return [
            "We will learn what the Pythagorean Theorem states.",
            "We will visualize a right triangle and label its sides.",
            "We will derive the relationship a squared plus b squared equals c squared.",
            "We will solve a numerical example.",
            "We will summarize and discuss common pitfalls.",
        ]

    # --- Dialogue ---
    def continue_step(self, step_text: str) -> str:
        """Return a short, child-friendly explanation for the given step.

        Prefers OpenAI for natural language; falls back to a simple template if unavailable.
        """
        if self.openai:
            prompt = (
                "You are a friendly elementary school tutor.\n"
                f"The current lesson step is: '{step_text}'.\n"
                "Explain this step in 2-3 short, simple sentences so a child can understand.\n"
                "Use everyday words and, if helpful, one tiny example from real life.\n"
                "Avoid complex symbols. Output plain text only."
            )
            try:
                chat = self.openai.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[{"role": "user", "content": prompt}],
                    temperature=0.5,
                )
                text = chat.choices[0].message.content.strip()
                if text:
                    return text
            except Exception:
                pass
        return (
            f"{step_text}. In simple words, this means we are learning about this idea in a gentle way. "
            "Think of something you already know, and we connect it to this step with a tiny example."
        )

    def answer_question(self, step_text: str, question_text: str) -> str:
        if self.openai:
            prompt = (
                "You are a patient elementary school tutor.\n"
                f"The current lesson step is: '{step_text}'.\n"
                f"The student asked: '{question_text}'.\n"
                "Answer in 2-4 short sentences using simple words and a friendly tone.\n"
                "If helpful, give one tiny example. Avoid symbols. End by saying you'll continue the lesson."
            )
            try:
                chat = self.openai.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[{"role": "user", "content": prompt}],
                    temperature=0.3,
                )
                return chat.choices[0].message.content
            except Exception:
                pass
        return "Great question. In short, this idea is easier than it sounds. Let’s keep it simple and move on together!"

    # --- STT ---
    def transcribe_audio(self, audio_bytes: bytes, file_name: str = "question.wav") -> str:
        # Placeholder: if using OpenAI Whisper via API, or local faster-whisper.
        if self.openai:
            try:
                # API expects file-like
                file_obj = io.BytesIO(audio_bytes)
                file_obj.name = file_name
                transcript = self.openai.audio.transcriptions.create(
                    model="whisper-1",
                    file=file_obj,
                )
                return transcript.text
            except Exception:
                pass
        return ""

    # --- TTS ---
    def synthesize_speech(self, text: str, voice: str = "en-US-Neural2-F") -> str | None:
        if not self.tts_client:
            return None
        synthesis_input = texttospeech.SynthesisInput(text=text)
        audio_config = texttospeech.AudioConfig(audio_encoding=texttospeech.AudioEncoding.MP3)
        # Try a list of female voices to avoid any default male fallback
        candidate_voices = [voice, "en-US-Wavenet-F", "en-US-Standard-F"]
        for candidate in candidate_voices:
            try:
                voice_params = texttospeech.VoiceSelectionParams(
                    language_code="en-US",
                    name=candidate,
                    ssml_gender=texttospeech.SsmlVoiceGender.FEMALE,
                )
                response = self.tts_client.synthesize_speech(
                    input=synthesis_input, voice=voice_params, audio_config=audio_config
                )
                audio_path = default_storage.save(
                    f"tts/utterance_{abs(hash(candidate + '|' + text))}.mp3",
                    ContentFile(response.audio_content)
                )
                return audio_path
            except Exception:
                continue
        return None


