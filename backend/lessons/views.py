from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status, permissions, generics
from rest_framework.exceptions import ValidationError
from django.shortcuts import get_object_or_404
from users.models import CustomUser
from django.utils import timezone

from .models import LessonSession, Utterance, Lesson, LessonProgress
from .serializers import (
    LessonSessionSerializer,
    UtteranceSerializer,
    LessonSerializer,
    LessonWithProgressSerializer,
)
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


def _mark_lesson_started(user, lesson: Lesson) -> None:
    if user is None or not getattr(user, 'is_authenticated', False):
        return
    if lesson is None:
        return

    lp, _ = LessonProgress.objects.get_or_create(user=user, lesson=lesson)
    if lp.state == LessonProgress.State.COMPLETED:
        return

    now = timezone.now()
    lp.state = LessonProgress.State.IN_PROGRESS
    if lp.started_at is None:
        lp.started_at = now
    lp.completed_at = None
    lp.save(update_fields=['state', 'started_at', 'completed_at', 'updated_at'])


def _mark_lesson_completed(user, lesson: Lesson) -> None:
    if user is None or not getattr(user, 'is_authenticated', False):
        return
    if lesson is None:
        return

    lp, _ = LessonProgress.objects.get_or_create(user=user, lesson=lesson)
    now = timezone.now()
    lp.state = LessonProgress.State.COMPLETED
    if lp.started_at is None:
        lp.started_at = now
    if lp.completed_at is None:
        lp.completed_at = now
    lp.save(update_fields=['state', 'started_at', 'completed_at', 'updated_at'])


