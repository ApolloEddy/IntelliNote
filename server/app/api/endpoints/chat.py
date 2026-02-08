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
import os

router = APIRouter()

class Message(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    notebook_id: str
    question: str
    source_ids: Optional[List[str]] = None
    history: Optional[List[Message]] = None

def get_cached_index(notebook_id: str):
    notebook_path = os.path.join(settings.VECTOR_STORE_DIR, notebook_id)
    if not os.path.exists(notebook_path) or not os.listdir(notebook_path):
        return None
    storage_context = StorageContext.from_defaults(persist_dir=notebook_path)
    return load_index_from_storage(storage_context)

@router.post("/chat/query")
async def query_notebook_stream(request: ChatRequest):
    index = get_cached_index(request.notebook_id)
    is_empty_selection = isinstance(request.source_ids, list) and len(request.source_ids) == 0
    use_rag = index is not None and not is_empty_selection

    async def event_generator():
        print(f"\n[STREAM] Start. Mode: {'RAG' if use_rag else 'GENERAL'}", flush=True)
        try:
            from llama_index.core import Settings as LlamaSettings
            from llama_index.core.llms import ChatMessage as LlamaChatMessage
            llm = LlamaSettings.llm
            
            chat_history = []
            if request.history:
                for msg in request.history:
                    chat_history.append(LlamaChatMessage(role=msg.role, content=msg.content))
            
            general_system_prompt = prompts.chat_general.format(query_str="")
            
            if not use_rag:
                messages = [LlamaChatMessage(role="system", content=general_system_prompt)] + chat_history + [LlamaChatMessage(role="user", content=request.question)]
                response_gen = await llm.astream_chat(messages)
                async for response in response_gen:
                    yield f"data: {json.dumps({'token': response.delta})}\n\n"
                    await asyncio.sleep(0.01)
            else:
                filters = None
                if request.source_ids:
                    meta_filters = []
                    for sid in request.source_ids:
                        meta_filters.append(MetadataFilter(key="source_file_id", value=sid))
                        meta_filters.append(MetadataFilter(key="doc_id", value=sid))
                    filters = MetadataFilters(filters=meta_filters, condition="or")

                # REPAIR: Switched to 'context' mode which is more stable with DashScope
                # and avoids the 'NoneType' multiplication error in LlamaIndex internals.
                chat_engine = index.as_chat_engine(
                    chat_mode="context", 
                    llm=llm,
                    similarity_top_k=5,
                    filters=filters,
                    system_prompt=prompts.chat_rag.split("### 背景资料")[0],
                    context_template=prompts.chat_context
                )
                
                streaming_response = await chat_engine.astream_chat(request.question, chat_history=chat_history)
                
                recall_count = len(streaming_response.source_nodes)
                print(f"[STREAM] Recall: {recall_count} nodes", flush=True)

                if recall_count == 0:
                    print("[STREAM] Fallback to General", flush=True)
                    messages = [LlamaChatMessage(role="system", content=general_system_prompt)] + chat_history + [LlamaChatMessage(role="user", content=request.question)]
                    response_gen = await llm.astream_chat(messages)
                    async for response in response_gen:
                        yield f"data: {json.dumps({'token': response.delta})}\n\n"
                else:
                    # Normal streaming
                    async for token in streaming_response.async_response_gen():
                        yield f"data: {json.dumps({'token': token})}\n\n"
                        await asyncio.sleep(0.01)

                    citations = []
                    for node in streaming_response.source_nodes:
                        sid = node.node.metadata.get("source_file_id") or node.node.metadata.get("doc_id", "unknown")
                        citations.append({
                            "chunk_id": node.node.node_id,
                            "source_id": sid,
                            "text": node.node.get_content(),
                            "score": node.score or 0.0, # Ensure float
                            "metadata": node.node.metadata
                        })
                    yield f"data: {json.dumps({'citations': citations})}\n\n"

            yield "data: [DONE]\n\n"
        except Exception as e:
            print(f"[STREAM] Error: {e}", flush=True)
            yield f"data: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")

class StudioRequest(BaseModel):
    notebook_id: str
    type: str

@router.post("/studio/generate")
async def generate_studio_content(request: StudioRequest):
    index = get_cached_index(request.notebook_id)
    if not index: raise HTTPException(status_code=404, detail="Not found")
    try:
        query_engine = index.as_query_engine()
        prompt = prompts.studio_study_guide if request.type == "study_guide" else prompts.studio_quiz
        response = query_engine.query(prompt)
        return {"content": str(response), "type": request.type}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))