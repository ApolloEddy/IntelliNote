from celery import Celery, Task
from celery.signals import worker_process_init
import asyncio

from app.core.config import settings

# Initialize Settings IMMEDIATELY to support task auto-discovery
# Because 'include' imports tasks, which imports ingestion_service, which checks Settings.
settings.init_llama_index()

celery_app = Celery(
    "intellinote_worker",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=["app.worker.tasks"]
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="Asia/Shanghai",
    enable_utc=True,
    # Worker Optimization
    worker_prefetch_multiplier=1, # One task at a time per worker (CPU bound)
    task_acks_late=True, # Acknowledge only after success
)

@worker_process_init.connect
def init_worker(**kwargs):
    """
    Initialize Global Settings (LlamaIndex, DB Pools) when a worker process starts.
    """
    print("Initializing Celery Worker Process...")
    settings.init_llama_index()

class AsyncContextTask(Task):
    """
    Custom Task class to run async functions in Celery synchronously.
    Celery doesn't natively support async/await well yet.
    """
    def run(self, *args, **kwargs):
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        return loop.run_until_complete(self.run_async(*args, **kwargs))

    async def run_async(self, *args, **kwargs):
        raise NotImplementedError
