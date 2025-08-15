import os
import pinecone
from openai import OpenAI

OPENAI_API_KEY = os.getenv("OpenAI-embedding-key")
PINECONE_API_KEY = os.getenv("Pinecone-API-Key")

def embed_text(text):
    client = OpenAI(api_key=OPENAI_API_KEY)
    response = client.embeddings.create(
        input=text,
        model="text-embedding-3-large"
    )
    return response.data[0].embedding

def retrieve_from_vector_db(query_text, top_k):
    pinecone.init(api_key=PINECONE_API_KEY)
    
    query_vector = embed_text(query_text)
    index = pinecone.Index("firstindex")

    results = index.query(
        vector=query_vector,
        top_k=top_k,
        include_metadata=True
    )

    return [
        {
            "id": match["id"],
            "score": match["score"],
            "title": match["metadata"].get("title"),
            "plan": match["metadata"].get("plan"),
            "thumbnail": match["metadata"].get("thumbnail")
        }
        for match in results["matches"]
    ]


