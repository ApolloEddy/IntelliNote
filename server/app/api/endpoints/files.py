from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
import os
import json
from pathlib import Path

from app.db.session import get_db
from app.models.artifact import Artifact
from app.models.document import Document, DocStatus
from app.schemas.file import FileUploadResponse, FileCheckRequest
from app.services.storage import storage_service
from app.services.document_parser import SUPPORTED_DOCUMENT_EXTENSIONS
from app.services.pdf_preview import extract_pdf_page_preview
from app.worker.tasks import ingest_document_task
from app.core.config import settings

router = APIRouter()
SUPPORTED_UPLOAD_EXTENSIONS = SUPPORTED_DOCUMENT_EXTENSIONS


def _normalize_extension(filename: str | None) -> str:
    return Path((filename or "").strip()).suffix.lower()


def _ensure_supported_extension(filename: str | None, content_type: str | None = None) -> None:
    ext = _normalize_extension(filename)
    if not ext and (content_type or "").lower() == "application/pdf":
        ext = ".pdf"
    if ext in SUPPORTED_UPLOAD_EXTENSIONS:
        return
    allowed = "/".join(sorted(e[1:].upper() for e in SUPPORTED_UPLOAD_EXTENSIONS))
    raise HTTPException(status_code=400, detail=f"仅支持 {allowed} 文件类型")


def _classify_ingestion_error(error_msg: str | None) -> tuple[str, str]:
    msg = (error_msg or "").strip()
    low = msg.lower()
    if not msg:
        return "E_INGEST_FAILED", "处理失败"
    if "queue_unavailable" in low:
        return "E_QUEUE_UNAVAILABLE", "任务队列不可用"
    if "pymupdf is required" in low or "no module named 'fitz'" in low:
        return "E_PDF_DEPENDENCY", "PDF 解析依赖缺失（PyMuPDF）"
    if "no readable text extracted from pdf" in low:
        return "E_PDF_EMPTY", "PDF 未提取到可读文本"
    if "timeout" in low or "timed out" in low:
        return "E_UPSTREAM_TIMEOUT", "上游处理超时"
    return "E_INGEST_FAILED", "处理失败"


async def _enqueue_ingestion_or_503(doc: Document, db: AsyncSession, ok_message: str) -> FileUploadResponse:
    try:
        ingest_document_task.delay(doc.id)
        return FileUploadResponse(doc_id=doc.id, status="processing", message=ok_message)
    except Exception as exc:
        doc.status = DocStatus.FAILED
        doc.error_msg = f"QUEUE_UNAVAILABLE: {exc}"
        await db.commit()
        raise HTTPException(
            status_code=503,
            detail={
                "error": "任务队列不可用，请检查 Redis/Celery",
                "error_code": "E_QUEUE_UNAVAILABLE",
            },
        )


@router.post("/check", response_model=FileUploadResponse)
async def check_file_exists(
    request: FileCheckRequest,
    db: AsyncSession = Depends(get_db)
):
    _ensure_supported_extension(request.filename)

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
        try:
            await db.commit()
            await db.refresh(new_doc)
        except IntegrityError:
            await db.rollback()
            stmt_existing = select(Document).where(
                Document.notebook_id == request.notebook_id,
                Document.file_hash == request.sha256,
            )
            res_existing = await db.execute(stmt_existing)
            existing = res_existing.scalars().first()
            if existing:
                if existing.status == DocStatus.READY:
                    return FileUploadResponse(doc_id=existing.id, status="already_exists", message="Active")
                return FileUploadResponse(doc_id=existing.id, status="processing", message="Re-indexing")
            raise
        return await _enqueue_ingestion_or_503(new_doc, db, "Re-indexing")
    
    return FileUploadResponse(doc_id="", status="upload_required", message="New")

@router.post("/upload", response_model=FileUploadResponse)
async def upload_file(notebook_id: str = Form(...), file: UploadFile = File(...), db: AsyncSession = Depends(get_db)):
    _ensure_supported_extension(file.filename, file.content_type)

    file_hash, size = storage_service.save_file(file.file)

    stmt_doc = select(Document).where(
        Document.notebook_id == notebook_id,
        Document.file_hash == file_hash,
    )
    res_doc = await db.execute(stmt_doc)
    existing_doc = res_doc.scalars().first()
    if existing_doc:
        if existing_doc.status == DocStatus.READY:
            return FileUploadResponse(doc_id=existing_doc.id, status="already_exists", message="Active")
        return FileUploadResponse(doc_id=existing_doc.id, status="processing", message="Accepted")

    stmt_art = select(Artifact).where(Artifact.hash == file_hash)
    res_art = await db.execute(stmt_art)
    if not res_art.scalar_one_or_none():
        db.add(Artifact(hash=file_hash, size=size, mime_type=file.content_type, storage_path=storage_service.get_path(file_hash)))
        await db.flush()
    new_doc = Document(notebook_id=notebook_id, filename=file.filename or "file", file_hash=file_hash, status=DocStatus.PENDING)
    db.add(new_doc)
    try:
        await db.commit()
        await db.refresh(new_doc)
    except IntegrityError:
        await db.rollback()
        stmt_existing = select(Document).where(
            Document.notebook_id == notebook_id,
            Document.file_hash == file_hash,
        )
        res_existing = await db.execute(stmt_existing)
        existing = res_existing.scalars().first()
        if existing:
            if existing.status == DocStatus.READY:
                return FileUploadResponse(doc_id=existing.id, status="already_exists", message="Active")
            return FileUploadResponse(doc_id=existing.id, status="processing", message="Accepted")
        raise
    return await _enqueue_ingestion_or_503(new_doc, db, "Accepted")

