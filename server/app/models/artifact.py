from sqlalchemy import Column, String, Integer, DateTime
from sqlalchemy.sql import func
from app.db.session import Base

class Artifact(Base):
    __tablename__ = "artifacts"

    # SHA256 Hash as Primary Key (Content Addressable)
    hash = Column(String(64), primary_key=True, index=True)
    size = Column(Integer, nullable=False)
    mime_type = Column(String, nullable=True)
    storage_path = Column(String, nullable=False) # e.g., "ab/cd/abcdef..."
    created_at = Column(DateTime(timezone=True), server_default=func.now())
