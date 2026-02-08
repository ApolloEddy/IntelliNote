from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
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
    # 1. Look for existing records
    stmt = select(Document).where(
        Document.notebook_id == request.notebook_id,
        Document.file_hash == request.sha256
    )
    result = await db.execute(stmt)
    docs = result.scalars().all()

    for doc in docs:
        # Better decision: If record exists in DB, it's either READY or need cleanup.
        # Check physical index folder.
        idx_path = os.path.join(settings.VECTOR_STORE_DIR, doc.notebook_id)
        if doc.status == DocStatus.READY and not os.path.exists(idx_path):
            # Zombie! Cleanup.
            await db.delete(doc)
        elif doc.status == DocStatus.READY:
            # Truly active
            return FileUploadResponse(doc_id=doc.id, status="already_exists", message="Active")
        else:
            # Stale processing/failed, cleanup to allow retry
            await db.delete(doc)
    
    await db.commit()

    # 2. CAS Hit
    stmt_art = select(Artifact).where(Artifact.hash == request.sha256)
    res_art = await db.execute(stmt_art)
    artifact = res_art.scalar_one_or_none()

    if artifact:
        new_doc = Document(notebook_id=request.notebook_id, filename=request.filename,
                           file_hash=artifact.hash, status=DocStatus.PENDING)
        db.add(new_doc)
        await db.commit()
        await db.refresh(new_doc)
        ingest_document_task.delay(new_doc.id)
        return FileUploadResponse(doc_id=new_doc.id, status="processing", message="Re-indexing")
    
    return FileUploadResponse(doc_id="", status="upload_required", message="New")

@router.post("/upload", response_model=FileUploadResponse)
async def upload_file(notebook_id: str = Form(...), file: UploadFile = File(...), db: AsyncSession = Depends(get_db)):
    file_hash, size = storage_service.save_file(file.file)
    stmt_art = select(Artifact).where(Artifact.hash == file_hash)
    res_art = await db.execute(stmt_art)
    if not res_art.scalar_one_or_none():
        db.add(Artifact(hash=file_hash, size=size, mime_type=file.content_type, storage_path=storage_service.get_path(file_hash)))
        await db.flush()
    new_doc = Document(notebook_id=notebook_id, filename=file.filename or "file", file_hash=file_hash, status=DocStatus.PENDING)
    db.add(new_doc)
    await db.commit()
    await db.refresh(new_doc)
    ingest_document_task.delay(new_doc.id)
    return FileUploadResponse(doc_id=new_doc.id, status="processing", message="Accepted")

@router.get("/{doc_id}/status")
async def get_document_status(doc_id: str, db: AsyncSession = Depends(get_db)):
    stmt = select(Document).where(Document.id == doc_id)
    res = await db.execute(stmt)
    doc = res.scalar_one_or_none()
    if not doc: raise HTTPException(status_code=404)
    
    # Simple, fast status check. Granular cleanup happens in /check or manually.
    # To keep this high-performance for polling, we ONLY return DB status.
    # The /check endpoint and Startup Sync are the ones responsible for DB cleanup.
    return {"doc_id": doc.id, "status": doc.status, "filename": doc.filename}

@router.delete("/{doc_id}")
async def delete_document(
    doc_id: str,
    db: AsyncSession = Depends(get_db)
):
    from app.services.ingestion import ingestion_service
    
    stmt = select(Document).where(Document.id == doc_id)
    result = await db.execute(stmt)
    doc = result.scalar_one_or_none()
    
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    
    # 1. Remove from Vector Index
    await ingestion_service.delete_document(doc.notebook_id, doc.id)
    
    # 2. Remove from DB
    await db.delete(doc)
    await db.commit()
    
    return {"status": "success", "message": "Document removed from index and database."}