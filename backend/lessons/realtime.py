import os
import json
import asyncio
from channels.generic.websocket import AsyncWebsocketConsumer
from vectordbquire import retrieve_from_vector_db

class LiveConsumer(AsyncWebsocketConsumer):
    """Server-side bridge between browser and Gemini Live API.

    Client protocol:
      - JSON { type: 'start' } to begin
      - Binary: 16-bit PCM mono at 16kHz frames (Uint8Array of Int16 buffer)
      - JSON { type: 'text', text: '...' } to send a text turn
      - JSON { type: 'stop' } to end

    Server sends:
      - Binary: 16-bit PCM mono at 24kHz audio frames from the model
      - JSON events for lightweight statuses if needed
    """

    async def connect(self):
        self.session_id = int(self.scope['url_route']['kwargs']['session_id'])
        await self.accept()
        self._collecting = False
        self._live_task = None
        self._session = None
        self._gemini_ok = False
        self._audio_chunks_out = 0

        # Lazy import google-genai
        try:
            from google import genai  # type: ignore
            self._genai = genai
            api_key = os.getenv('GOOGLE_AI_API_KEY', '')
            self._client = genai.Client(api_key=api_key) if api_key else None
            self._gemini_ok = self._client is not None
        except Exception as e:
            self._genai = None
            self._client = None
            self._gemini_ok = False
            await self._send_json({ 'event': 'error', 'detail': f'genai import/init failed: {e}' })

        await self._send_json({ 'event': 'connected', 'gemini': self._gemini_ok })
        if not self._gemini_ok:
            await self._send_json({ 'event': 'error', 'detail': 'Gemini Live unavailable on server' })

    async def disconnect(self, code):
        self._collecting = False
        try:
            if self._live_task:
                self._live_task.cancel()
        except Exception:
            pass
        try:
            if self._session:
                await self._session.aclose()  # type: ignore[attr-defined]
        except Exception:
            pass

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is not None:
            try:
                msg = json.loads(text_data)
            except Exception:
                return
            t = msg.get('type')
            if t == 'start':
                await self._ensure_live_started()
                self._collecting = True
                await self._send_json({ 'event': 'recording' })
            elif t == 'stop':
                self._collecting = False
                await self.close()
            elif t == 'commit':
                # Stop collecting to let model process current turn
                self._collecting = False
                # Nudge the model with a brief text to ensure a response is produced
                try:
                    if self._session:
                        await self._session.send_realtime_input(text="Please respond briefly to conclude this turn.")  # type: ignore
                except Exception:
                    pass
                await self._send_json({ 'event': 'committed' })
            elif t == 'text':
                await self._ensure_live_started()
                if self._session:
                    user_text = str(msg.get('text', ''))
                    try:
                        results = await asyncio.to_thread(retrieve_from_vector_db, user_text, 3)
                        if results:
                            context_parts = []
                            for r in results:
                                ctx = f"Title: {r.get('title', '')}\nPlan: {r.get('plan', '')}"
                                context_parts.append(ctx)
                            context_text = "\n\n".join(context_parts)
                        else:
                            context_text = ""
                    except Exception as e:
                        context_text = ""
                        await self._send_json({
                        'event': 'error',
                        'detail': f'Vector DB retrieval failed: {e}'
                    })

                    full_prompt = user_text
                    if context_text:
                        full_prompt += f"\n\nRelevant context:\n{context_text}"

                    await self._session.send_realtime_input(text=full_prompt)

        elif bytes_data is not None and self._collecting:
            # Forward PCM16@16k chunk to Gemini
            if not self._session:
                await self._ensure_live_started()
            if self._session:
                try:
                    from google.genai import types  # type: ignore
                    await self._session.send_realtime_input(  # type: ignore
                        audio=types.Blob(data=bytes_data, mime_type="audio/pcm;rate=16000")
                    )
                except Exception:
                    pass

    async def _ensure_live_started(self):
        if self._session or not self._gemini_ok:
            return
        # Start live session and background forwarder
        try:
            self._session = await self._client.aio.live.connect(  # type: ignore[attr-defined]
                model="models/gemini-2.0-flash-live-001",
                config={
                    "response_modalities": ["AUDIO"],
                    "system_instruction": "You are a helpful assistant and answer in a friendly tone.",
                },
            ).__aenter__()
            # Send a tiny greeting to kick the model to produce audio after first commit
            await self._session.send_realtime_input(text="Hello, please acknowledge in a short sentence.")  # type: ignore
            await self._send_json({ 'event': 'live_started' })
        except Exception as e:
            self._session = None
            await self._send_json({ 'event': 'error', 'detail': f'Failed to start live session: {e}' })
            return

        async def pump_from_model():
            try:
                async for response in self._session.receive():  # type: ignore
                    if getattr(response, 'data', None) is not None:
                        await self.send(bytes_data=response.data)  # type: ignore
                        self._audio_chunks_out += 1
                        await self._send_json({ 'event': 'audio_progress', 'chunks': self._audio_chunks_out, 'bytes': len(response.data) if hasattr(response, 'data') else 0 })
                    else:
                        server_content = getattr(response, 'server_content', None)
                        if server_content and getattr(server_content, 'turn_complete', False):
                            await self._send_json({ 'event': 'turn_complete' })
            except asyncio.CancelledError:
                return
            except Exception as e:
                await self._send_json({ 'event': 'error', 'detail': f'pump error: {e}' })
                return

        self._live_task = asyncio.create_task(pump_from_model())

    async def _send_json(self, payload: dict):
        await self.send(text_data=json.dumps(payload))


