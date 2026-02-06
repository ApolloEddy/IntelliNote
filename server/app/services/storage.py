import hashlib
import shutil
import os
from typing import BinaryIO, Tuple
from app.core.config import settings

class StorageService:
    def __init__(self):
        self.base_path = settings.CAS_DIR
        if not os.path.exists(self.base_path):
            os.makedirs(self.base_path)

    def get_path(self, file_hash: str) -> str:
        """
        Shards directories to avoid too many files in one folder.
        e.g., hash "abcdef..." -> "cas/ab/cd/abcdef..."
        """
        if len(file_hash) < 4:
            return os.path.join(self.base_path, file_hash)
        
        p1 = file_hash[:2]
        p2 = file_hash[2:4]
        return os.path.join(self.base_path, p1, p2, file_hash)

    def save_file(self, file_obj: BinaryIO) -> Tuple[str, int]:
        """
        Reads file stream, computes SHA256, saves to CAS.
        Returns (sha256_hash, file_size_bytes)
        """
        sha256 = hashlib.sha256()
        temp_path = os.path.join(self.base_path, "temp_upload")
        
        # Ensure temp dir exists
        if not os.path.exists(os.path.dirname(temp_path)):
             os.makedirs(os.path.dirname(temp_path))

        size = 0
        with open(temp_path, "wb") as f_out:
            while chunk := file_obj.read(8192):
                sha256.update(chunk)
                f_out.write(chunk)
                size += len(chunk)
        
        file_hash = sha256.hexdigest()
        dest_path = self.get_path(file_hash)
        
        # If already exists, we can discard temp (CAS property)
        if os.path.exists(dest_path):
            os.remove(temp_path)
        else:
            # Move temp to final CAS location
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            shutil.move(temp_path, dest_path)
            
        return file_hash, size

    def get_file(self, file_hash: str) -> str:
        path = self.get_path(file_hash)
        if not os.path.exists(path):
            raise FileNotFoundError(f"File {file_hash} not found in CAS")
        return path

storage_service = StorageService()
