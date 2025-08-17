from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status, permissions, generics
from django.shortcuts import get_object_or_404
from users.models import CustomUser

from .models import LessonSession, Utterance, Lesson
from .serializers import LessonSessionSerializer, UtteranceSerializer, LessonSerializer
from .services import TutorEngine
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny
from django.conf import settings
import os
import logging
import sys
import json
import time
import platform
from urllib.request import Request, urlopen
from urllib.error import URLError


class StartLessonView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        topic = request.data.get('topic') or 'Pythagorean Theorem'
        engine = TutorEngine()
        plan = engine.build_lesson_plan(topic)

        session = LessonSession.objects.create(
            user=request.user if request.user and request.user.is_authenticated else None,
            topic=topic,
            lesson_plan=plan,
            current_step_index=0,
            is_waiting_for_question=False,
            is_completed=False,
        )

        # Speak the first step
        step_text = engine.continue_step(plan[0])
        audio_path = engine.synthesize_speech(step_text)
        Utterance.objects.create(session=session, role='tutor', text=step_text, audio_file=audio_path)

        # Do not wait for questions by default; frontend handles raise-hand after playback
        session.is_waiting_for_question = False
        session.save(update_fields=["is_waiting_for_question", "updated_at"])

        serializer = LessonSessionSerializer(session)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class NextSegmentView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request, session_id: int):
        engine = TutorEngine()
        session = get_object_or_404(LessonSession, pk=session_id)
        user = request.user

        if session.is_completed:
            return Response({"detail": "Lesson already completed."}, status=status.HTTP_400_BAD_REQUEST)

        # If we were waiting for a question previously, toggling off once question answered happens in RaiseHandView
        if session.is_waiting_for_question:
            # Tutor continues from the same step after having answered
            pass

        # Advance to next step if possible
        if session.current_step_index < len(session.lesson_plan) - 1:
            session.current_step_index += 1

        step_text = engine.continue_step(session.lesson_plan[session.current_step_index])
        audio_path = engine.synthesize_speech(step_text)
        Utterance.objects.create(session=session, role='tutor', text=step_text, audio_file=audio_path)

        # If this is the last step, mark completed after speaking
        if session.current_step_index >= len(session.lesson_plan) - 1:
            session.is_completed = True
            user.credits += 10
            session.is_waiting_for_question = False
        else:
            # Frontend controls raise-hand; keep waiting flag false
            session.is_waiting_for_question = False
        session.save(update_fields=["current_step_index", "is_completed", "is_waiting_for_question", "updated_at"])

        return Response(LessonSessionSerializer(session).data)


class RaiseHandView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request, session_id: int):
        engine = TutorEngine()
        session = get_object_or_404(LessonSession, pk=session_id)
        # Allow questions whenever called (frontend enforces timing)

        # If question absent and Gemini Live is desired, open live chat mode flag
        start_live = request.data.get('start_live') in (True, 'true', '1')
        if start_live:
            # Enter live mode immediately without requiring an initial question.
            # The chat session will be lazily started on the first /live/ message if needed.
            data = LessonSessionSerializer(session).data
            data['live'] = True
            return Response(data)

        # Accept either text question or audio file for STT
        question_text = request.data.get('question')
        if not question_text and 'audio' in request.FILES:
            audio_file = request.FILES['audio']
            question_text = engine.transcribe_audio(audio_file.read(), audio_file.name)

        # If no content provided (and not live), simply mark waiting and return
        if not question_text:
            session.is_waiting_for_question = True
            session.save(update_fields=["is_waiting_for_question", "updated_at"])
            data = LessonSessionSerializer(session).data
            data['live'] = False
            return Response(data)

        step_text = session.lesson_plan[session.current_step_index]

        # (If start_live was requested we already returned above.)

        answer = engine.answer_question(step_text, question_text)
        # Store student's question
        Utterance.objects.create(session=session, role='student', text=question_text)
        # Store tutor's answer
        audio_path = engine.synthesize_speech(answer)
        Utterance.objects.create(session=session, role='tutor', text=answer, audio_file=audio_path)

        # After answering, continue exactly where we left off: move to next step if any
        if session.current_step_index < len(session.lesson_plan) - 1:
            session.current_step_index += 1
            next_text = engine.continue_step(session.lesson_plan[session.current_step_index])
            next_audio = engine.synthesize_speech(next_text)
            Utterance.objects.create(session=session, role='tutor', text=next_text, audio_file=next_audio)
            # Allow another question after the new sentence
            session.is_waiting_for_question = False
            session.is_completed = session.current_step_index >= len(session.lesson_plan) - 1
        else:
            # Already on last step; lesson ends
            session.is_completed = True
            session.is_waiting_for_question = False

        session.save(update_fields=["current_step_index", "is_waiting_for_question", "is_completed", "updated_at"])

        return Response(LessonSessionSerializer(session).data)


