from sqlalchemy import Column, String, LargeBinary
from app.db.session import Base

class ChunkCache(Base):
    """
    Caches the embedding vector for a specific text hash.
    Optimization: Prevents re-calculating embeddings for the same text content across different files.
    """
    __tablename__ = "chunk_cache"

    # Hash of the text chunk content (normalized)
    text_hash = Column(String(64), primary_key=True, index=True)
    
    # The actual embedding vector stored as bytes (serialized list of floats)
    # This saves API costs and latency.
    embedding = Column(LargeBinary, nullable=False)
    
    # Optional: Model version to invalidate cache if we switch models
    model_name = Column(String, default="default")