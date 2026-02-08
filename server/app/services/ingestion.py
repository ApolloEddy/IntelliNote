import os
from typing import List
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from llama_index.core import (
    VectorStoreIndex,
    SimpleDirectoryReader,
    StorageContext,
    load_index_from_storage,
    Document as LlamaDocument,
    Settings
)
from llama_index.core.node_parser import SentenceSplitter

from app.core.config import settings
from app.db.session import AsyncSessionLocal
from app.models.document import Document, DocStatus
from app.models.artifact import Artifact
from app.services.storage import storage_service
from app.services.smart_embedding import SmartEmbeddingManager

class IngestionService:
    def __init__(self):
        self.splitter = SentenceSplitter(chunk_size=512, chunk_overlap=50)
        self.embedding_manager = SmartEmbeddingManager(Settings.embed_model)
        
        # Ensure vector store directory exists
        if not os.path.exists(settings.VECTOR_STORE_DIR):
             os.makedirs(settings.VECTOR_STORE_DIR)

    def _get_index_path(self, notebook_id: str) -> str:
        # Each notebook gets its own index folder for isolation
        path = os.path.join(settings.VECTOR_STORE_DIR, notebook_id)
        if not os.path.exists(path):
            os.makedirs(path)
        return path

    async def run_pipeline(self, doc_id: str):
        """
        Orchestrates the Full RAG Ingestion Pipeline.
        """
        async with AsyncSessionLocal() as db:
            # 1. Fetch Metadata
            stmt = select(Document).where(Document.id == doc_id)
            result = await db.execute(stmt)
            doc_record = result.scalar_one_or_none()
            
            if not doc_record:
                print(f"Error: Document {doc_id} not found.")
                return

            # Update Status -> PROCESSING
            doc_record.status = DocStatus.PROCESSING
            await db.commit()

            try:
                # 2. Fetch Artifact (Physical File)
                stmt_art = select(Artifact).where(Artifact.hash == doc_record.file_hash)
                res_art = await db.execute(stmt_art)
                artifact = res_art.scalar_one_or_none()
                
                if not artifact:
                    raise Exception("Physical artifact missing")

                file_path = storage_service.get_file(artifact.hash)
                
                # 3. Load & Parse
                # TODO: Integrate LlamaParse for PDFs here if needed.
                # Currently using SimpleDirectoryReader for text/md.
                reader = SimpleDirectoryReader(input_files=[file_path])
                llama_docs = reader.load_data()
                
                # Attach Metadata
                for d in llama_docs:
                    d.metadata["doc_id"] = doc_id
                    d.metadata["notebook_id"] = doc_record.notebook_id
                    d.metadata["filename"] = doc_record.filename
                    
                    # CRITICAL: Exclude dynamic metadata from Embedding
                    # This ensures that SmartEmbedding calculates hash based ONLY on content,
                    # allowing deduplication across different uploads (doc_ids) of the same file.
                    d.excluded_embed_metadata_keys.extend(["doc_id", "notebook_id", "filename"])
                    d.excluded_llm_metadata_keys.extend(["doc_id", "notebook_id"])

                # 4. Chunking
                nodes = self.splitter.get_nodes_from_documents(llama_docs)
                
                # 5. Smart Embedding (Deduplication + API)
                await self.embedding_manager.batch_embed_nodes(nodes)
                
                # 6. Indexing (Persistence)
                # We lock the index by notebook_id (file-based lock implicit in OS)
                index_path = self._get_index_path(doc_record.notebook_id)
                
                # Check if index exists
                try:
                    storage_context = StorageContext.from_defaults(persist_dir=index_path)
                    index = load_index_from_storage(storage_context)
                    index.insert_nodes(nodes)
                except (FileNotFoundError, ValueError):
                    # Create new index
                    storage_context = StorageContext.from_defaults()
                    index = VectorStoreIndex(nodes, storage_context=storage_context)
                
                # Persist
                index.storage_context.persist(persist_dir=index_path)

                # 7. Finalize
                doc_record.status = DocStatus.READY
                await db.commit()
                print(f"Ingestion successful for {doc_id}")

            except Exception as e:
                print(f"Ingestion Failed: {e}")
                doc_record.status = DocStatus.FAILED
                doc_record.error_msg = str(e)
                await db.commit()

ingestion_service = IngestionService()
