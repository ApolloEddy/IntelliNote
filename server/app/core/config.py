from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict
from llama_index.core import Settings as LlamaSettings
from llama_index.llms.dashscope import DashScope, DashScopeGenerationModels
from llama_index.embeddings.dashscope import DashScopeEmbedding, DashScopeTextEmbeddingModels

class Settings(BaseSettings):
    # App
    PROJECT_NAME: str = "IntelliNote Server"
    API_V1_STR: str = "/api/v1"
    
    # DashScope (Qwen)
    DASHSCOPE_API_KEY: str
    
    # Database
    DATABASE_URL: str = "sqlite+aiosqlite:///./data/sql_app.db"
    
    # Storage Paths
    STORAGE_BASE: str = "./data"
    CAS_DIR: str = "./data/cas"
    VECTOR_STORE_DIR: str = "./data/vector_store"
    
    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

    def init_llama_index(self):
        """
        Initialize Global LlamaIndex Settings
        """
        if not self.DASHSCOPE_API_KEY:
             print("WARNING: DASHSCOPE_API_KEY not found.")
             return

        # LLM
        LlamaSettings.llm = DashScope(
            model_name=DashScopeGenerationModels.QWEN_FLASH,
            api_key=self.DASHSCOPE_API_KEY
        )
        
        # Embedding
        LlamaSettings.embed_model = DashScopeEmbedding(
            model_name=DashScopeTextEmbeddingModels.TEXT_EMBEDDING_V4,
            api_key=self.DASHSCOPE_API_KEY
        )
        
        LlamaSettings.chunk_size = 512
        LlamaSettings.chunk_overlap = 50

settings = Settings()