class StartLessonView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        lesson_obj = None
        lesson_id = request.data.get('lesson_id')
        if lesson_id is not None:
            try:
                lesson_obj = Lesson.objects.get(id=int(lesson_id))
            except (ValueError, TypeError, Lesson.DoesNotExist):
                lesson_obj = None

        topic = request.data.get('topic') or (lesson_obj.title if lesson_obj else 'Pythagorean Theorem')
        if lesson_obj is None and topic:
            # Best-effort linking: if topic matches a known lesson title, link it.
            try:
                lesson_obj = Lesson.objects.get(title__iexact=str(topic).strip())
            except Lesson.DoesNotExist:
                lesson_obj = None
        use_existing_images = request.data.get('use_existing_images', False) in (True, 'true', '1')
        use_elevenlabs_tts = request.data.get('use_elevenlabs_tts', False) in (True, 'true', '1')
        engine = TutorEngine()
        plan = engine.build_lesson_plan(topic)

        session = LessonSession.objects.create(
            user=request.user if request.user and request.user.is_authenticated else None,
            lesson=lesson_obj,
            topic=topic,
            lesson_plan=plan,
            current_step_index=0,
            is_waiting_for_question=False,
            is_completed=False,
            use_existing_images=use_existing_images,
            use_elevenlabs_tts=use_elevenlabs_tts,
        )

        # Speak the first step
        step_text = engine.continue_step(plan[0])
        audio_path = engine.synthesize_speech(step_text, use_elevenlabs_tts=use_elevenlabs_tts)
        Utterance.objects.create(session=session, role='tutor', text=step_text, audio_file=audio_path)

        # Do not wait for questions by default; frontend handles raise-hand after playback
        session.is_waiting_for_question = False
        session.save(update_fields=["is_waiting_for_question", "updated_at"])

        if session.user_id and session.lesson_id:
            _mark_lesson_started(request.user, lesson_obj)

        serializer = LessonSessionSerializer(session)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class NextSegmentView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request, session_id: int):
        engine = TutorEngine()
        session = get_object_or_404(LessonSession, pk=session_id)

        if session.is_completed:
            return Response({"detail": "Lesson already completed."}, status=status.HTTP_400_BAD_REQUEST)

        # If we were waiting for a question previously, toggling off once question answered happens in RaiseHandView
        if session.is_waiting_for_question:
            # Tutor continues from the same step after having answered
            pass

        # Advance to next step if possible
        if session.current_step_index < len(session.lesson_plan) - 1:
            session.current_step_index += 1

        use_elevenlabs_tts = getattr(session, 'use_elevenlabs_tts', False)
        step_text = engine.continue_step(session.lesson_plan[session.current_step_index])
        audio_path = engine.synthesize_speech(step_text, use_elevenlabs_tts=use_elevenlabs_tts)
        Utterance.objects.create(session=session, role='tutor', text=step_text, audio_file=audio_path)

        # If this is the last step, mark completed after speaking
        if session.current_step_index >= len(session.lesson_plan) - 1:
            session.is_completed = True
            session.is_waiting_for_question = False
        else:
            # Frontend controls raise-hand; keep waiting flag false
            session.is_waiting_for_question = False
        session.save(update_fields=["current_step_index", "is_completed", "is_waiting_for_question", "updated_at"])

        if session.is_completed and session.user_id and session.lesson_id:
            _mark_lesson_completed(session.user, session.lesson)

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

        use_elevenlabs_tts = getattr(session, 'use_elevenlabs_tts', False)
        answer = engine.answer_question(step_text, question_text)
        # Store student's question
        Utterance.objects.create(session=session, role='student', text=question_text)
        # Store tutor's answer
        audio_path = engine.synthesize_speech(answer, use_elevenlabs_tts=use_elevenlabs_tts)
        Utterance.objects.create(session=session, role='tutor', text=answer, audio_file=audio_path)

        # After answering, continue exactly where we left off: move to next step if any
        if session.current_step_index < len(session.lesson_plan) - 1:
            session.current_step_index += 1
            next_text = engine.continue_step(session.lesson_plan[session.current_step_index])
            next_audio = engine.synthesize_speech(next_text, use_elevenlabs_tts=use_elevenlabs_tts)
            Utterance.objects.create(session=session, role='tutor', text=next_text, audio_file=next_audio)
            # Allow another question after the new sentence
            session.is_waiting_for_question = False
            session.is_completed = session.current_step_index >= len(session.lesson_plan) - 1
        else:
            # Already on last step; lesson ends
            session.is_completed = True
            session.is_waiting_for_question = False

        session.save(update_fields=["current_step_index", "is_waiting_for_question", "is_completed", "updated_at"])

        if session.is_completed and session.user_id and session.lesson_id:
            _mark_lesson_completed(session.user, session.lesson)

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
        use_elevenlabs_tts = getattr(session, 'use_elevenlabs_tts', False)
        audio = engine.synthesize_speech(reply, use_elevenlabs_tts=use_elevenlabs_tts)
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
            use_elevenlabs_tts = getattr(session, 'use_elevenlabs_tts', False)
            next_text = engine.continue_step(session.lesson_plan[session.current_step_index])
            next_audio = engine.synthesize_speech(next_text, use_elevenlabs_tts=use_elevenlabs_tts)
            Utterance.objects.create(session=session, role='tutor', text=next_text, audio_file=next_audio)
            session.is_completed = session.current_step_index >= len(session.lesson_plan) - 1
        else:
            session.is_completed = True
        session.save(update_fields=["current_step_index", "is_completed", "updated_at"])

        if session.is_completed and session.user_id and session.lesson_id:
            _mark_lesson_completed(session.user, session.lesson)
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
        google_tts = {'available': False}
        try:
            from google.cloud import texttospeech
            client = texttospeech.TextToSpeechClient()
            voices = client.list_voices()
            google_tts['available'] = True
            google_tts['voices'] = len(getattr(voices, 'voices', []) or [])
        except Exception as e:
            google_tts['error'] = str(e)
        info['google_tts'] = google_tts

        # ElevenLabs TTS check (Netanyahu + voice_id env vars)
        elevenlabs_tts = {'available': False}
        try:
            api_key = os.getenv('Netanyahu', '')
            voice_id = os.getenv('voice_id', '')
            if api_key and voice_id:
                from elevenlabs.client import ElevenLabs
                ElevenLabs(api_key=api_key)
                elevenlabs_tts['available'] = True
                elevenlabs_tts['voice_id'] = voice_id
        except Exception as e:
            elevenlabs_tts['error'] = str(e)
        info['elevenlabs_tts'] = elevenlabs_tts

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
        want_debug = True
        debug_steps = []

        if not prompt:
            return Response({'detail': 'prompt required'}, status=400)

        # --- Ephemeral token retrieval ---
        google_key = os.getenv('GOOGLE_AI_API_KEY', '') or os.getenv('GEMINI_API_KEY', '')
        if not google_key:
            return Response({'detail': 'GOOGLE_AI_API_KEY not set'}, status=500)

        try:
            from google import genai
        except Exception as e:
            return Response({'detail': f'google-genai not installed: {e}'}, status=500)

        try:
            client = genai.Client(api_key=google_key)
            primary_model = 'imagen-4.0-generate-001'
            resp = None

            # --- SDK generation attempt ---
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
                    resp = None
                    debug_steps.append({'stage': 'sdk.error', 'error': str(e2)})

            # --- REST fallback if SDK fails ---
            if resp is None:
                # Fetch ephemeral token
                token_url = 'https://generativelanguage.googleapis.com/v1beta/ephemeralTokens'
                token_resp = requests.post(
                    token_url,
                    headers={'Authorization': f'Bearer {google_key}'},
                    timeout=15
                )
                ephemeral_token = ''
                if token_resp.status_code // 100 == 2:
                    ephemeral_token = token_resp.json().get('token', '')
                    debug_steps.append({'stage': 'ephemeral_token', 'token_present': bool(ephemeral_token)})
                else:
                    debug_steps.append({'stage': 'ephemeral_token_error', 'status': token_resp.status_code})
                    return Response({'detail': 'failed to fetch ephemeral token', 'debug': debug_steps}, status=502)

                # Use ephemeral token to call REST endpoint
                url = 'https://generativelanguage.googleapis.com/v1beta/images:generate'
                headers = {'Authorization': f'Bearer {ephemeral_token}', 'Content-Type': 'application/json'}
                payload = {
                    'model': f'models/{primary_model}',
                    'prompt': {'text': prompt},
                    'config': {
                        'numberOfImages': 1,
                        'aspectRatio': '1:1',
                        'sampleImageSize': '1K',
                        'personGeneration': 'dont_allow',
                    }
                }
                rr = requests.post(url, headers=headers, json=payload, timeout=60)
                debug_steps.append({'stage': 'rest.images:generate', 'status': rr.status_code, 'len': len(rr.text or '')})
                if rr.status_code // 100 != 2:
                    return Response({
                        'detail': f'rest API error {rr.status_code}',
                        'body': rr.text or '',
                        'debug': debug_steps
                    }, status=502)

                data = rr.json() if rr.content else {}
                b64 = ''
                try:
                    imgs = data.get('generatedImages') or []
                    if imgs:
                        img0 = imgs[0].get('image') or {}
                        b64 = (img0.get('imageBytes') or '').strip()
                except Exception:
                    b64 = ''
                if not b64:
                    return Response({'detail': 'no image in REST response', 'body': data, 'debug': debug_steps}, status=502)
                return Response({'image_b64': b64, 'debug': debug_steps if want_debug else None})

            # --- SDK response parsing ---
            b64 = ''
            try:
                gi = getattr(resp, 'generated_images', None) or getattr(resp, 'generatedImages', None) or []
                if gi:
                    img0 = gi[0]
                    image = getattr(img0, 'image', None) or {}
                    b64 = getattr(image, 'image_bytes', None) or getattr(image, 'imageBytes', None) or ''
                    if isinstance(b64, bytes):
                        b64 = base64.b64encode(b64).decode('utf-8')
            except Exception:
                b64 = ''

            if not b64:
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

            return Response({'image_b64': b64, 'debug': debug_steps if want_debug else None})

        except Exception as e:
            debug_steps.append({'stage': 'sdk.exception', 'error': str(e)})
            return Response({'detail': f'gemini request failed: {e}', 'debug': debug_steps}, status=502)


