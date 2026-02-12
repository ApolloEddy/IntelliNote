import os

from fastapi.testclient import TestClient

# Ensure app boots in test mode with local sqlite.
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///./test_ext_validation.db")
os.environ.setdefault("DASHSCOPE_API_KEY", "dummy_key")

from main import app

client = TestClient(app)


def test_check_file_rejects_unsupported_extension():
    response = client.post(
        "/api/v1/files/check",
        json={
            "notebook_id": "nb_ext",
            "sha256": "x" * 64,
            "filename": "notes.docx",
        },
    )
    assert response.status_code == 400
    assert "TXT" in response.text
    assert "MD" in response.text
    assert "PDF" in response.text
