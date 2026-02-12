import os
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict
from llama_index.core import Settings as LlamaSettings
from llama_index.llms.dashscope import DashScope, DashScopeGenerationModels
from app.services.dashscope_http_embedding import DashScopeHTTPEmbedding

class Settings(BaseSettings):
    # App
    PROJECT_NAME: str = "Intelli Note Server"
    API_V1_STR: str = "/api/v1"
    
    # DashScope (Qwen)
    DASHSCOPE_API_KEY: Optional[str] = None # Fallback
    DASHSCOPE_LLM_API_KEY: Optional[str] = None
    DASHSCOPE_EMBED_API_KEY: Optional[str] = None
    
    LLM_MODEL_NAME: str = "qwen-plus" # Default fallback, user uses qwen3-32b
    EMBED_MODEL_NAME: str = "text-embedding-v3" # Default fallback
    EMBED_BATCH_SIZE: int = 1
    DASHSCOPE_CHAT_TIMEOUT_SECONDS: int = 90
    PDF_OCR_MODEL_NAME: str = "qwen-vl-max-latest"
    PDF_OCR_ENABLED: bool = False
    PDF_OCR_MAX_PAGES: int = 12
    PDF_OCR_TIMEOUT_SECONDS: int = 45
    PDF_TEXT_PAGE_MIN_CHARS: int = 20
    PDF_SCAN_PAGE_MAX_CHARS: int = 8
    PDF_SCAN_IMAGE_RATIO_THRESHOLD: float = 0.65

    # Network (proxy/tun)
    HTTP_PROXY: Optional[str] = None
    HTTPS_PROXY: Optional[str] = None
    NO_PROXY: Optional[str] = None
    DASHSCOPE_FORCE_NO_PROXY: bool = False

    # Database
    DATABASE_URL: str = "sqlite+aiosqlite:///./data/sql_app.db"
    
    # Storage Paths
    STORAGE_BASE: str = "./data"
    CAS_DIR: str = "./data/cas"
    VECTOR_STORE_DIR: str = "./data/vector_store"
    
    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True, extra="ignore")

    def apply_network_settings(self):
        """
        Apply proxy/TUN related environment variables for SDKs that read from os.environ.
        """
        if self.HTTP_PROXY:
            os.environ["HTTP_PROXY"] = self.HTTP_PROXY
            os.environ["http_proxy"] = self.HTTP_PROXY

        if self.HTTPS_PROXY:
            os.environ["HTTPS_PROXY"] = self.HTTPS_PROXY
            os.environ["https_proxy"] = self.HTTPS_PROXY

        if self.NO_PROXY:
            os.environ["NO_PROXY"] = self.NO_PROXY
            os.environ["no_proxy"] = self.NO_PROXY

        if self.DASHSCOPE_FORCE_NO_PROXY:
            base = os.environ.get("NO_PROXY", "")
            parts = [p.strip() for p in base.split(",") if p.strip()]
            required = ["aliyuncs.com", "dashscope.aliyuncs.com"]
            for host in required:
                if host not in parts:
                    parts.append(host)
            merged = ",".join(parts)
            os.environ["NO_PROXY"] = merged
            os.environ["no_proxy"] = merged

        print(
            "[Network] HTTP_PROXY={}, HTTPS_PROXY={}, NO_PROXY={}, DASHSCOPE_FORCE_NO_PROXY={}".format(
                "set" if os.environ.get("HTTP_PROXY") else "unset",
                "set" if os.environ.get("HTTPS_PROXY") else "unset",
                "set" if os.environ.get("NO_PROXY") else "unset",
                "true" if self.DASHSCOPE_FORCE_NO_PROXY else "false",
            )
        )

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
            LlamaSettings.embed_model = DashScopeHTTPEmbedding(
                model_name=self.EMBED_MODEL_NAME,
                api_key=embed_key
            )
        
        LlamaSettings.chunk_size = 256 # Reduced from 512
        LlamaSettings.chunk_overlap = 20 # Reduced from 50

settings = Settings()
