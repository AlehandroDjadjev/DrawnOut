from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status, permissions
from django.shortcuts import get_object_or_404

from .models import LessonSession, Utterance
from .serializers import LessonSessionSerializer, UtteranceSerializer
from .services import TutorEngine


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

        # Accept either text question or audio file for STT
        question_text = request.data.get('question')
        if not question_text and 'audio' in request.FILES:
            audio_file = request.FILES['audio']
            question_text = engine.transcribe_audio(audio_file.read(), audio_file.name)

        if not question_text:
            return Response({"detail": "Question text or audio is required."}, status=status.HTTP_400_BAD_REQUEST)

        step_text = session.lesson_plan[session.current_step_index]
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


class SessionDetailView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request, session_id: int):
        session = get_object_or_404(LessonSession, pk=session_id)
        return Response(LessonSessionSerializer(session).data)


