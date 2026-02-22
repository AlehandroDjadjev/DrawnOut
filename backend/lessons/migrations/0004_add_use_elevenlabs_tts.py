# Generated migration for use_elevenlabs_tts

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('lessons', '0003_add_use_existing_images'),
    ]

    operations = [
        migrations.AddField(
            model_name='lessonsession',
            name='use_elevenlabs_tts',
            field=models.BooleanField(
                default=False,
                help_text='If True, use ElevenLabs TTS; else use Google Cloud TTS'
            ),
        ),
    ]
