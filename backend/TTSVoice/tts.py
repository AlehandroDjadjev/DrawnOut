from django.shortcuts import render
from django.http import JsonResponse, HttpResponse
from google.cloud import texttospeech
import base64

def tts_demo(request):
    """Simple TTS demo page"""
    if request.method == 'POST':
        client = texttospeech.TextToSpeechClient()
        
        # Get parameters from POST
        text = request.POST.get('text', 'Hello')
        voice_name = request.POST.get('voice', 'en-US-Studio-O')
        speaking_rate = float(request.POST.get('rate', 1.0))
        pitch = float(request.POST.get('pitch', 3.0))
        
        # Configure TTS
        synthesis_input = texttospeech.SynthesisInput(text=text)
        voice = texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name=voice_name
        )
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3,
            speaking_rate=speaking_rate,
            pitch=pitch
        )
        
        # Generate speech
        try:
            response = client.synthesize_speech(
                input=synthesis_input,
                voice=voice,
                audio_config=audio_config
            )
            # Return audio as base64 for HTML audio player
            audio_b64 = base64.b64encode(response.audio_content).decode()
            return JsonResponse({
                'audio': f'data:audio/mp3;base64,{audio_b64}',
                'success': True
            })
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=400)
            
    # List available voices
    client = texttospeech.TextToSpeechClient()
    voices = client.list_voices().voices
    voice_list = [
        {'name': v.name, 'gender': v.ssml_gender.name} 
        for v in voices 
        if 'en-US' in v.language_codes
    ]
    
    return render(request, 'lessons/tts_demo.html', {
        'voices': voice_list
    })