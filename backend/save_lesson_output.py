"""
Save a complete lesson output to a folder.
Downloads: script, images (with tags), and audio.

Usage:
    python save_lesson_output.py "Photosynthesis" --subject Biology
"""
import os
import sys
import json
import argparse
import requests
from pathlib import Path
from datetime import datetime
import hashlib
import re

# Fix Windows console encoding for Unicode
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# Add backend to path for imports
sys.path.insert(0, str(Path(__file__).parent))

# Load environment variables
from dotenv import load_dotenv
load_dotenv()


def slugify(text: str, max_length: int = 50) -> str:
    """Convert text to a safe filename slug."""
    # Remove special characters, keep alphanumeric and spaces
    text = re.sub(r'[^\w\s-]', '', text.lower())
    # Replace spaces with underscores
    text = re.sub(r'[\s]+', '_', text.strip())
    return text[:max_length]


def download_image(url: str, dest_path: Path, timeout: int = 30) -> bool:
    """Download an image from URL to destination path."""
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 DrawnOutBot/1.0'
    }
    try:
        response = requests.get(url, headers=headers, timeout=timeout, stream=True)
        response.raise_for_status()
        
        with open(dest_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        return True
    except Exception as e:
        print(f"  ❌ Failed to download {url[:60]}...: {e}")
        return False


def generate_audio(text: str, output_path: Path, use_elevenlabs: bool = False) -> bool:
    """Generate audio using Google Cloud TTS or ElevenLabs API.
    use_elevenlabs: If True, use ElevenLabs (Netanyahu + voice_id env vars); else Google Cloud.
    """
    if use_elevenlabs:
        return _generate_audio_elevenlabs(text, output_path)
    return _generate_audio_google(text, output_path)


def _generate_audio_google(text: str, output_path: Path) -> bool:
    """Generate audio using Google Cloud TTS."""
    try:
        from google.cloud import texttospeech

        client = texttospeech.TextToSpeechClient()

        max_chars = 4500
        chunks = []
        current_chunk = ""

        sentences = text.replace('\n', ' ').split('. ')
        for sentence in sentences:
            if len(current_chunk) + len(sentence) < max_chars:
                current_chunk += sentence + '. '
            else:
                if current_chunk:
                    chunks.append(current_chunk.strip())
                current_chunk = sentence + '. '
        if current_chunk:
            chunks.append(current_chunk.strip())

        all_audio = b''
        for i, chunk in enumerate(chunks):
            print(f"  🎙️ Generating audio chunk {i+1}/{len(chunks)}...")
            synthesis_input = texttospeech.SynthesisInput(text=chunk)
            voice = texttospeech.VoiceSelectionParams(
                language_code="en-US",
                name="en-US-Studio-O",
            )
            audio_config = texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.MP3,
                speaking_rate=1.0,
                pitch=0.0,
            )
            response = client.synthesize_speech(
                input=synthesis_input,
                voice=voice,
                audio_config=audio_config,
            )
            all_audio += response.audio_content

        with open(output_path, 'wb') as f:
            f.write(all_audio)
        return True

    except ImportError:
        print("  ⚠️ Google Cloud TTS not available. Skipping audio generation.")
        return False
    except Exception as e:
        print(f"  ❌ Failed to generate audio: {e}")
        return False


def _generate_audio_elevenlabs(text: str, output_path: Path) -> bool:
    """Generate audio using ElevenLabs API (Netanyahu + voice_id env vars)."""
    api_key = os.getenv('Netanyahu', '')
    voice_id = os.getenv('voice_id', '')
    if not api_key or not voice_id:
        print("  ⚠️ ElevenLabs not configured: set Netanyahu and voice_id env vars.")
        return False

    try:
        from elevenlabs.client import ElevenLabs

        client = ElevenLabs(api_key=api_key)
        max_chars = 4500
        chunks = []
        current_chunk = ""

        sentences = text.replace('\n', ' ').split('. ')
        for sentence in sentences:
            if len(current_chunk) + len(sentence) < max_chars:
                current_chunk += sentence + '. '
            else:
                if current_chunk:
                    chunks.append(current_chunk.strip())
                current_chunk = sentence + '. '
        if current_chunk:
            chunks.append(current_chunk.strip())

        all_audio = b''
        for i, chunk in enumerate(chunks):
            print(f"  🎙️ Generating audio chunk {i+1}/{len(chunks)}...")
            audio_iter = client.text_to_speech.convert(
                text=chunk,
                voice_id=voice_id,
                model_id="eleven_multilingual_v2",
                output_format="mp3_44100_128",
            )
            audio_content = b"".join(audio_iter) if hasattr(audio_iter, "__iter__") else bytes(audio_iter)
            all_audio += audio_content

        with open(output_path, 'wb') as f:
            f.write(all_audio)
        return True

    except ImportError:
        print("  ⚠️ ElevenLabs not available. pip install elevenlabs")
        return False
    except Exception as e:
        print(f"  ❌ Failed to generate audio: {e}")
        return False


