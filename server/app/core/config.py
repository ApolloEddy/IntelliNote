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
    DASHSCOPE_API_KEY: Optional[str] = None # Fallback
    DASHSCOPE_LLM_API_KEY: Optional[str] = None
    DASHSCOPE_EMBED_API_KEY: Optional[str] = None
    
    LLM_MODEL_NAME: str = "qwen-plus" # Default fallback, user uses qwen3-32b
    EMBED_MODEL_NAME: str = "text-embedding-v3" # Default fallback

    # Database
    DATABASE_URL: str = "sqlite+aiosqlite:///./data/sql_app.db"
    
    # Storage Paths
    STORAGE_BASE: str = "./data"
    CAS_DIR: str = "./data/cas"
    VECTOR_STORE_DIR: str = "./data/vector_store"
    
    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True, extra="ignore")

    def init_llama_index(self):
        """
        Initialize Global LlamaIndex Settings
        """
        llm_key = self.DASHSCOPE_LLM_API_KEY or self.DASHSCOPE_API_KEY
        embed_key = self.DASHSCOPE_EMBED_API_KEY or self.DASHSCOPE_API_KEY

        if not llm_key:
             print("WARNING: LLM API Key not found.")
        
        if not embed_key:
             print("WARNING: Embedding API Key not found.")

        # LLM
        if llm_key:
            LlamaSettings.llm = DashScope(
                model_name=self.LLM_MODEL_NAME,
                api_key=llm_key,
                max_tokens=4096, # Reduced to fit in context window
            )
        
        # Embedding
        if embed_key:
            LlamaSettings.embed_model = DashScopeEmbedding(
                model_name=self.EMBED_MODEL_NAME,
                api_key=embed_key
            )
        
        LlamaSettings.chunk_size = 256 # Reduced from 512
        LlamaSettings.chunk_overlap = 20 # Reduced from 50

settings = Settings()