from sqlalchemy import Column, String, LargeBinary, PrimaryKeyConstraint
from app.db.session import Base

class ChunkCache(Base):
    """
    Caches the embedding vector for a specific text hash.
    Optimization: Prevents re-calculating embeddings for the same text content across different files.
    """
    __tablename__ = "chunk_cache"
    __table_args__ = (
        PrimaryKeyConstraint("text_hash", "model_name", name="pk_chunk_cache_text_model"),
    )

    # Hash of the text chunk content (normalized)
    text_hash = Column(String(64), nullable=False, index=True)
    
    # Model name/version is part of cache identity to avoid cross-model contamination.
    model_name = Column(String, nullable=False, default="default")
    
    # The actual embedding vector stored as bytes (serialized list of floats)
    # This saves API costs and latency.
    embedding = Column(LargeBinary, nullable=False)
