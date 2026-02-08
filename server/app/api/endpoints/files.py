from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
import os

from app.db.session import get_db
from app.models.artifact import Artifact
from app.models.document import Document, DocStatus
from app.schemas.file import FileUploadResponse, FileCheckRequest
from app.services.storage import storage_service
from app.worker.tasks import ingest_document_task
from app.core.config import settings

router = APIRouter()

@router.post("/check", response_model=FileUploadResponse)
async def check_file_exists(
    request: FileCheckRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Highly robust check that cleans up its own stale records.
    """
    # 1. Look for existing records for this hash in this notebook
    stmt = select(Document).where(
        Document.notebook_id == request.notebook_id,
        Document.file_hash == request.sha256
    )
    result = await db.execute(stmt)
    docs = result.scalars().all()

    for doc in docs:
        # Check if the record is actually healthy
        is_healthy = False
        if doc.status == DocStatus.READY:
            idx_path = os.path.join(settings.VECTOR_STORE_DIR, doc.notebook_id)
            if os.path.exists(idx_path):
                is_healthy = True
        
        if is_healthy:
            # Found a truly ready and indexed file
            return FileUploadResponse(
                doc_id=doc.id,
                status="already_exists",
                message="File already active in notebook."
            )
        else:
            # This is a zombie record (failed, pending, or index deleted).
            # SILENTLY DELETE IT from DB to allow a fresh start.
            print(f"[CLEANUP] Removing stale record {doc.id} for hash {doc.file_hash[:8]}")
            await db.delete(doc)
    
    await db.commit()

    # 2. Check if file exists in CAS (any notebook) for instant hit
    stmt_art = select(Artifact).where(Artifact.hash == request.sha256)
    res_art = await db.execute(stmt_art)
    artifact = res_art.scalar_one_or_none()

    if artifact:
        new_doc = Document(
            notebook_id=request.notebook_id,
            filename=request.filename,
            file_hash=artifact.hash,
            status=DocStatus.PENDING
        )
        db.add(new_doc)
        await db.commit()
        await db.refresh(new_doc)
        ingest_document_task.delay(new_doc.id)
        return FileUploadResponse(doc_id=new_doc.id, status="processing", message="CAS Hit")
    
    return FileUploadResponse(doc_id="", status="upload_required", message="New file")

@router.post("/upload", response_model=FileUploadResponse)
async def upload_file(
    notebook_id: str = Form(...),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db)
):
    file_hash, size = storage_service.save_file(file.file)
    # Deduplicate artifact record
    stmt_art = select(Artifact).where(Artifact.hash == file_hash)
    res_art = await db.execute(stmt_art)
    if not res_art.scalar_one_or_none():
        db.add(Artifact(hash=file_hash, size=size, mime_type=file.content_type, 
                        storage_path=storage_service.get_path(file_hash)))
        await db.flush()

    new_doc = Document(notebook_id=notebook_id, filename=file.filename or "file",
                        file_hash=file_hash, status=DocStatus.PENDING)
    db.add(new_doc)
    await db.commit()
    await db.refresh(new_doc)
    ingest_document_task.delay(new_doc.id)
    return FileUploadResponse(doc_id=new_doc.id, status="processing", message="Uploaded")

@router.get("/{doc_id}/status")
async def get_document_status(doc_id: str, db: AsyncSession = Depends(get_db)):
    stmt = select(Document).where(Document.id == doc_id)
    res = await db.execute(stmt)
    doc = res.scalar_one_or_none()
    if not doc: raise HTTPException(status_code=404)
    
    # Quick health check for Ready files
    if doc.status == DocStatus.READY:
        if not os.path.exists(os.path.join(settings.VECTOR_STORE_DIR, doc.notebook_id)):
            raise HTTPException(status_code=404, detail="Stale index")
            
    return {"doc_id": doc.id, "status": doc.status, "filename": doc.filename}