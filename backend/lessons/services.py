import io
import os
from dataclasses import dataclass
from typing import List, Optional

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.conf import settings

from google.cloud import texttospeech

try:
    import google.generativeai as genai  # optional
except Exception:
    genai = None

from openai import OpenAI


OPENAI_API_KEY = os.getenv('OPENAI_API_KEY', '')
GOOGLE_APPLICATION_CREDENTIALS = os.getenv('GOOGLE_APPLICATION_CREDENTIALS', '')
GOOGLE_AI_API_KEY = os.getenv('GOOGLE_AI_API_KEY', '')


@dataclass
class TutorResponse:
    text: str
    audio_path: Optional[str]


class TutorEngine:
    """Handles GPT planning/dialogue and TTS/STT IO."""

    def __init__(self):
        self.openai = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None
        # Google TTS client (relies on GOOGLE_APPLICATION_CREDENTIALS or ADC)
        try:
            self.tts_client = texttospeech.TextToSpeechClient()
        except Exception:
            self.tts_client = None

        # Gemini / google generative ai availability
        self.gemini_available = bool(GOOGLE_AI_API_KEY and genai)
        if self.gemini_available:
            try:
                genai.configure(api_key=GOOGLE_AI_API_KEY)
            except Exception:
                self.gemini_available = False

        # In-memory live chat sessions keyed by lesson session id (dev only)
        self._live_chats: dict[int, object] = {}

    # --- Lesson Planning ---
    def build_lesson_plan(self, topic: str) -> List[str]:
        hardcoded_topic = topic or "Introduction to the Pythagorean Theorem"
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
        """Return a short, child-friendly explanation for the given step."""
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
        # Placeholder: if using OpenAI Whisper or local Whisper.
        if self.openai:
            try:
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
    def synthesize_speech(
        self,
        text: str,
        voice: Optional[str] = None,
        use_ssml: bool = True,
        speaking_rate: Optional[float] = None,
        pitch: Optional[float] = None,
        volume_gain_db: Optional[float] = None,
    ) -> Optional[str]:
        """
        Synthesize speech and save to default_storage. Returns saved path or None.
        - If use_ssml=True, `text` is treated as SSML. Otherwise plain text.
        - speaking_rate: 0.25..4.0
        - pitch: semitones (-20..20)
        - volume_gain_db: -96..16
        """
        if not self.tts_client:
            return None

        # Pull defaults from settings if present
        default_voice = voice or getattr(settings, "TTS_DEFAULT_VOICE", "en-US-Neural2-F")
        candidate_voices = getattr(settings, "TTS_CANDIDATE_VOICES", [default_voice, "en-US-Wavenet-F", "en-US-Standard-F"])
        language_code = getattr(settings, "TTS_LANGUAGE_CODE", "en-US")
        ssml_gender_str = getattr(settings, "TTS_SSML_GENDER", "FEMALE")
        try:
            ssml_gender = getattr(texttospeech.SsmlVoiceGender, ssml_gender_str)
        except Exception:
            ssml_gender = texttospeech.SsmlVoiceGender.FEMALE

        speaking_rate = speaking_rate if speaking_rate is not None else getattr(settings, "TTS_DEFAULT_SPEAKING_RATE", 1.0)
        pitch = pitch if pitch is not None else getattr(settings, "TTS_DEFAULT_PITCH", 0.0)
        volume_gain_db = volume_gain_db if volume_gain_db is not None else getattr(settings, "TTS_DEFAULT_VOLUME_GAIN_DB", 0.0)

        # Build input (SSML or plain text)
        if use_ssml:
            # Wrap text in <speak> if user provided plain text
            if not text.strip().startswith("<speak"):
                ssml_text = f"<speak><prosody rate=\"{speaking_rate}\" pitch=\"{pitch}st\">{text}</prosody></speak>"
            else:
                ssml_text = text
            synthesis_input = texttospeech.SynthesisInput(ssml=ssml_text)
        else:
            synthesis_input = texttospeech.SynthesisInput(text=text)

        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3,
            speaking_rate=speaking_rate,
            pitch=pitch,
            volume_gain_db=volume_gain_db,
        )

        for candidate in candidate_voices:
            try:
                voice_params = texttospeech.VoiceSelectionParams(
                    language_code=language_code,
                    name=candidate,
                    ssml_gender=ssml_gender,
                )
                response = self.tts_client.synthesize_speech(
                    input=synthesis_input,
                    voice=voice_params,
                    audio_config=audio_config,
                )
                # Save result and return path
                safe_name = f"tts/utterance_{abs(hash(candidate + '|' + text))}.mp3"
                saved_path = default_storage.save(safe_name, ContentFile(response.audio_content))
                return saved_path
            except Exception:
                continue
        return None

    # --- Gemini Live (text-chat fallback) ---
    def start_live_chat(self, lesson_session_id: int) -> bool:
        if not self.gemini_available:
            return False
        try:
            model = genai.GenerativeModel("gemini-1.5-flash")
            chat = model.start_chat(history=[])
            self._live_chats[lesson_session_id] = chat
            return True
        except Exception:
            return False

    def live_message(self, lesson_session_id: int, user_text: str) -> Optional[str]:
        chat = self._live_chats.get(lesson_session_id)
        if not chat:
            started = self.start_live_chat(lesson_session_id)
            if not started:
                return None
            chat = self._live_chats.get(lesson_session_id)
        try:
            resp = chat.send_message(user_text)
            return (getattr(resp, "text", None) or str(resp)).strip()
        except Exception:
            return None

    def end_live_chat(self, lesson_session_id: int) -> None:
        if lesson_session_id in self._live_chats:
            try:
                del self._live_chats[lesson_session_id]
            except Exception:
                pass