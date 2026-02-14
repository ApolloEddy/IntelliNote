import os

os.environ.setdefault("DASHSCOPE_API_KEY", "dummy_key")
os.environ.setdefault("OPENAI_API_KEY", "dummy_key")

from fastapi.testclient import TestClient

from main import app
from app.core.config import settings

client = TestClient(app)


def test_get_pdf_ocr_config_returns_expected_fields():
    response = client.get("/api/v1/system/pdf-ocr-config")
    assert response.status_code == 200
    data = response.json()
    assert "enabled" in data
    assert "model_name" in data
    assert "max_pages" in data
    assert "timeout_seconds" in data
    assert "vision_enabled" in data
    assert "vision_model_name" in data
    assert "vision_max_pages" in data


def test_put_pdf_ocr_config_updates_runtime_values():
    old_enabled = settings.PDF_OCR_ENABLED
    old_pages = settings.PDF_OCR_MAX_PAGES
    old_vision_enabled = settings.PDF_VISION_ENABLED
    old_vision_pages = settings.PDF_VISION_MAX_PAGES
    try:
        response = client.put(
            "/api/v1/system/pdf-ocr-config",
            json={
                "enabled": True,
                "max_pages": 18,
                "scan_image_ratio_threshold": 0.8,
                "vision_enabled": True,
                "vision_max_pages": 6,
                "vision_max_images_per_page": 3,
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["enabled"] is True
        assert data["max_pages"] == 18
        assert abs(float(data["scan_image_ratio_threshold"]) - 0.8) < 1e-6
        assert data["vision_enabled"] is True
        assert data["vision_max_pages"] == 6
        assert data["vision_max_images_per_page"] == 3
    finally:
        settings.PDF_OCR_ENABLED = old_enabled
        settings.PDF_OCR_MAX_PAGES = old_pages
        settings.PDF_VISION_ENABLED = old_vision_enabled
        settings.PDF_VISION_MAX_PAGES = old_vision_pages


def test_put_pdf_ocr_config_rejects_out_of_range_threshold():
    response = client.put(
        "/api/v1/system/pdf-ocr-config",
        json={"scan_image_ratio_threshold": 1.5, "vision_min_image_ratio": 1.5},
    )
    assert response.status_code == 422