class LessonGetView(APIView):
    def get(self, request, lesson_id):
        try:
            lesson = Lesson.objects.get(id=lesson_id)
            serializer = LessonSerializer(lesson)
            return Response(serializer.data)
        except Lesson.DoesNotExist:
            return Response({"error": "Lesson not found"}, status=status.HTTP_404_NOT_FOUND)
        

class LessonsListView(generics.ListAPIView):
    pagination_class = None
    serializer_class = LessonSerializer

    def get_serializer_class(self):
        # If authenticated, include per-lesson progress state.
        if getattr(self.request, 'user', None) is not None and self.request.user.is_authenticated:
            return LessonWithProgressSerializer
        return LessonSerializer

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        user = getattr(self.request, 'user', None)
        if user is None or not user.is_authenticated:
            return ctx

        # Build a progress map for the lessons in the current queryset.
        lessons = list(self.get_queryset().only('id', 'title'))
        lesson_ids = [l.id for l in lessons]
        title_to_id = { (l.title or '').strip().lower(): l.id for l in lessons }

        progress_by_lesson_id = {lid: 'not_started' for lid in lesson_ids}

        # 1) Persisted per-user per-lesson progress.
        progress_rows = (
            LessonProgress.objects
            .filter(user=user, lesson_id__in=lesson_ids)
            .values('lesson_id', 'state')
        )
        for row in progress_rows:
            lid = row.get('lesson_id')
            state = row.get('state')
            if lid and state:
                progress_by_lesson_id[lid] = state

        # 2) Back-compat fallback: infer progress from sessions if no persisted
        # progress exists yet.
        linked = (
            LessonSession.objects
            .filter(user=user, lesson_id__in=lesson_ids)
            .values('lesson_id', 'is_completed')
        )
        for row in linked:
            lid = row.get('lesson_id')
            if not lid:
                continue
            if progress_by_lesson_id.get(lid) != 'not_started':
                continue
            progress_by_lesson_id[lid] = 'completed' if row.get('is_completed') else 'in_progress'

        unlinked = (
            LessonSession.objects
            .filter(user=user, lesson__isnull=True)
            .values('topic', 'is_completed')
        )
        for row in unlinked:
            topic = (row.get('topic') or '').strip().lower()
            lid = title_to_id.get(topic)
            if not lid:
                continue
            if progress_by_lesson_id.get(lid) != 'not_started':
                continue
            progress_by_lesson_id[lid] = 'completed' if row.get('is_completed') else 'in_progress'

        ctx['progress_by_lesson_id'] = progress_by_lesson_id
        return ctx

    def get_queryset(self):
        qs = Lesson.objects.all().order_by('title')

        subject = (self.request.query_params.get('subject') or '').strip().lower()
        difficulty = (self.request.query_params.get('difficulty') or '').strip().lower()

        if subject:
            valid_subjects = {k for k, _ in Lesson.SUBJECT_CHOICES}
            if subject not in valid_subjects:
                raise ValidationError({
                    'subject': [
                        f"Invalid subject '{subject}'. Valid: {sorted(valid_subjects)}"
                    ]
                })
            qs = qs.filter(subject=subject)

        if difficulty:
            valid_difficulties = {k for k, _ in Lesson.DIFFICULTY_CHOICES}
            if difficulty not in valid_difficulties:
                raise ValidationError({
                    'difficulty': [
                        f"Invalid difficulty '{difficulty}'. Valid: {sorted(valid_difficulties)}"
                    ]
                })
            qs = qs.filter(difficulty=difficulty)

        return qs


