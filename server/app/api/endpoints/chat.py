from typing import List, Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from llama_index.core import StorageContext, load_index_from_storage, VectorStoreIndex
from app.core.config import settings
import os

router = APIRouter()

class ChatRequest(BaseModel):
    notebook_id: str
    question: str

class Citation(BaseModel):
    chunk_id: str
    source_id: str
    text: str
    score: Optional[float]
    metadata: dict

class ChatResponse(BaseModel):
    answer: str
    citations: List[Citation]

@router.post("/query", response_model=ChatResponse)
async def query_notebook(request: ChatRequest):
    notebook_path = os.path.join(settings.VECTOR_STORE_DIR, request.notebook_id)
    
    # Check if index exists
    if not os.path.exists(notebook_path) or not os.listdir(notebook_path):
        return ChatResponse(
            answer="该笔记本尚无可用资料，请先上传文件。",
            citations=[]
        )

    try:
        # Load Index
        storage_context = StorageContext.from_defaults(persist_dir=notebook_path)
        index = load_index_from_storage(storage_context)
        
        # Query
        query_engine = index.as_query_engine(
            similarity_top_k=3,
        )
        response = query_engine.query(request.question)
        
        # Format Response
        citations = []
        for node in response.source_nodes:
            citations.append(Citation(
                chunk_id=node.node.node_id,
                source_id=node.node.metadata.get("doc_id", "unknown"),
                text=node.node.get_content(),
                score=node.score,
                metadata=node.node.metadata
            ))
            
        return ChatResponse(
            answer=str(response),
            citations=citations
        )
    except Exception as e:
        print(f"Query Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
