#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Quick test script to verify the image integration pipeline.
Run: python test_image_pipeline.py
"""

import os
import sys
import django

# Fix Unicode output on Windows
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

# Setup Django
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

from timeline_generator.image_integration import (
    extract_image_tags_from_segments,
    process_timeline_with_images
)

# Test data with IMAGE tags
test_timeline = {
    "segments": [
        {
            "sequence": 1,
            "speech_text": "Welcome to the lesson!",
            "estimated_duration": 5.0,
            "drawing_actions": []
        },
        {
            "sequence": 2,
            "speech_text": 'Today we will learn about DNA. [IMAGE id="img_1" prompt="detailed diagram of DNA double helix structure" style="diagram" aspect="16:9"] This is the building block of life.',
            "estimated_duration": 8.0,
            "drawing_actions": []
        },
        {
            "sequence": 3,
            "speech_text": "DNA has many applications.",
            "estimated_duration": 4.0,
            "drawing_actions": []
        }
    ]
}

print("=" * 60)
print("TEST 1: Extract IMAGE tags from segments")
print("=" * 60)

image_tags = extract_image_tags_from_segments(test_timeline['segments'])
print(f"\n✅ Extracted {len(image_tags)} IMAGE tags:")
for tag in image_tags:
    print(f"  - {tag['tag_id']}: {tag['prompt'][:50]}...")
    print(f"    Segment: {tag['segment_index']}, Position: {tag['position']}")

print("\n" + "=" * 60)
print("TEST 2: Process full timeline with images")
print("=" * 60)

try:
    result = process_timeline_with_images(
        timeline_data=test_timeline,
        topic="DNA Structure",
        subject="Biology"
    )
    
    print(f"\n✅ Processing complete!")
    print(f"   Image count: {result.get('image_count', 0)}")
    
    # Check if sketch_image actions were added
    for seg in result['segments']:
        actions = seg.get('drawing_actions', [])
        image_actions = [a for a in actions if a.get('type') == 'sketch_image']
        if image_actions:
            print(f"\n   Segment {seg['sequence']} has {len(image_actions)} image action(s):")
            for action in image_actions:
                print(f"     - URL: {action.get('image_url', 'N/A')[:80]}...")
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()

print("\n" + "=" * 60)

