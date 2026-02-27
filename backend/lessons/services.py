import io
import os
import re
from dataclasses import dataclass
from typing import List, Optional

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.conf import settings

try:
    from google.cloud import texttospeech
except Exception:
    texttospeech = None

try:
    import google.generativeai as genai  # optional
except Exception:
    genai = None

from openai import OpenAI


OPENAI_API_KEY = os.getenv('OPENAI_API_KEY', '')
GOOGLE_APPLICATION_CREDENTIALS = os.getenv('GOOGLE_APPLICATION_CREDENTIALS', '')
GOOGLE_AI_API_KEY = os.getenv('GOOGLE_AI_API_KEY', '')
ELEVENLABS_API_KEY = os.getenv('Netanyahu', '')
ELEVENLABS_VOICE_ID = os.getenv('voice_id', '')


@dataclass
class TutorResponse:
    text: str
    audio_path: Optional[str]


class TutorEngine:
    """Handles GPT planning/dialogue and TTS/STT IO."""

    def __init__(self):
        self.openai = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None
        # ElevenLabs TTS client (API key from Netanyahu env, voice from voice_id env)
        self._elevenlabs_client = None
        if ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID:
            try:
                from elevenlabs.client import ElevenLabs
                self._elevenlabs_client = ElevenLabs(api_key=ELEVENLABS_API_KEY)
            except Exception:
                pass

        # Google Cloud TTS client (fallback when use_elevenlabs_tts=False)
        self._google_tts_client = None
        if texttospeech:
            try:
                self._google_tts_client = texttospeech.TextToSpeechClient()
            except Exception:
                pass

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

    # --- TTS (ElevenLabs or Google Cloud) ---
    def synthesize_speech(
        self,
        text: str,
        voice: Optional[str] = None,
        use_ssml: bool = True,
        speaking_rate: Optional[float] = None,
        pitch: Optional[float] = None,
        volume_gain_db: Optional[float] = None,
        use_elevenlabs_tts: bool = False,
    ) -> Optional[str]:
        """
        Synthesize speech and save to default_storage. Returns saved path or None.
        use_elevenlabs_tts: If True, use ElevenLabs (Netanyahu + voice_id env vars); else Google Cloud TTS.
        """
        plain_text = text
        if use_ssml and text.strip().startswith("<speak"):
            plain_text = re.sub(r"<[^>]+>", "", text).strip()
        elif use_ssml:
            plain_text = re.sub(r"<[^>]+>", "", text).strip() or text
        if not plain_text.strip():
            return None

        # ElevenLabs path
        if use_elevenlabs_tts and self._elevenlabs_client and ELEVENLABS_VOICE_ID:
            try:
                audio_iter = self._elevenlabs_client.text_to_speech.convert(
                    text=plain_text,
                    voice_id=ELEVENLABS_VOICE_ID,
                    model_id="eleven_multilingual_v2",
                    output_format="mp3_44100_128",
                )
                audio_content = b"".join(audio_iter) if hasattr(audio_iter, "__iter__") else bytes(audio_iter)
                if audio_content:
                    safe_name = f"tts/utterance_{abs(hash(ELEVENLABS_VOICE_ID + '|' + text))}.mp3"
                    return default_storage.save(safe_name, ContentFile(audio_content))
            except Exception:
                pass

        # Google Cloud TTS path
        if self._google_tts_client and texttospeech:
            sr = speaking_rate if speaking_rate is not None else getattr(settings, "TTS_DEFAULT_SPEAKING_RATE", 1.0)
            pt = pitch if pitch is not None else getattr(settings, "TTS_DEFAULT_PITCH", 0.0)
            vg = volume_gain_db if volume_gain_db is not None else getattr(settings, "TTS_DEFAULT_VOLUME_GAIN_DB", 0.0)
            candidate_voices = getattr(settings, "TTS_CANDIDATE_VOICES", ["en-US-Neural2-F", "en-US-Wavenet-F", "en-US-Standard-F"])
            language_code = getattr(settings, "TTS_LANGUAGE_CODE", "en-US")
            ssml_gender = getattr(settings, "TTS_SSML_GENDER", "FEMALE")
            if use_ssml and not text.strip().startswith("<speak"):
                ssml_text = f'<speak><prosody rate="{sr}" pitch="{pt}st">{text}</prosody></speak>'
                synthesis_input = texttospeech.SynthesisInput(ssml=ssml_text)
            else:
                synthesis_input = texttospeech.SynthesisInput(text=plain_text)
            audio_config = texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.MP3,
                speaking_rate=sr,
                pitch=pt,
                volume_gain_db=vg,
            )
            for candidate in candidate_voices:
                try:
                    voice_params = texttospeech.VoiceSelectionParams(
                        language_code=language_code,
                        name=candidate,
                        ssml_gender=ssml_gender,
                    )
                    response = self._google_tts_client.synthesize_speech(
                        input=synthesis_input,
                        voice=voice_params,
                        audio_config=audio_config,
                    )
                    safe_name = f"tts/utterance_{abs(hash(candidate + '|' + text))}.mp3"
                    return default_storage.save(safe_name, ContentFile(response.audio_content))
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