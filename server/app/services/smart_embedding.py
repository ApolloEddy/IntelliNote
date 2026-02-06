import hashlib
import pickle
import asyncio
from typing import List, Dict
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from llama_index.core.embeddings import BaseEmbedding
from llama_index.core.schema import TextNode
from app.models.chunk_cache import ChunkCache
from app.db.session import AsyncSessionLocal

class SmartEmbeddingManager:
    def __init__(self, embed_model: BaseEmbedding):
        self.embed_model = embed_model
        self.model_name = "qwen-v4" # Should match settings

    def _compute_hash(self, text: str) -> str:
        # Normalize text to maximize cache hits (strip whitespace, etc)
        normalized = text.strip().replace("\r\n", "\n")
        return hashlib.sha256(normalized.encode("utf-8")).hexdigest()

    async def batch_embed_nodes(self, nodes: List[TextNode]):
        """
        Main entry point: Takes nodes, fills their embeddings using Cache + API.
        """
        if not nodes:
            return

        # 1. Prepare
        node_map: Dict[str, List[TextNode]] = {} # Hash -> [Nodes] (one hash can map to multiple identical nodes)
        for node in nodes:
            h = self._compute_hash(node.get_content(metadata_mode="embed"))
            if h not in node_map:
                node_map[h] = []
            node_map[h].append(node)
        
        all_hashes = list(node_map.keys())
        needed_hashes = set(all_hashes)
        
        # 2. Check Cache (Async DB)
        async with AsyncSessionLocal() as db:
            # Batch query SQLite
            # SQLite limit is usually 999 vars, so we might need to chunk this query if too huge
            # For simplicity, assuming batch size < 500
            stmt = select(ChunkCache).where(ChunkCache.text_hash.in_(all_hashes))
            result = await db.execute(stmt)
            cached_entries = result.scalars().all()

            for entry in cached_entries:
                embedding = pickle.loads(entry.embedding)
                # Assign to all nodes with this hash
                for node in node_map[entry.text_hash]:
                    node.embedding = embedding
                
                if entry.text_hash in needed_hashes:
                    needed_hashes.remove(entry.text_hash)
        
        # 3. Process Misses (API Call)
        if needed_hashes:
            print(f"Cache Miss: Computing embeddings for {len(needed_hashes)} unique chunks...")
            texts_to_embed = []
            hashes_to_embed = []
            
            # Use one node's content as representative for the hash
            for h in needed_hashes:
                representative_node = node_map[h][0]
                texts_to_embed.append(representative_node.get_content(metadata_mode="embed"))
                hashes_to_embed.append(h)
            
            # Call API (Batch)
            # Ensure embed_model is async compatible or run in threadpool
            embeddings = await self.embed_model.aget_text_embedding_batch(texts_to_embed)
            
            # 4. Save new embeddings to Cache
            new_cache_entries = []
            async with AsyncSessionLocal() as db:
                for h, emb in zip(hashes_to_embed, embeddings):
                    # Assign to nodes
                    for node in node_map[h]:
                        node.embedding = emb
                    
                    # Prepare DB record
                    new_cache_entries.append(ChunkCache(
                        text_hash=h,
                        embedding=pickle.dumps(emb),
                        model_name=self.model_name
                    ))
                
                db.add_all(new_cache_entries)
                await db.commit()
