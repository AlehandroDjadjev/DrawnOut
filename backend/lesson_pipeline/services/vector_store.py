"""
Pinecone vector store service for image embeddings.
"""
import logging
from typing import List, Optional, Dict, Any
from pinecone import Pinecone, ServerlessSpec

from lesson_pipeline.config import config
from lesson_pipeline.types import ImageEmbeddingRecord

logger = logging.getLogger(__name__)


class PineconeVectorStore:
    """Service for storing and querying image embeddings in Pinecone"""
    
    def __init__(self):
        self.api_key = config.pinecone_api_key
        self.environment = config.pinecone_environment
        self.index_name = config.pinecone_index_name
        self.dimension = config.embedding_dimension
        
        self.client: Optional[Pinecone] = None
        self.index = None
        self._initialized = False
    
    def _ensure_initialized(self):
        """Lazy initialize Pinecone client and index"""
        if self._initialized:
            return
        
        if not self.api_key:
            logger.warning("Pinecone API key not configured")
            raise ValueError("PINECONE_API_KEY environment variable not set")
        
        try:
            logger.info(f"Initializing Pinecone client")
            self.client = Pinecone(api_key=self.api_key)
            
            # Create index if it doesn't exist
            existing_indexes = [idx.name for idx in self.client.list_indexes()]
            
            if self.index_name not in existing_indexes:
                logger.info(f"Creating Pinecone index: {self.index_name}")
                self.client.create_index(
                    name=self.index_name,
                    dimension=self.dimension,
                    metric='cosine',
                    spec=ServerlessSpec(
                        cloud='aws',
                        region=self.environment
                    )
                )
            
            # Connect to index
            self.index = self.client.Index(self.index_name)
            logger.info(f"Connected to Pinecone index: {self.index_name}")
            
            self._initialized = True
            
        except Exception as e:
            logger.error(f"Failed to initialize Pinecone: {e}")
            raise
    
    def upsert_images(self, records: List[ImageEmbeddingRecord]) -> None:
        """
        Upload/update image embeddings in Pinecone.
        
        Args:
            records: List of ImageEmbeddingRecord to upsert
        """
        self._ensure_initialized()
        
        if not records:
            logger.warning("No records to upsert")
            return
        
        try:
            # Convert records to Pinecone format
            vectors = []
            for record in records:
                # Filter out null/None values from metadata (Pinecone rejects them)
                clean_metadata = {
                    k: v for k, v in {
                        'image_url': record.image_url,
                        'topic_id': record.topic_id,
                        'original_prompt': record.original_prompt,
                        **record.metadata
                    }.items() if v is not None
                }
                
                vectors.append({
                    'id': record.id,
                    'values': record.vector,
                    'metadata': clean_metadata
                })
            
            # Upsert in batches
            batch_size = 100
            for i in range(0, len(vectors), batch_size):
                batch = vectors[i:i+batch_size]
                self.index.upsert(vectors=batch)
                logger.debug(f"Upserted batch of {len(batch)} vectors")
            
            logger.info(f"Successfully upserted {len(records)} image embeddings")
            
        except Exception as e:
            logger.error(f"Failed to upsert images: {e}")
            raise
    
    def query_images_by_text(
        self,
        text_embedding: List[float],
        topic_id: Optional[str] = None,
        top_k: int = 5
    ) -> List[ImageEmbeddingRecord]:
        """
        Query for similar images using text embedding.
        
        Args:
            text_embedding: Query vector
            topic_id: Optional topic ID to filter by
            top_k: Number of results to return
        
        Returns:
            List of matched ImageEmbeddingRecord
        """
        self._ensure_initialized()
        
        try:
            # Build filter
            filter_dict = {}
            if topic_id:
                filter_dict['topic_id'] = topic_id
            
            # Query
            results = self.index.query(
                vector=text_embedding,
                top_k=top_k,
                filter=filter_dict if filter_dict else None,
                include_metadata=True
            )
            
            # Convert to ImageEmbeddingRecord
            records = []
            for match in results.matches:
                metadata = match.metadata or {}
                record = ImageEmbeddingRecord(
                    id=match.id,
                    image_url=metadata.get('image_url', ''),
                    vector=[],  # Don't include full vector in response
                    topic_id=metadata.get('topic_id', ''),
                    original_prompt=metadata.get('original_prompt', ''),
                    metadata=metadata
                )
                records.append(record)
            
            logger.debug(f"Found {len(records)} matching images")
            return records
            
        except Exception as e:
            logger.error(f"Failed to query images: {e}")
            raise
    
    def delete_by_topic(self, topic_id: str) -> None:
        """
        Delete all vectors for a topic.
        
        Args:
            topic_id: Topic ID to delete
        """
        self._ensure_initialized()
        
        try:
            self.index.delete(filter={'topic_id': topic_id})
            logger.info(f"Deleted vectors for topic: {topic_id}")
        except Exception as e:
            logger.error(f"Failed to delete topic vectors: {e}")
            raise
    
    def get_stats(self) -> Dict[str, Any]:
        """Get index statistics"""
        self._ensure_initialized()
        
        try:
            stats = self.index.describe_index_stats()
            return {
                'total_vector_count': stats.total_vector_count,
                'dimension': stats.dimension,
                'index_fullness': stats.index_fullness,
            }
        except Exception as e:
            logger.error(f"Failed to get stats: {e}")
            return {}


# Global singleton instance
_vector_store: Optional[PineconeVectorStore] = None


def get_vector_store() -> PineconeVectorStore:
    """Get or create the global vector store instance"""
    global _vector_store
    if _vector_store is None:
        _vector_store = PineconeVectorStore()
    return _vector_store


# Convenience functions
def upsert_images(records: List[ImageEmbeddingRecord]) -> None:
    """Upload image embeddings to Pinecone"""
    get_vector_store().upsert_images(records)


def query_images_by_text(
    text_embedding: List[float],
    topic_id: Optional[str] = None,
    top_k: int = 5
) -> List[ImageEmbeddingRecord]:
    """Query for similar images"""
    return get_vector_store().query_images_by_text(text_embedding, topic_id, top_k)