def extract_speech_text(content: str) -> str:
    """Extract speakable text from lesson content."""
    # Remove markdown image tags
    text = re.sub(r'!\[.*?\]\(.*?\)\{.*?\}', '', content)
    text = re.sub(r'!\[.*?\]\(.*?\)', '', content)
    
    # Remove markdown headers but keep text
    text = re.sub(r'^#+\s*', '', text, flags=re.MULTILINE)
    
    # Remove extra whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = text.strip()
    
    return text


def save_lesson(prompt: str, subject: str = "General", duration: float = 60.0,
                output_dir: str = None, api_url: str = "http://127.0.0.1:8000",
                tts: str = "google"):
    """
    Call the lesson API and save all outputs to a folder.
    """
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    folder_name = f"lesson_{slugify(prompt)}_{timestamp}"
    
    if output_dir:
        output_path = Path(output_dir) / folder_name
    else:
        output_path = Path(__file__).parent / "lesson_outputs" / folder_name
    
    output_path.mkdir(parents=True, exist_ok=True)
    images_path = output_path / "images"
    images_path.mkdir(exist_ok=True)
    
    print("=" * 60)
    print(f"📚 Generating Lesson: {prompt}")
    print(f"📁 Output folder: {output_path}")
    print("=" * 60)
    
    # 1. Call the API
    print("\n🔄 Calling lesson generation API...")
    try:
        response = requests.post(
            f"{api_url}/api/lesson-pipeline/generate/",
            json={
                "prompt": prompt,
                "subject": subject,
                "duration_target": duration
            },
            timeout=300  # 5 minutes
        )
        response.raise_for_status()
        lesson_data = response.json()
        print(f"  ✅ API responded with status {response.status_code}")
    except Exception as e:
        print(f"  ❌ API call failed: {e}")
        return None
    
    # 2. Save raw API response
    print("\n💾 Saving API response...")
    with open(output_path / "lesson_data.json", 'w', encoding='utf-8') as f:
        json.dump(lesson_data, f, indent=2, ensure_ascii=False)
    print(f"  ✅ Saved lesson_data.json")
    
    # 3. Save the script/content as markdown
    print("\n📝 Saving lesson script...")
    content = lesson_data.get('content', '')
    with open(output_path / "script.md", 'w', encoding='utf-8') as f:
        f.write(f"# {prompt}\n\n")
        f.write(f"**Subject:** {subject}\n")
        f.write(f"**Generated:** {datetime.now().isoformat()}\n\n")
        f.write("---\n\n")
        f.write(content)
    print(f"  ✅ Saved script.md")
    
    # 4. Download images and create manifest
    print("\n🖼️ Downloading images...")
    images = lesson_data.get('images', [])
    image_manifest = []
    
    for i, img in enumerate(images):
        tag = img.get('tag', {})
        tag_id = tag.get('id', f'img_{i}')
        tag_prompt = tag.get('prompt', '')
        tag_query = tag.get('query', '')
        tag_style = tag.get('style', 'photo')
        
        base_url = img.get('base_image_url', '')
        final_url = img.get('final_image_url', '') or base_url
        vector_id = img.get('vector_id')
        
        # Create filename from tag
        filename = f"{tag_id}_{slugify(tag_query or tag_prompt)}"
        
        # Determine extension from URL
        ext = '.jpg'
        if base_url:
            url_lower = base_url.lower()
            if '.png' in url_lower:
                ext = '.png'
            elif '.gif' in url_lower:
                ext = '.gif'
            elif '.svg' in url_lower:
                ext = '.svg'
            elif '.webp' in url_lower:
                ext = '.webp'
        
        image_filename = f"{filename}{ext}"
        image_path = images_path / image_filename
        
        # Download image
        downloaded = False
        if base_url:
            print(f"  [{i+1}/{len(images)}] Downloading {tag_id}: {base_url[:50]}...")
            downloaded = download_image(base_url, image_path)
            if downloaded:
                print(f"      ✅ Saved as {image_filename}")
        else:
            print(f"  [{i+1}/{len(images)}] {tag_id}: No URL available")
        
        # Add to manifest
        image_manifest.append({
            "index": i,
            "tag_id": tag_id,
            "prompt": tag_prompt,
            "query": tag_query,
            "style": tag_style,
            "aspect_ratio": tag.get('aspect_ratio'),
            "source_url": base_url,
            "final_url": final_url,
            "vector_id": vector_id,
            "local_file": image_filename if downloaded else None,
            "downloaded": downloaded
        })
    
    # Save image manifest
    with open(output_path / "images_manifest.json", 'w', encoding='utf-8') as f:
        json.dump(image_manifest, f, indent=2, ensure_ascii=False)
    print(f"\n  ✅ Saved images_manifest.json ({len([m for m in image_manifest if m['downloaded']])} images downloaded)")
    
    # 5. Generate audio
    print("\n🎙️ Generating audio narration...")
    speech_text = extract_speech_text(content)
    
    # Save text version
    with open(output_path / "narration.txt", 'w', encoding='utf-8') as f:
        f.write(speech_text)
    print(f"  ✅ Saved narration.txt ({len(speech_text)} characters)")
    
    # Try to generate audio (use --tts flag: google or elevenlabs)
    use_elevenlabs = tts == 'elevenlabs'
    audio_path = output_path / "narration.mp3"
    if generate_audio(speech_text, audio_path, use_elevenlabs=use_elevenlabs):
        print(f"  ✅ Saved narration.mp3")
    else:
        print(f"  ⚠️ Audio generation skipped (see above)")
    
    # 6. Create summary
    print("\n📊 Creating summary...")
    summary = {
        "prompt": prompt,
        "subject": subject,
        "duration_target": duration,
        "generated_at": datetime.now().isoformat(),
        "lesson_id": lesson_data.get('id'),
        "topic_id": lesson_data.get('topic_id'),
        "indexed_image_count": lesson_data.get('indexed_image_count', 0),
        "total_images": len(images),
        "downloaded_images": len([m for m in image_manifest if m['downloaded']]),
        "content_length": len(content),
        "files": {
            "script": "script.md",
            "data": "lesson_data.json",
            "images_manifest": "images_manifest.json",
            "narration_text": "narration.txt",
            "narration_audio": "narration.mp3" if audio_path.exists() else None,
            "images_folder": "images/"
        }
    }
    
    with open(output_path / "summary.json", 'w', encoding='utf-8') as f:
        json.dump(summary, f, indent=2)
    print(f"  ✅ Saved summary.json")
    
    # Final report
    print("\n" + "=" * 60)
    print("✅ LESSON SAVED SUCCESSFULLY!")
    print("=" * 60)
    print(f"📁 Location: {output_path}")
    print(f"📝 Script: script.md")
    print(f"🖼️ Images: {summary['downloaded_images']}/{summary['total_images']} downloaded")
    print(f"🎙️ Audio: {'narration.mp3' if audio_path.exists() else 'Not generated'}")
    print(f"📊 Indexed in Pinecone: {summary['indexed_image_count']} vectors")
    print("=" * 60)
    
    return output_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate and save a complete lesson")
    parser.add_argument("prompt", help="The lesson topic/prompt")
    parser.add_argument("--subject", "-s", default="General", help="Subject area (default: General)")
    parser.add_argument("--duration", "-d", type=float, default=60.0, help="Target duration in seconds (default: 60)")
    parser.add_argument("--output", "-o", help="Output directory (default: ./lesson_outputs/)")
    parser.add_argument("--api", default="http://127.0.0.1:8000", help="API base URL")
    parser.add_argument("--tts", choices=["google", "elevenlabs"], default="google",
                        help="TTS provider: google or elevenlabs (default: google)")

    args = parser.parse_args()

    save_lesson(
        prompt=args.prompt,
        subject=args.subject,
        duration=args.duration,
        output_dir=args.output,
        api_url=args.api,
        tts=args.tts,
    )

