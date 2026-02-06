import pytest
import pytest_asyncio
import os
import shutil
import json
from unittest.mock import MagicMock, patch, AsyncMock

# --- 环境配置 ---
# 必须在导入 app 之前设置，绕过真实连接
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_suite.db"
os.environ["DASHSCOPE_API_KEY"] = "dummy_key"
os.environ["OPENAI_API_KEY"] = "dummy_key"

from fastapi.testclient import TestClient
from main import app
from app.core.config import settings
from app.db.base import Base
from app.db.session import engine

client = TestClient(app)

# --- Fixtures ---
@pytest_asyncio.fixture(autouse=True)
async def setup_database():
    # Cleanup old
    if os.path.exists("./test_suite.db"):
        try: os.remove("./test_suite.db")
        except: pass
    if os.path.exists("./data/cas_test"):
        shutil.rmtree("./data/cas_test")
    
    # Override CAS dir for test
    settings.CAS_DIR = "./data/cas_test"
    os.makedirs(settings.CAS_DIR, exist_ok=True)
    
    # Init DB
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    yield
    
    # Cleanup (Optional, Windows file lock might fail this)
    # try: os.remove("./test_suite.db")
    # except: pass

# --- Tests ---

@pytest.mark.asyncio
async def test_file_upload_lifecycle():
    """测试文件上传与状态查询"""
    # Mock Celery
    with patch("app.api.endpoints.files.ingest_document_task") as mock_task:
        mock_task.delay = MagicMock()

        # 1. Upload
        file_content = b"Test Content for RAG"
        response = client.post(
            "/api/v1/files/upload",
            data={"notebook_id": "nb_1"},
            files={"file": ("test.txt", file_content, "text/plain")}
        )
        assert response.status_code == 200
        data = response.json()
        doc_id = data["doc_id"]
        assert data["status"] == "processing"
        
        # 2. Check Status
        status_resp = client.get(f"/api/v1/files/{doc_id}/status")
        assert status_resp.status_code == 200
        assert status_resp.json()["status"] == "pending" # Initial DB state

@pytest.mark.asyncio
async def test_chat_streaming():
    """测试流式对话接口 (SSE)"""
    
    # Mock Index & Query Engine
    mock_engine = MagicMock()
    # Mock aquery to return a fake streaming response
    mock_streaming_response = MagicMock()
    
    # async generator for tokens
    async def fake_token_gen():
        yield "Hello"
        yield " World"
    
    mock_streaming_response.response_gen = fake_token_gen()
    mock_streaming_response.source_nodes = [] # Empty citations for simplicity
    
    # async aquery method
    mock_engine.aquery = AsyncMock(return_value=mock_streaming_response)

    # Patch get_cached_index to return our mock index
    with patch("app.api.endpoints.chat.get_cached_index") as mock_get_index:
        mock_index = MagicMock()
        mock_index.as_query_engine.return_value = mock_engine
        mock_get_index.return_value = mock_index

        # Request
        response = client.post(
            "/api/v1/chat/query",
            json={"notebook_id": "nb_1", "question": "Hi"},
            headers={"Accept": "text/event-stream"} # SSE Standard
        )
        
        # Assertions
        assert response.status_code == 200
        assert "text/event-stream" in response.headers["content-type"]
        
        # Verify Content (SSE format)
        content = response.text
        assert "data: " in content
        # Check if we got our tokens
        assert '{"token": "Hello"}' in content
        assert '{"token": " World"}' in content
