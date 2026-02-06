import asyncio
from asgiref.sync import async_to_sync
from celery import shared_task
from app.services.ingestion import ingestion_service
from app.worker.celery_app import celery_app

@celery_app.task(name="ingest_document", bind=True, max_retries=3)
def ingest_document_task(self, doc_id: str):
    """
    Background task to ingest a document.
    Wraps the async service call.
    """
    print(f"[Task] Starting ingestion for doc_id: {doc_id}")
    try:
        # Use asyncio.run to execute the async pipeline in this sync worker thread
        # Note: We create a new loop because Celery workers (prefork) don't have one by default.
        loop = asyncio.get_event_loop()
        if loop.is_closed():
             loop = asyncio.new_event_loop()
             asyncio.set_event_loop(loop)
        
        loop.run_until_complete(ingestion_service.run_pipeline(doc_id))
        
        return {"status": "success", "doc_id": doc_id}
    except Exception as e:
        print(f"[Task] Failed: {e}")
        # Exponential backoff retry
        raise self.retry(exc=e, countdown=2 ** self.request.retries)
