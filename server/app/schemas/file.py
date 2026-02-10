from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class FileCheckRequest(BaseModel):
    sha256: str
    notebook_id: str
    filename: str

class FileUploadResponse(BaseModel):
    doc_id: str
    status: str
    message: str

class DocumentRead(BaseModel):
    id: str
    filename: str
    emoji: str
    status: str
    created_at: datetime
    
    class Config:
        from_attributes = True