class LessonHistoryView(APIView):
    """Return the authenticated user's lesson sessions with timeline metadata.

    Only sessions that have a valid timeline (with duration > 0 and at least
    one segment) are returned. Results are deduplicated by topic — only the
    most recent valid session per topic is shown. Invalid sessions (no
    timeline or zero duration) are deleted from the database automatically.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        from timeline_generator.models import Timeline

        sessions = LessonSession.objects.filter(
            user=request.user,
        ).order_by('-created_at')

        # Collect valid sessions and delete invalid ones
        valid = []          # (session, timeline)
        invalid_ids = []    # session IDs to purge

        for s in sessions:
            tl = s.timelines.order_by('-created_at').first()
            if tl is None or (tl.total_duration or 0) <= 0 or tl.segment_records.count() == 0:
                invalid_ids.append(s.id)
            else:
                valid.append((s, tl))

        # Purge invalid sessions from the database
        if invalid_ids:
            LessonSession.objects.filter(id__in=invalid_ids).delete()

        # Deduplicate: keep only the most recent session per topic
        seen_topics = set()
        results = []
        for s, tl in valid:
            topic_key = s.topic.strip().lower()
            if topic_key in seen_topics:
                continue
            seen_topics.add(topic_key)
            results.append({
                'id': s.id,
                'topic': s.topic,
                'is_completed': s.is_completed,
                'created_at': s.created_at.isoformat(),
                'timeline_id': tl.id,
                'total_duration': tl.total_duration,
                'segment_count': tl.segment_records.count(),
                'resume_segment_index': s.resume_segment_index,
                'resume_playback_time': s.resume_playback_time,
            })

        return Response(results)


class SaveProgressView(APIView):
    """Persist the current playback position so the user can resume later."""
    permission_classes = [permissions.AllowAny]

    def post(self, request, session_id):
        # Try to find the session — for authenticated users, scope to their own.
        if request.user and request.user.is_authenticated:
            session = get_object_or_404(LessonSession, pk=session_id, user=request.user)
        else:
            session = get_object_or_404(LessonSession, pk=session_id)

        segment_index = request.data.get('segment_index')
        playback_time = request.data.get('playback_time')

        if segment_index is None or playback_time is None:
            return Response(
                {'error': 'segment_index and playback_time are required'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            segment_index = int(segment_index)
            playback_time = float(playback_time)
        except (ValueError, TypeError):
            return Response(
                {'error': 'segment_index must be int, playback_time must be float'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        session.resume_segment_index = segment_index
        session.resume_playback_time = playback_time
        session.save(update_fields=['resume_segment_index', 'resume_playback_time', 'updated_at'])

        return Response({
            'status': 'saved',
            'resume_segment_index': session.resume_segment_index,
            'resume_playback_time': session.resume_playback_time,
        })


class MarkLessonCompleteView(APIView):
    """Mark a lesson session as completed."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, session_id):
        session = get_object_or_404(LessonSession, pk=session_id, user=request.user)
        session.is_completed = True
        session.save(update_fields=['is_completed', 'updated_at'])

        lesson = session.lesson
        if lesson is None:
            # Back-compat: infer lesson by matching the topic to a lesson title.
            lesson = Lesson.objects.filter(title__iexact=(session.topic or '').strip()).first()

        if lesson is not None:
            _mark_lesson_completed(request.user, lesson)
        return Response({'status': 'completed'})
