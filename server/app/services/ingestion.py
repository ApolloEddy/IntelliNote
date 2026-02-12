import os
import json
import redis.asyncio as redis
from sqlalchemy import select

from llama_index.core import (
    VectorStoreIndex,
    StorageContext,
    load_index_from_storage,
    Settings
)
from llama_index.core.node_parser import SentenceSplitter

from app.core.config import settings
from app.db.session import AsyncSessionLocal
from app.models.document import Document, DocStatus
from app.models.artifact import Artifact
from app.services.storage import storage_service
from app.services.smart_embedding import SmartEmbeddingManager
from app.services.classifier import classifier_service
from app.services.document_parser import DocumentParserRegistry

class IngestionService:
    def __init__(self):
        self.splitter = SentenceSplitter(chunk_size=256, chunk_overlap=20)
        self.embedding_manager = SmartEmbeddingManager(Settings.embed_model)
        self.document_parser = DocumentParserRegistry()
        
        # Ensure vector store directory exists
        if not os.path.exists(settings.VECTOR_STORE_DIR):
             os.makedirs(settings.VECTOR_STORE_DIR)

    def _get_index_path(self, notebook_id: str) -> str:
        # Each notebook gets its own index folder for isolation
        path = os.path.join(settings.VECTOR_STORE_DIR, notebook_id)
        if not os.path.exists(path):
            os.makedirs(path)
        return path

    async def _set_progress(
        self,
        r,
        doc_id: str,
        progress: float,
        stage: str,
        message: str,
        detail: dict | None = None,
    ):
        payload = {
            "progress": max(0.0, min(1.0, progress)),
            "stage": stage,
            "message": message,
        }
        if detail:
            payload["detail"] = detail
        await r.set(f"prog:{doc_id}", json.dumps(payload, ensure_ascii=False))

    async def run_pipeline(self, doc_id: str):
        """
        Orchestrates the Full RAG Ingestion Pipeline.
        """
        r = redis.from_url(settings.REDIS_URL, decode_responses=True)
        await self._set_progress(r, doc_id, 0.02, "queued", "任务排队中")

        async with AsyncSessionLocal() as db:
            # 1. Fetch Metadata
            stmt = select(Document).where(Document.id == doc_id)
            result = await db.execute(stmt)
            doc_record = result.scalar_one_or_none()
            
            if not doc_record:
                print(f"Error: Document {doc_id} not found.")
                await r.close()
                return

            # Update Status -> PROCESSING
            doc_record.status = DocStatus.PROCESSING
            await db.commit()
            await self._set_progress(r, doc_id, 0.06, "loading", "读取文件中")

            try:
                # 2. Fetch Artifact (Physical File)
                stmt_art = select(Artifact).where(Artifact.hash == doc_record.file_hash)
                res_art = await db.execute(stmt_art)
                artifact = res_art.scalar_one_or_none()
                
                if not artifact:
                    raise Exception("Physical artifact missing")
                
                await self._set_progress(r, doc_id, 0.12, "loading", "文件已加载")

                file_path = storage_service.get_file(artifact.hash)
                await self._set_progress(r, doc_id, 0.18, "parsing", "解析文档中")

                # 3. Load & Parse (text/pdf parser is selected by filename extension)
                llama_docs, parse_stats = self.document_parser.parse(
                    file_path=file_path,
                    filename=doc_record.filename,
                )
                
                # Classify
                await self._set_progress(r, doc_id, 0.22, "classifying", "文档分类中")
                full_text = "\n".join([d.text for d in llama_docs[:5]]) # First 5 pages/chunks
                doc_record.emoji = await classifier_service.classify_text(full_text)
                await db.commit()
                await self._set_progress(
                    r,
                    doc_id,
                    0.30,
                    "parsed",
                    "解析完成",
                    parse_stats.to_detail(),
                )

                # Attach Metadata
                for d in llama_docs:
                    d.metadata["source_file_id"] = doc_id
                    d.metadata["notebook_id"] = doc_record.notebook_id
                    d.metadata["filename"] = doc_record.filename

                    # CRITICAL: Exclude dynamic metadata from Embedding
                    for key in (
                        "source_file_id",
                        "notebook_id",
                        "filename",
                        "page_number",
                        "source_parser",
                        "ocr_used",
                        "image_ratio",
                    ):
                        if key not in d.excluded_embed_metadata_keys:
                            d.excluded_embed_metadata_keys.append(key)
                    for key in ("source_file_id", "notebook_id"):
                        if key not in d.excluded_llm_metadata_keys:
                            d.excluded_llm_metadata_keys.append(key)

                # 4. Chunking
                nodes = self.splitter.get_nodes_from_documents(llama_docs)
                total_nodes = len(nodes)
                await self._set_progress(
                    r, doc_id, 0.38, "chunking", "切分 Chunk 完成", {"total_chunks": total_nodes}
                )
                
                # 5. Smart Embedding (Deduplication + API)
                async def _update_embed_prog(processed, total_needed):
                    ratio = (processed / total_needed) if total_needed else 1.0
                    progress = 0.40 + (0.45 * ratio)  # 0.40 -> 0.85
                    await self._set_progress(
                        r,
                        doc_id,
                        progress,
                        "embedding",
                        f"计算向量中 ({processed}/{total_needed})",
                        {"embedded_chunks": processed, "total_chunks": total_needed},
                    )

                await self.embedding_manager.batch_embed_nodes(nodes, progress_callback=_update_embed_prog)
                await self._set_progress(r, doc_id, 0.86, "embedding_done", "向量计算完成")
                
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
                await self._set_progress(r, doc_id, 0.92, "indexing", "写入索引中")
                index.storage_context.persist(persist_dir=index_path)

                # 7. Finalize
                doc_record.status = DocStatus.READY
                await db.commit()
                await self._set_progress(r, doc_id, 1.0, "done", "处理完成")
                await r.expire(f"prog:{doc_id}", 3600) # Clean up later
                print(f"Ingestion successful for {doc_id}")

            except Exception as e:
                print(f"Ingestion Failed: {e}")
                doc_record.status = DocStatus.FAILED
                doc_record.error_msg = str(e)
                await db.commit()
                await self._set_progress(r, doc_id, 1.0, "failed", "处理失败", {"error": str(e)})
                raise
            finally:
                await r.close()

    async def delete_document(self, notebook_id: str, doc_id: str):
        """
        Removes all nodes associated with a doc_id from the notebook's vector index.
        """
        index_path = self._get_index_path(notebook_id)
        if not os.path.exists(os.path.join(index_path, "docstore.json")):
            return

        try:
            storage_context = StorageContext.from_defaults(persist_dir=index_path)
            index = load_index_from_storage(storage_context)
            
            docstore = index.docstore
            all_docs = docstore.docs
            nodes_to_delete = []
            
            for node_id, node in all_docs.items():
                metadata = node.metadata
                if metadata.get("source_file_id") == doc_id or metadata.get("doc_id") == doc_id:
                    nodes_to_delete.append(node_id)
            
            if nodes_to_delete:
                print(f"[Ingestion] Deleting {len(nodes_to_delete)} nodes for doc {doc_id}")
                for node_id in nodes_to_delete:
                    index.delete_nodes([node_id], delete_from_docstore=True)
                index.storage_context.persist(persist_dir=index_path)
            else:
                print(f"[Ingestion] No nodes found in index for doc {doc_id}")
        except Exception as e:
            print(f"[Ingestion] Failed to delete nodes from index: {e}")

ingestion_service = IngestionService()