class LiveChatView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request, session_id: int):
        engine = TutorEngine()
        session = get_object_or_404(LessonSession, pk=session_id)
        user_text = request.data.get('message', '')
        if not user_text:
            return Response({"detail": "message is required"}, status=400)
        reply = engine.live_message(session.id, user_text) or "I didn't catch that. Could you rephrase?"
        Utterance.objects.create(session=session, role='student', text=user_text)
        audio = engine.synthesize_speech(reply)
        Utterance.objects.create(session=session, role='tutor', text=reply, audio_file=audio)
        data = LessonSessionSerializer(session).data
        data['live'] = True
        return Response(data)

    def delete(self, request, session_id: int):
        engine = TutorEngine()
        session = get_object_or_404(LessonSession, pk=session_id)
        engine.end_live_chat(session.id)
        # After ending live, auto-advance to next lesson step
        if session.current_step_index < len(session.lesson_plan) - 1:
            session.current_step_index += 1
            next_text = TutorEngine().continue_step(session.lesson_plan[session.current_step_index])
            next_audio = TutorEngine().synthesize_speech(next_text)
            Utterance.objects.create(session=session, role='tutor', text=next_text, audio_file=next_audio)
            session.is_completed = session.current_step_index >= len(session.lesson_plan) - 1
        else:
            session.is_completed = True
        session.save(update_fields=["current_step_index", "is_completed", "updated_at"])
        data = LessonSessionSerializer(session).data
        data['live'] = False
        return Response(data)


class SessionDetailView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, session_id: int):
        session = get_object_or_404(LessonSession, pk=session_id)
        return Response(LessonSessionSerializer(session).data)


class LiveSDPView(APIView):
    permission_classes = [AllowAny]

    def post(self, request, session_id: int):
        offer = request.data.get('offer')
        model = request.data.get('model', 'models/gemini-2.0-flash-live-001')
        if not offer:
            return Response({"detail": "offer is required"}, status=400)
        # Placeholder: integrate Gemini Live WebRTC signaling here.
        return Response({"detail": "Gemini Live WebRTC signaling not yet configured", "model": model}, status=501)


