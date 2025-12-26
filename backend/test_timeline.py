#!/usr/bin/env python
"""Quick test script for timeline generation"""
import os
import sys
import django

# Setup Django
sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

from timeline_generator.services import TimelineGeneratorService
from lessons.models import LessonSession

def test_timeline_generation():
    """Test timeline generation with a sample session"""
    print("🧪 Testing timeline generation...")
    
    # Get or create a test session
    session = LessonSession.objects.first()
    if not session:
        print("❌ No sessions found. Create one first with the Start Lesson button.")
        return
    
    print(f"✅ Using session {session.id}: {session.topic}")
    
    # Generate timeline
    generator = TimelineGeneratorService()
    
    print("⏳ Generating timeline (this may take 10-30 seconds)...")
    timeline = generator.generate_timeline(
        lesson_plan={'lesson_plan': session.lesson_plan},
        topic=session.topic,
        duration_target=30.0  # Shorter for testing
    )
    
    if not timeline:
        print("❌ Timeline generation failed!")
        return
    
    print(f"✅ Timeline generated successfully!")
    print(f"   Segments: {len(timeline['segments'])}")
    print(f"   Total duration: {timeline.get('total_estimated_duration', 0)}s")
    print()
    
    # Print segments
    for i, seg in enumerate(timeline['segments']):
        print(f"Segment {i+1}:")
        print(f"  Time: {seg['start_time']:.1f}s - {seg['end_time']:.1f}s")
        print(f"  Speech: {seg['speech_text'][:60]}...")
        print(f"  Actions: {len(seg['drawing_actions'])} drawing actions")
        print()
    
    print("🎉 Test complete!")
    print()
    print("To test audio synthesis, use the web app's green button.")

if __name__ == '__main__':
    test_timeline_generation()



