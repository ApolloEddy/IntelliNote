from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings

# Apply network settings before initializing SDK clients.
settings.apply_network_settings()

# Initialize LlamaIndex IMMEDIATELY before importing endpoints
# This ensures that when ingestion_service is instantiated during import,
# the correct Embedding/LLM models are already configured.
settings.init_llama_index()

from app.api.endpoints import files, chat

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

@app.get("/")
async def root():
    return {"status": "running", "service": settings.PROJECT_NAME}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
