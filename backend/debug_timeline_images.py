#!/usr/bin/env python
"""Debug script to check image URLs in timeline segments"""
import os
import sys

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')

import django
django.setup()

from timeline_generator.models import Timeline

def main():
    t = Timeline.objects.order_by('-created_at').first()
    if not t:
        print("No timeline found")
        return
    
    print(f"Timeline ID: {t.id}")
    print(f"Created: {t.created_at}")
    print(f"Total segments: {len(t.segments)}")
    print("=" * 60)
    
    sketch_images_found = 0
    sketch_images_with_url = 0
    
    for i, seg in enumerate(t.segments):
        actions = seg.get('drawing_actions', [])
        for act in actions:
            if act.get('type') == 'sketch_image':
                sketch_images_found += 1
                image_url = act.get('image_url')
                metadata = act.get('metadata', {})
                
                print(f"\n--- Segment {i+1} sketch_image ---")
                print(f"  image_url: {repr(image_url)}")
                print(f"  metadata.id: {metadata.get('id')}")
                print(f"  metadata.url: {metadata.get('url')}")
                print(f"  metadata.image_url: {metadata.get('image_url')}")
                print(f"  metadata.prompt: {metadata.get('prompt', '')[:50]}...")
                print(f"  metadata.source: {metadata.get('source')}")
                
                if image_url:
                    sketch_images_with_url += 1
    
    print("\n" + "=" * 60)
    print(f"Summary: {sketch_images_found} sketch_image actions found")
    print(f"         {sketch_images_with_url} have image_url populated")
    print(f"         {sketch_images_found - sketch_images_with_url} are MISSING URLs")
    
    if sketch_images_found > 0 and sketch_images_with_url == 0:
        print("\n[WARNING] ALL sketch_images are missing URLs!")
        print("    This is likely due to DuckDuckGo rate limiting.")
        print("    Check server logs for '403 Ratelimit' errors.")
        print("    Regenerate the timeline to apply placeholder fallbacks.")

if __name__ == '__main__':
    main()