class LiveTokenView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        # Preferred: mint ephemeral token via google genai SDK (v1alpha)
        try:
            from google import genai  # pip install google-genai
            client = genai.Client(api_key=os.getenv('GOOGLE_AI_API_KEY') or None)
            tok = None
            # Try multiple creation paths across library versions
            try:
                tok = getattr(getattr(client, 'auth', None), 'tokens', None)
                tok = tok.create(config={'uses': 1, 'http_options': { 'api_version': 'v1alpha' }}) if tok else None
            except Exception:
                tok = None
            if tok is None:
                try:
                    tokens_obj = getattr(client, 'tokens', None)
                    if tokens_obj and hasattr(tokens_obj, 'create'):
                        tok = tokens_obj.create(config={'uses': 1, 'http_options': { 'api_version': 'v1alpha' }})
                except Exception:
                    tok = None
            if tok is not None:
                return Response({ 'token': getattr(tok, 'name', ''), 'mode': 'ephemeral' })
        except Exception as e:
            logging.getLogger(__name__).warning("Ephemeral token mint failed: %s", e)

        # Fallback: allow insecure dev by returning long-lived key (local only)
        allow_insecure = os.getenv('LIVE_INSECURE_DEV', '1') == '1' or getattr(settings, 'DEBUG', False)
        if allow_insecure:
            token = os.getenv('GOOGLE_AI_API_KEY', '')
            if token:
                return Response({"token": token, "mode": "insecure-dev"})

        # Optional: proxy to external token minter
        proxy_url = os.getenv('LIVE_TOKEN_URL', '')
        if proxy_url:
            try:
                import urllib.request, json as pyjson
                with urllib.request.urlopen(proxy_url, timeout=5) as resp:
                    body = pyjson.loads(resp.read().decode('utf-8'))
                    if 'token' in body:
                        return Response(body)
                    return Response({"detail": "Token proxy did not return token"}, status=502)
            except Exception as e:
                return Response({"detail": f"Token proxy error: {e}"}, status=502)

        return Response({"detail": "Unable to mint Live token. Install google-genai or configure LIVE_TOKEN_URL or LIVE_INSECURE_DEV=1."}, status=500)


class DiagnosticsView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        started_at = time.time()
        info = {}
        # Basic runtime
        info['runtime'] = {
            'python': sys.version.split()[0],
            'platform': platform.platform(),
        }
        # Django/Channels presence
        try:
            import django
            info['runtime']['django'] = getattr(django, '__version__', 'unknown')
        except Exception as e:
            info['runtime']['django'] = f'error: {e}'
        try:
            import channels
            info['runtime']['channels'] = getattr(channels, '__version__', 'present')
        except Exception:
            info['runtime']['channels'] = 'absent'

        # Env checks (masked)
        def mask(val: str) -> str:
            if not val:
                return ''
            return ('*' * max(0, len(val) - 4)) + val[-4:]

        env = {
            'DEBUG': getattr(settings, 'DEBUG', False),
            'GOOGLE_AI_API_KEY_set': bool(os.getenv('GOOGLE_AI_API_KEY')),
            'GOOGLE_AI_API_KEY_masked': mask(os.getenv('GOOGLE_AI_API_KEY', '')),
            'OPENAI_API_KEY_set': bool(os.getenv('OPENAI_API_KEY')),
            'OPENAI_API_KEY_masked': mask(os.getenv('OPENAI_API_KEY', '')),
            'GOOGLE_APPLICATION_CREDENTIALS': os.getenv('GOOGLE_APPLICATION_CREDENTIALS', ''),
            'LIVE_INSECURE_DEV': os.getenv('LIVE_INSECURE_DEV', ''),
        }
        creds_path = env['GOOGLE_APPLICATION_CREDENTIALS']
        env['GOOGLE_APPLICATION_CREDENTIALS_exists'] = bool(creds_path and os.path.isfile(creds_path))
        info['env'] = env

        # Network reachability
        net = {}
        try:
            req = Request('https://generativelanguage.googleapis.com/', method='HEAD')
            with urlopen(req, timeout=3) as resp:  # nosec - diagnostic only
                net['generativelanguage_googleapis'] = resp.status
        except URLError as e:
            net['generativelanguage_googleapis'] = f'error: {e}'
        except Exception as e:
            net['generativelanguage_googleapis'] = f'error: {e}'
        info['network'] = net

        # google-genai ephemeral token test
        live = { 'ephemeral_token': 'unavailable' }
        try:
            from google import genai  # pip install google-genai
            client = genai.Client(api_key=os.getenv('GOOGLE_AI_API_KEY') or None)
            tok = None
            try:
                tok_obj = getattr(getattr(client, 'auth', None), 'tokens', None)
                if tok_obj and hasattr(tok_obj, 'create'):
                    tok = tok_obj.create(config={'uses': 1, 'http_options': { 'api_version': 'v1alpha' }})
            except Exception:
                tok = None
            if tok is None:
                try:
                    tokens_obj = getattr(client, 'tokens', None)
                    if tokens_obj and hasattr(tokens_obj, 'create'):
                        tok = tokens_obj.create(config={'uses': 1, 'http_options': { 'api_version': 'v1alpha' }})
                except Exception:
                    tok = None
            live['ephemeral_token'] = 'ok' if (tok and getattr(tok, 'name', '')) else 'unavailable'
        except Exception as e:
            live['ephemeral_token'] = f'lib-missing: {e}'
        info['live_api'] = live

        # Google TTS check
        tts = { 'available': False }
        try:
            from google.cloud import texttospeech
            client = texttospeech.TextToSpeechClient()
            # light call: list voices (no billing)
            voices = client.list_voices()
            tts['available'] = True
            tts['voices'] = len(getattr(voices, 'voices', []) or [])
        except Exception as e:
            tts['error'] = str(e)
        info['google_tts'] = tts

        info['took_ms'] = int((time.time() - started_at) * 1000)
        return Response(info)

