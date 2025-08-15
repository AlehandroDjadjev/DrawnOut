from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import Lesson
import openai
import pinecone
import os

PINECONE_API_KEY = os.getenv("Pinecone-API-Key")
Pinecone = pinecone(api_key=PINECONE_API_KEY)
index = pinecone.Index("firstindex")

OPENAI_API_KEY = os.getenv("OpenAI-embedding-key")
openai.api_key = OPENAI_API_KEY

@receiver(post_save, sender=Lesson)
def add_or_update_lesson_in_vector_db(sender, instance, **kwargs):
    from openai import OpenAI

    client = OpenAI(api_key=openai.api_key)
    
    text_to_embed = f"{instance.title}\n\n{instance.plan}"
    
    response = client.embeddings.create(
        model="text-embedding-3-large",
        input=text_to_embed
    )
    
    vector = response.data[0].embedding
    
    index.upsert(
        vectors=[
            {
                "id": str(instance.id),
                "values": vector,
                "metadata": {
                    "title": instance.title,
                    "plan": instance.plan,
                    "thumbnail": instance.thumbnail.url if instance.thumbnail else None
                }
            }
        ]
    )
