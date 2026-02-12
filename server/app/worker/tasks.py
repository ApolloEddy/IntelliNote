import asyncio
from app.services.ingestion import ingestion_service
from app.worker.celery_app import celery_app
from app.worker.retry_policy import is_non_retryable_error

@celery_app.task(name="ingest_document", bind=True, max_retries=3)
def ingest_document_task(self, doc_id: str):
    """
    Background task to ingest a document.
    Wraps the async service call.
    """
    print(f"[Task] Starting ingestion for doc_id: {doc_id}")
    try:
        # Always create/close a dedicated event loop in this sync Celery worker context.
        asyncio.run(ingestion_service.run_pipeline(doc_id))
        
        return {"status": "success", "doc_id": doc_id}
    except Exception as e:
        print(f"[Task] Failed: {e}")
        if is_non_retryable_error(e):
            raise
        # Exponential backoff retry
        raise self.retry(exc=e, countdown=2 ** self.request.retries)