@router.get("/{doc_id}/status")
async def get_document_status(doc_id: str, db: AsyncSession = Depends(get_db)):
    stmt = select(Document).where(Document.id == doc_id)
    res = await db.execute(stmt)
    doc = res.scalar_one_or_none()
    if not doc: raise HTTPException(status_code=404)
    
    progress = 0.0
    stage = "queued"
    message = "排队中"
    detail = None
    if doc.status == DocStatus.READY:
        progress = 1.0
        stage = "done"
        message = "处理完成"
    elif doc.status == DocStatus.FAILED:
        progress = 1.0
        stage = "failed"
        message = "处理失败"

    import redis.asyncio as redis
    from app.core.config import settings

    r = redis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        val = await r.get(f"prog:{doc_id}")
        if val:
            try:
                parsed = json.loads(val)
                if isinstance(parsed, dict):
                    progress = float(parsed.get("progress", progress))
                    stage = str(parsed.get("stage", stage))
                    message = str(parsed.get("message", message))
                    detail = parsed.get("detail")
                else:
                    progress = float(val)
            except (ValueError, TypeError, json.JSONDecodeError):
                progress = float(val)
    except Exception as exc:
        print(f"[files.status] redis progress read failed for {doc_id}: {exc}")
    finally:
        await r.close()

    response = {
        "doc_id": doc.id,
        "status": doc.status,
        "filename": doc.filename,
        "progress": progress,
        "stage": stage,
        "message": message,
    }
    if detail is not None:
        response["detail"] = detail
    if doc.status == DocStatus.FAILED and doc.error_msg:
        response["error"] = doc.error_msg
        code, hint = _classify_ingestion_error(doc.error_msg)
        response["error_code"] = code
        response["error_hint"] = hint
    return response


@router.get("/{doc_id}/page/{page_number}")
async def get_document_pdf_page_preview(
    doc_id: str,
    page_number: int,
    max_chars: int = 4000,
    db: AsyncSession = Depends(get_db),
):
    if page_number < 1:
        raise HTTPException(status_code=400, detail="page_number must be >= 1")

    stmt = select(Document).where(Document.id == doc_id)
    res = await db.execute(stmt)
    doc = res.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    if not (doc.filename or "").lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Only PDF sources support page preview")

    stmt_art = select(Artifact).where(Artifact.hash == doc.file_hash)
    res_art = await db.execute(stmt_art)
    artifact = res_art.scalar_one_or_none()
    if not artifact:
        raise HTTPException(status_code=404, detail="Physical artifact missing")

    try:
        file_path = storage_service.get_file(artifact.hash)
        preview = extract_pdf_page_preview(file_path, page_number=page_number, max_chars=max_chars)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Physical file missing")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    return {
        "doc_id": doc.id,
        "filename": doc.filename,
        **preview,
    }

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
    
    file_hash = doc.file_hash

    # 1. Remove from Vector Index
    await ingestion_service.delete_document(doc.notebook_id, doc.id)
    
    # 2. Remove from DB
    await db.delete(doc)
    await db.commit()

    # 3. Cleanup orphan artifact (CAS) when no document references it anymore.
    stmt_ref = select(Document.id).where(Document.file_hash == file_hash).limit(1)
    res_ref = await db.execute(stmt_ref)
    if res_ref.scalar_one_or_none() is None:
        stmt_art = select(Artifact).where(Artifact.hash == file_hash)
        res_art = await db.execute(stmt_art)
        artifact = res_art.scalar_one_or_none()
        if artifact:
            await db.delete(artifact)
            await db.commit()
            storage_service.delete_file(file_hash)
    
    return {"status": "success", "message": "Document removed from index and database."}

@router.post("/{doc_id}/classify")
async def classify_document_content(
    doc_id: str,
    db: AsyncSession = Depends(get_db)
):
    from app.services.classifier import classifier_service
    from app.services.storage import storage_service
    
    stmt = select(Document).where(Document.id == doc_id)
    res = await db.execute(stmt)
    doc = res.scalar_one_or_none()
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
        
    stmt_art = select(Artifact).where(Artifact.hash == doc.file_hash)
    res_art = await db.execute(stmt_art)
    artifact = res_art.scalar_one_or_none()
    
    if not artifact:
        return {"emoji": "❓"} # Artifact missing
        
    try:
        file_bytes = storage_service.read_file(artifact.hash)
        try:
            text_content = file_bytes.decode('utf-8')
        except UnicodeDecodeError:
            return {"emoji": "📄"} 

        emoji = await classifier_service.classify_text(text_content)
        return {"emoji": emoji}
    except Exception as e:
        print(f"Classify error: {e}")
        return {"emoji": "📁"}
    
    
