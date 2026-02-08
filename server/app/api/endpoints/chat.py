from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional
import json
import asyncio
from llama_index.core import StorageContext, load_index_from_storage
from llama_index.core.vector_stores import MetadataFilters, MetadataFilter
from app.core.config import settings
from app.core.prompts import prompts
from functools import lru_cache
import os

router = APIRouter()

# --- Models ---
class Message(BaseModel):
    role: str # "user" | "assistant"
    content: str

class ChatRequest(BaseModel):
    notebook_id: str
    question: str
    source_ids: Optional[List[str]] = None
    history: Optional[List[Message]] = None

class Citation(BaseModel):
    chunk_id: str
    source_id: str
    text: str
    score: Optional[float]
    metadata: dict

# --- Index Cache ---
# REMOVED lru_cache because ingestion happens in a separate process (Celery).
# The API server needs to reload from disk to see updates.
# Optimization TODO: Use a file-watcher or timestamp check to reload only when changed.
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
    
    # Determine mode
    # None -> Global RAG (default)
    # [...] -> Filtered RAG
    # [] -> General Chat (User explicitly unselected everything)
    is_empty_selection = isinstance(request.source_ids, list) and len(request.source_ids) == 0
    use_rag = index is not None and not is_empty_selection

    async def event_generator():
        try:
            from llama_index.core import Settings as LlamaSettings
            from llama_index.core.llms import ChatMessage as LlamaChatMessage
            llm = LlamaSettings.llm
            
            # Convert history to LlamaIndex format
            chat_history = []
            if request.history:
                for msg in request.history:
                    chat_history.append(LlamaChatMessage(role=msg.role, content=msg.content))
            
            if not use_rag:
                # --- Path A: General Chat with History ---
                system_prompt = prompts.chat_general.format(query_str="")
                messages = [LlamaChatMessage(role="system", content=system_prompt)] + chat_history + [LlamaChatMessage(role="user", content=request.question)]
                
                response_gen = await llm.astream_chat(messages)
                async for response in response_gen:
                    yield f"data: {json.dumps({'token': response.delta})}\n\n"
                    await asyncio.sleep(0.01)
                yield f"data: {json.dumps({'citations': []})}\n\n"
            
            else:
                # --- Path B: RAG with Intelligent History (CondensePlusContext) ---
                filters = None
                if request.source_ids is not None and len(request.source_ids) > 0:
                    meta_filters = []
                    for sid in request.source_ids:
                        meta_filters.append(MetadataFilter(key="source_file_id", value=sid))
                        meta_filters.append(MetadataFilter(key="doc_id", value=sid))
                    filters = MetadataFilters(filters=meta_filters, condition="or")

                # Initialize advanced Chat Engine
                chat_engine = index.as_chat_engine(
                    chat_mode="condense_plus_context",
                    llm=llm,
                    similarity_top_k=10,
                    filters=filters,
                    system_prompt=prompts.chat_rag.split("### 背景资料")[0],
                    context_template=prompts.chat_context,
                    condense_prompt=prompts.chat_condense
                )
                
                streaming_response = await chat_engine.astream_chat(request.question, chat_history=chat_history)
                
                # Correctly use the async generator for tokens
                async for token in streaming_response.async_response_gen():
                    yield f"data: {json.dumps({'token': token})}\n\n"
                    await asyncio.sleep(0.01)

                citations = []
                if streaming_response.source_nodes:
                    for node in streaming_response.source_nodes:
                        sid = node.node.metadata.get("source_file_id") or node.node.metadata.get("doc_id", "unknown")
                        citations.append({
                            "chunk_id": node.node.node_id,
                            "source_id": sid,
                            "text": node.node.get_content(),
                            "score": node.score,
                            "metadata": node.node.metadata
                        })
                yield f"data: {json.dumps({'citations': citations})}\n\n"

            yield "data: [DONE]\n\n"

        except Exception as e:
            print(f"CRITICAL ERROR in event_generator: {e}")
            import traceback
            traceback.print_exc()
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

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
            prompt = prompts.studio_study_guide
        elif request.type == "quiz":
            prompt = prompts.studio_quiz
        else:
            raise HTTPException(status_code=400, detail="Invalid type")
            
        response = query_engine.query(prompt)
        
        return {
            "content": str(response),
            "type": request.type
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))