# --- New: Diagram generation proxy (OpenAI gpt-image-1) ---
from rest_framework.permissions import AllowAny
import base64, requests

class DiagramView(APIView):
    permission_classes = [AllowAny]
    def post(self, request):
        prompt = (request.data.get('prompt') or '').strip()
        size = (request.data.get('size') or '256x256')
        want_debug = (str(request.query_params.get('debug', '')).lower() in ('1','true','yes') or
                      str(request.data.get('debug', '')).lower() in ('1','true','yes'))
        debug_steps = []
        if not prompt:
            return Response({'detail': 'prompt required'}, status=400)

        # Prefer Google Imagen over OpenAI; require GOOGLE_AI_API_KEY
        google_key = os.getenv('GOOGLE_AI_API_KEY', '') or os.getenv('GEMINI_API_KEY', '')
        if not google_key:
            return Response({'detail': 'GOOGLE_AI_API_KEY not set'}, status=500)

        # Prefer the official google-genai SDK to avoid endpoint drift
        try:
            from google import genai  # pip install google-genai
        except Exception as e:
            return Response({'detail': f'google-genai not installed: {e}'}, status=500)

        try:
            client = genai.Client(api_key=google_key)
            # Preferred model IDs per latest SDK
            primary_model = 'imagen-4.0-generate-001'
            alt_model = 'imagen-4.0-ultra-generate-001'
            # Try common SDK methods (different versions expose different surfaces)
            resp = None
            try:
                debug_steps.append({'stage': 'sdk.generate_images', 'model': primary_model})
                resp = client.models.generate_images(
                    model=primary_model,
                    prompt=prompt,
                    config={
                        'numberOfImages': 1,
                        'aspectRatio': '1:1',
                        'sampleImageSize': '1K',
                        'personGeneration': 'dont_allow',
                    },
                )
            except Exception:
                try:
                    debug_steps.append({'stage': 'sdk.images.generate', 'model': primary_model})
                    resp = client.images.generate(
                        model=primary_model,
                        prompt=prompt,
                        aspect_ratio='1:1',
                        number_of_images=1,
                        sample_image_size='1K',
                        person_generation='dont_allow',
                    )
                except Exception as e2:
                    # SDK path failed; fall back to REST
                    resp = None
                    debug_steps.append({'stage': 'sdk.error', 'error': str(e2)})
            if resp is None:
                import requests as _rq
                # First, try v1beta/images:generate (Generative Language API)
                url = 'https://generativelanguage.googleapis.com/v1beta/images:generate'
                q = { 'key': google_key }
                pl = {
                    'model': f'models/{primary_model}',
                    'prompt': { 'text': prompt },
                    'config': {
                        'numberOfImages': 1,
                        'aspectRatio': '1:1',
                        'sampleImageSize': '1K',
                        'personGeneration': 'dont_allow',
                    },
                }
                rr = _rq.post(url, params=q, json=pl, timeout=60)
                debug_steps.append({'stage': 'rest.images:generate', 'endpoint': url, 'status': rr.status_code, 'len': len(rr.text or '')})
                if rr.status_code // 100 != 2:
                    # Try legacy model method path
                    url2 = f'https://generativelanguage.googleapis.com/v1beta/models/{primary_model}:generateImages'
                    rr = _rq.post(url2, params=q, json={
                        'prompt': { 'text': prompt },
                        'config': {
                            'numberOfImages': 1,
                            'aspectRatio': '1:1',
                            'sampleImageSize': '1K',
                            'personGeneration': 'dont_allow',
                        },
                    }, timeout=60)
                    debug_steps.append({'stage': 'rest.models:generateImages', 'endpoint': url2, 'status': rr.status_code, 'len': len(rr.text or '')})
                    if rr.status_code // 100 != 2:
                        return Response({'detail': f'gemini error {rr.status_code}', 'body': rr.text or '(empty)', 'debug': debug_steps}, status=502)
                data = rr.json() if rr.content else {}
                # Extract base64 from REST response
                b64 = ''
                # New style
                try:
                    imgs = data.get('generatedImages') or []
                    if imgs:
                        img0 = imgs[0].get('image') or {}
                        b64 = (img0.get('imageBytes') or '').strip()
                except Exception:
                    pass
                if not b64:
                    try:
                        cand = (data.get('candidates') or [])[0]
                        parts = ((cand.get('content') or {}).get('parts') or [])
                        if parts:
                            inline = parts[0].get('inlineData') or {}
                            b64 = (inline.get('data') or '').strip()
                    except Exception:
                        b64 = ''
                if not b64:
                    return Response({'detail': 'no image in response', 'body': data, 'debug': debug_steps}, status=502)
                return Response({'image_b64': b64})

            # Extract base64 from response object, trying common attribute shapes
            b64 = ''
            try:
                # Preferred response shape
                gi = getattr(resp, 'generated_images', None) or getattr(resp, 'generatedImages', None) or []
                if gi:
                    img0 = gi[0]
                    image = getattr(img0, 'image', None) or {}
                    b64 = getattr(image, 'image_bytes', None) or getattr(image, 'imageBytes', None) or ''
                    if isinstance(b64, bytes):
                        import base64 as _b64
                        b64 = _b64.b64encode(b64).decode('utf-8')
            except Exception:
                b64 = ''
            if not b64:
                # Some versions return dict-like
                try:
                    d = dict(resp)
                    arr = d.get('generatedImages') or d.get('images') or []
                    if arr:
                        img0 = arr[0]
                        iobj = img0.get('image') or img0
                        b64 = iobj.get('imageBytes') or iobj.get('bytesBase64Encoded') or ''
                except Exception:
                    b64 = ''
            if not b64:
                return Response({'detail': 'no image in SDK response', 'debug': debug_steps}, status=502)
            return Response({'image_b64': b64})
        except Exception as e:
            debug_steps.append({'stage': 'sdk.exception', 'error': str(e)})
            return Response({'detail': f'gemini sdk request failed: {e}', 'debug': debug_steps}, status=502)
class LessonCreateView(generics.CreateAPIView):
    queryset = Lesson.objects.all()
    serializer_class = LessonSerializer
    permission_classes = [permissions.IsAdminUser]

class LessonGetView(APIView):
    def get(self, request, lesson_id):
        try:
            lesson = Lesson.objects.get(id=lesson_id)
            serializer = LessonSerializer(lesson)
            return Response(serializer.data)
        except Lesson.DoesNotExist:
            return Response({"error": "Lesson not found"}, status=status.HTTP_404_NOT_FOUND)
        

class LessonsListView(generics.ListAPIView):
    queryset = Lesson.objects.all()
    serializer_class = LessonSerializer

