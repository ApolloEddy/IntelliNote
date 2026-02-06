from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import get_db
from app.models.artifact import Artifact
from app.models.document import Document, DocStatus
from app.schemas.file import FileUploadResponse, FileCheckRequest
from app.services.storage import storage_service
from app.worker.tasks import ingest_document_task

router = APIRouter()

@router.post("/check", response_model=FileUploadResponse)
async def check_file_exists(
    request: FileCheckRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Check if file hash exists. 
    REVISED LOGIC: Even if file exists in CAS, we MUST trigger ingestion 
    to ensure it's added to the specific Notebook's vector index.
    But it will be fast because of Smart Embedding Cache.
    """
    # 1. Check Artifact
    stmt = select(Artifact).where(Artifact.hash == request.sha256)
    result = await db.execute(stmt)
    artifact = result.scalar_one_or_none()

    if artifact:
        # Hit! Create Document but set status to PENDING
        new_doc = Document(
            notebook_id=request.notebook_id,
            filename=request.filename,
            file_hash=artifact.hash,
            status=DocStatus.PENDING # Needs indexing
        )
        db.add(new_doc)
        await db.commit()
        await db.refresh(new_doc)
        
        # Trigger Task (Fast Path)
        ingest_document_task.delay(new_doc.id)
        
        return FileUploadResponse(
            doc_id=new_doc.id,
            status="processing", # Not instant_success anymore
            message="File found. Indexing for this notebook..."
        )
    
    return FileUploadResponse(
        doc_id="",
        status="upload_required",
        message="File not found on server."
    )

@router.post("/upload", response_model=FileUploadResponse)
async def upload_file(
    notebook_id: str = Form(...),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db)
):
    # 1. Save to CAS (Physical Storage)
    file_hash, size = storage_service.save_file(file.file)

    # 2. Register Artifact
    stmt = select(Artifact).where(Artifact.hash == file_hash)
    result = await db.execute(stmt)
    artifact = result.scalar_one_or_none()

    if not artifact:
        artifact = Artifact(
            hash=file_hash,
            size=size,
            mime_type=file.content_type,
            storage_path=storage_service.get_path(file_hash)
        )
        db.add(artifact)
        await db.flush() 

    # 3. Create Document
    new_doc = Document(
        notebook_id=notebook_id,
        filename=file.filename or "uploaded_file",
        file_hash=file_hash,
        status=DocStatus.PENDING
    )
    db.add(new_doc)
    await db.commit()
    await db.refresh(new_doc)

    # 4. Trigger Celery Task
    ingest_document_task.delay(new_doc.id)

    return FileUploadResponse(
        doc_id=new_doc.id,
        status="processing",
        message="Upload accepted. Processing in background."
    )

@router.get("/{doc_id}/status")
async def get_document_status(
    doc_id: str,
    db: AsyncSession = Depends(get_db)
):
    stmt = select(Document).where(Document.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
        
    return {
        "doc_id": doc.id,
        "status": doc.status,
        "filename": doc.filename,
        "updated_at": doc.updated_at
    }