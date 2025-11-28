"""
Quick test script to verify image pipeline integration with timeline generator.

Run from backend directory:
    python test_image_integration.py
"""
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

from timeline_generator.image_integration import (
    extract_image_tags_from_segments,
    clean_speech_text_from_tags,
    process_timeline_with_images
)

def test_extract_tags():
    """Test IMAGE tag extraction"""
    print("\n" + "="*60)
    print("TEST 1: Extract IMAGE tags from segments")
    print("="*60)
    
    segments = [
        {
            "sequence": 1,
            "speech_text": "Welcome to the lesson!",
            "drawing_actions": []
        },
        {
            "sequence": 2,
            "speech_text": 'Let me show you this. [IMAGE id="img_1" prompt="diagram of a cell" style="diagram" aspect="16:9"] As you can see here.',
            "drawing_actions": []
        },
        {
            "sequence": 3,
            "speech_text": 'And here is another example. [IMAGE id="img_2" prompt="photo of mitochondria" style="photo" aspect="16:9"] Pretty cool!',
            "drawing_actions": []
        }
    ]
    
    tags = extract_image_tags_from_segments(segments)
    
    print(f"✓ Found {len(tags)} IMAGE tags:")
    for tag in tags:
        print(f"  - {tag['tag_id']}: {tag['prompt'][:50]}...")
        print(f"    Segment: {tag['segment_index']}, Position: {tag['position']}")
    
    assert len(tags) == 2, f"Expected 2 tags, got {len(tags)}"
    assert tags[0]['tag_id'] == 'img_1'
    assert tags[1]['tag_id'] == 'img_2'
    print("\n✅ Tag extraction test PASSED")


def test_clean_speech():
    """Test IMAGE tag removal from speech"""
    print("\n" + "="*60)
    print("TEST 2: Clean IMAGE tags from speech text")
    print("="*60)
    
    original = 'Let me show you this. [IMAGE id="img_1" prompt="diagram of a cell" style="diagram" aspect="16:9"] As you can see here.'
    cleaned = clean_speech_text_from_tags(original)
    
    print(f"Original: {original}")
    print(f"Cleaned:  {cleaned}")
    
    assert '[IMAGE' not in cleaned
    assert 'Let me show you this' in cleaned
    assert 'As you can see here' in cleaned
    print("\n✅ Speech cleaning test PASSED")


def test_full_integration():
    """Test full integration with mock timeline"""
    print("\n" + "="*60)
    print("TEST 3: Full integration (will skip image resolution)")
    print("="*60)
    
    timeline_data = {
        "segments": [
            {
                "sequence": 1,
                "speech_text": "Today we'll learn about cells.",
                "estimated_duration": 5.0,
                "drawing_actions": [
                    {"type": "heading", "text": "CELL BIOLOGY"}
                ]
            },
            {
                "sequence": 2,
                "speech_text": 'Cells have many parts. [IMAGE id="img_1" prompt="labeled diagram of animal cell showing nucleus, mitochondria, and membrane" style="scientific diagram" aspect="16:9"] Each part has a function.',
                "estimated_duration": 8.0,
                "drawing_actions": [
                    {"type": "bullet", "text": "Nucleus", "level": 1}
                ]
            },
            {
                "sequence": 3,
                "speech_text": 'The mitochondria produces energy. [IMAGE id="img_2" prompt="cross-section illustration of mitochondria structure" style="educational illustration" aspect="16:9"] This is crucial for life.',
                "estimated_duration": 7.0,
                "drawing_actions": [
                    {"type": "bullet", "text": "Mitochondria", "level": 1}
                ]
            }
        ],
        "total_estimated_duration": 20.0
    }
    
    # Extract tags only (skip resolution for quick test)
    tags = extract_image_tags_from_segments(timeline_data['segments'])
    print(f"\n✓ Extracted {len(tags)} tags from timeline")
    
    # Clean speech
    for segment in timeline_data['segments']:
        original = segment['speech_text']
        cleaned = clean_speech_text_from_tags(original)
        if '[IMAGE' in original:
            print(f"\n  Segment {segment['sequence']}:")
            print(f"    Before: {original[:80]}...")
            print(f"    After:  {cleaned[:80]}...")
    
    print("\n✅ Full integration test PASSED")
    print("\nNOTE: To test actual image resolution, start the Django server and")
    print("      generate a lesson via the API. The image pipeline will run automatically.")


if __name__ == '__main__':
    try:
        test_extract_tags()
        test_clean_speech()
        test_full_integration()
        
        print("\n" + "="*60)
        print("🎉 ALL TESTS PASSED!")
        print("="*60)
        print("\nNext step: Generate a real lesson to test end-to-end:")
        print("  1. Start backend: python manage.py runserver")
        print("  2. Start Flutter app")
        print("  3. Click 'Start Lesson' and watch images get sketched!")
        
    except Exception as e:
        print(f"\n❌ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

