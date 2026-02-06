from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional
import json
import asyncio
from llama_index.core import StorageContext, load_index_from_storage
from llama_index.core.vector_stores import MetadataFilters, MetadataFilter
from app.core.config import settings
from functools import lru_cache
import os

router = APIRouter()

# --- Models ---
class ChatRequest(BaseModel):
    notebook_id: str
    question: str
    source_ids: Optional[List[str]] = None

class Citation(BaseModel):
    chunk_id: str
    source_id: str
    text: str
    score: Optional[float]
    metadata: dict

# --- Index Cache ---
@lru_cache(maxsize=20)
def get_cached_index(notebook_id: str):
    notebook_path = os.path.join(settings.VECTOR_STORE_DIR, notebook_id)
    if not os.path.exists(notebook_path) or not os.listdir(notebook_path):
        return None
        
    storage_context = StorageContext.from_defaults(persist_dir=notebook_path)
    return load_index_from_storage(storage_context)

@router.post("/chat/query")
async def query_notebook_stream(request: ChatRequest):
    """
    Server-Sent Events (SSE) Endpoint for Streaming Chat.
    """
    index = get_cached_index(request.notebook_id)
    if not index:
        # Fallback for empty index: Stream a static message
        async def empty_stream():
            yield f"data: {json.dumps({'token': '该笔记本尚无可用资料，请先上传文件。'})}\n\n"
            yield f"data: {json.dumps({'citations': []})}\n\n"
        return StreamingResponse(empty_stream(), media_type="text/event-stream")

    # Build Filters
    filters = None
    if request.source_ids and len(request.source_ids) > 0:
        meta_filters = [
            MetadataFilter(key="doc_id", value=sid) 
            for sid in request.source_ids
        ]
        filters = MetadataFilters(filters=meta_filters, condition="or")

    # Create Streaming Engine
    query_engine = index.as_query_engine(
        similarity_top_k=3,
        filters=filters,
        streaming=True # Enable Streaming
    )

    async def event_generator():
        try:
            # 1. Start Query
            streaming_response = await query_engine.aquery(request.question)
            
            # 2. Stream Tokens
            async for token in streaming_response.response_gen:
                # SSE format: data: <json>\n\n
                payload = {"token": token}
                yield f"data: {json.dumps(payload)}\n\n"
                # Yield control to event loop
                await asyncio.sleep(0.01)

            # 3. Stream Citations (After text is done)
            citations = []
            if streaming_response.source_nodes:
                for node in streaming_response.source_nodes:
                    citations.append({
                        "chunk_id": node.node.node_id,
                        "source_id": node.node.metadata.get("doc_id", "unknown"),
                        "text": node.node.get_content(),
                        "score": node.score,
                        "metadata": node.node.metadata
                    })
            
            yield f"data: {json.dumps({'citations': citations})}\n\n"
            yield "data: [DONE]\n\n"

        except Exception as e:
            print(f"Stream Error: {e}")
            error_payload = {"error": str(e)}
            yield f"data: {json.dumps(error_payload)}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")

class StudioRequest(BaseModel):
    notebook_id: str
    type: str # "study_guide" | "quiz"

@router.post("/studio/generate")
async def generate_studio_content(request: StudioRequest):
    index = get_cached_index(request.notebook_id)
    
    if not index:
        raise HTTPException(status_code=404, detail="Notebook index not found")

    try:
        query_engine = index.as_query_engine()
        
        prompt = ""
        if request.type == "study_guide":
            prompt = "请根据所有资料，为我生成一份详细的学习指南。包含核心概念、关键知识点总结和复习建议。使用Markdown格式，层级清晰。"
        elif request.type == "quiz":
            prompt = "请根据资料生成5道测验题（单选或简答）。每道题后附带正确答案和解析。使用Markdown格式。"
        else:
            raise HTTPException(status_code=400, detail="Invalid type")
            
        response = query_engine.query(prompt)
        
        return {
            "content": str(response),
            "type": request.type
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))