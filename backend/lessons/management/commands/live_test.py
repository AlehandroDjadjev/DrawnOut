import os
import json
import time
import wave
from pathlib import Path
from urllib.parse import quote
import asyncio

from django.core.management.base import BaseCommand
from django.conf import settings


class Command(BaseCommand):
    help = "Server-to-server Live API connectivity test: opens WS, requests short audio reply, saves WAV."

    def add_arguments(self, parser):
        parser.add_argument(
            "--model",
            default="models/gemini-2.0-flash-live-001",
            help="Live model to use (e.g., models/gemini-2.0-flash-live-001)",
        )
        parser.add_argument(
            "--text",
            default="Please say a short greeting so I can verify audio streaming works.",
            help="Text to prompt the model with (will request audio response)",
        )
        parser.add_argument(
            "--seconds",
            type=int,
            default=6,
            help="Max seconds to listen for audio before closing",
        )

    def handle(self, *args, **options):
        api_key = os.getenv("GOOGLE_AI_API_KEY", "")
        if not api_key:
            self.stderr.write("GOOGLE_AI_API_KEY is not set in environment.")
            return None

        model = options["model"]
        prompt_text = options["text"]
        listen_seconds = max(1, options["seconds"])

        # Prefer official SDK for Live; it handles the correct transport.
        try:
            asyncio.run(self._run_sdk_live_test(api_key, model, prompt_text, listen_seconds))
            return None
        except Exception as e:
            self.stderr.write(f"SDK live test failed: {e}")

        # Fallback to raw websocket-client (may not work if endpoint/protocol changes)
        try:
            import websocket  # websocket-client
        except Exception:
            self.stderr.write(
                "websocket-client not installed. Install with: pip install websocket-client"
            )
            return None

        url = "wss://generativelanguage.googleapis.com/v1alpha/live:connect"
        self.stdout.write("Connecting to Live API (server-to-server, header auth)...")

        ws = None
        wav_path = Path(settings.MEDIA_ROOT) / "live_test_output.wav"
        wav_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            ws = websocket.create_connection(
                url,
                timeout=10,
                header=[f"x-goog-api-key: {api_key}"],
            )
            try:
                ws.settimeout(1)
            except Exception:
                pass
            self.stdout.write("WebSocket open")

            setup_msg = {
                "setup": {
                    "model": model,
                    "response_modalities": ["AUDIO"],
                    "system_instruction": "You are a helpful assistant and answer in a friendly tone.",
                }
            }
            ws.send(json.dumps(setup_msg))
            ws.send(json.dumps({"realtime_input": {"text": prompt_text}}))

            wf = wave.open(str(wav_path), "wb")
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(24000)

            start = time.time()
            turn_complete = False
            while time.time() - start < listen_seconds:
                try:
                    frame = ws.recv()
                except Exception:
                    continue
                if isinstance(frame, (bytes, bytearray)):
                    wf.writeframes(frame)
                else:
                    try:
                        data = json.loads(frame)
                        if data.get("server_content", {}).get("turn_complete"):
                            turn_complete = True
                            break
                    except Exception:
                        pass

            wf.close()
            ws.close()

            if wav_path.exists() and wav_path.stat().st_size > 44:
                self.stdout.write(f"Saved audio to: {wav_path}")
            else:
                self.stderr.write("No audio received (file empty)")
            if not turn_complete:
                self.stderr.write("Turn did not complete before timeout; increase --seconds if needed.")
            return None
        except Exception as e:
            self.stderr.write(f"Live test failed: {e}")
            try:
                if ws is not None:
                    ws.close()
            except Exception:
                pass
            return None

    async def _run_sdk_live_test(self, api_key: str, model: str, prompt_text: str, listen_seconds: int):
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=api_key)
        wav_path = Path(settings.MEDIA_ROOT) / "live_test_output.wav"
        wav_path.parent.mkdir(parents=True, exist_ok=True)

        async with client.aio.live.connect(model=model, config={
            "response_modalities": ["AUDIO"],
            "system_instruction": "You are a helpful assistant and answer in a friendly tone.",
        }) as session:
            await session.send_realtime_input(text=prompt_text)
            wf = wave.open(str(wav_path), "wb")
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(24000)
            start = time.time()
            async for response in session.receive():
                if response.data is not None:
                    wf.writeframes(response.data)
                if time.time() - start > listen_seconds:
                    break
            wf.close()

        if wav_path.exists() and wav_path.stat().st_size > 44:
            self.stdout.write(f"Saved audio to: {wav_path}")
        else:
            self.stderr.write("No audio received (file empty)")


