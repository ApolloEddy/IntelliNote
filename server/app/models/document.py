import uuid
from sqlalchemy import Column, String, ForeignKey, DateTime, Enum, UniqueConstraint
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum

from app.db.session import Base

class DocStatus(str, enum.Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    READY = "ready"
    FAILED = "failed"


DOC_STATUS_ENUM = Enum(
    DocStatus,
    name="doc_status_enum",
    native_enum=False,
    values_callable=lambda x: [e.value for e in x],
    validate_strings=True,
)

class Document(Base):
    __tablename__ = "documents"
    __table_args__ = (
        UniqueConstraint("notebook_id", "file_hash", name="uq_documents_notebook_file_hash"),
    )

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    notebook_id = Column(String, index=True, nullable=False)
    
    # User's filename for this instance
    filename = Column(String, nullable=False)
    
    # Reference to physical file (Artifact)
    file_hash = Column(String(64), ForeignKey("artifacts.hash"), nullable=False)
    
    emoji = Column(String, default="📄")
    status = Column(DOC_STATUS_ENUM, default=DocStatus.PENDING, nullable=False)
    error_msg = Column(String, nullable=True)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    artifact = relationship("Artifact")
