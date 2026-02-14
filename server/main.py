from contextlib import asynccontextmanager
import asyncio
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import redis.asyncio as redis

from app.core.config import settings

# Apply network settings before initializing SDK clients.
settings.apply_network_settings()

# Initialize LlamaIndex IMMEDIATELY before importing endpoints
# This ensures that when ingestion_service is instantiated during import,
# the correct Embedding/LLM models are already configured.
settings.init_llama_index()

from app.api.endpoints import files, chat, system

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    yield
    # Shutdown

app = FastAPI(
    title=settings.PROJECT_NAME,
    lifespan=lifespan
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routes
app.include_router(files.router, prefix=f"{settings.API_V1_STR}/files", tags=["files"])
# "chat" router actually handles all RAG operations including studio
app.include_router(chat.router, prefix=f"{settings.API_V1_STR}", tags=["rag"])
app.include_router(system.router, prefix=f"{settings.API_V1_STR}/system", tags=["system"])

@app.get("/")
async def root():
    return {"status": "running", "service": settings.PROJECT_NAME}


async def _check_redis() -> dict:
    client = redis.from_url(settings.REDIS_URL, decode_responses=True)
    try:
        pong = await client.ping()
        return {"ok": bool(pong)}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    finally:
        await client.aclose()


def _check_worker_sync() -> dict:
    try:
        from app.worker.celery_app import celery_app

        inspector = celery_app.control.inspect(timeout=1.0)
        result = inspector.ping() or {}
        nodes = sorted(result.keys())
        return {"ok": bool(nodes), "nodes": nodes}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


@app.get("/health")
async def health():
    redis_check = await _check_redis()
    try:
        worker_check = await asyncio.wait_for(asyncio.to_thread(_check_worker_sync), timeout=2.0)
    except asyncio.TimeoutError:
        worker_check = {"ok": False, "error": "worker ping timeout"}
    config_check = {
        "ok": bool(settings.DASHSCOPE_LLM_API_KEY or settings.DASHSCOPE_API_KEY),
        "llm_model": settings.LLM_MODEL_NAME,
        "embed_model": settings.EMBED_MODEL_NAME,
    }

    checks = {
        "redis": redis_check,
        "worker": worker_check,
        "llm_config": config_check,
    }
    overall_ok = all(item.get("ok", False) for item in checks.values())
    payload = {
        "status": "ok" if overall_ok else "degraded",
        "service": settings.PROJECT_NAME,
        "checks": checks,
    }
    return JSONResponse(status_code=200 if overall_ok else 503, content=payload)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
