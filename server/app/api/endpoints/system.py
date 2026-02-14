from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.core.config import settings

router = APIRouter()


class PdfOcrConfigResponse(BaseModel):
    enabled: bool
    model_name: str
    max_pages: int
    timeout_seconds: int
    text_page_min_chars: int
    scan_page_max_chars: int
    scan_image_ratio_threshold: float
    vision_enabled: bool
    vision_model_name: str
    vision_max_pages: int
    vision_max_images_per_page: int
    vision_timeout_seconds: int
    vision_min_image_ratio: float
    vision_include_text_pages: bool


class PdfOcrConfigUpdate(BaseModel):
    enabled: Optional[bool] = None
    model_name: Optional[str] = Field(default=None, min_length=1, max_length=128)
    max_pages: Optional[int] = Field(default=None, ge=1, le=200)
    timeout_seconds: Optional[int] = Field(default=None, ge=10, le=180)
    text_page_min_chars: Optional[int] = Field(default=None, ge=1, le=2000)
    scan_page_max_chars: Optional[int] = Field(default=None, ge=0, le=200)
    scan_image_ratio_threshold: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    vision_enabled: Optional[bool] = None
    vision_model_name: Optional[str] = Field(default=None, min_length=1, max_length=128)
    vision_max_pages: Optional[int] = Field(default=None, ge=1, le=200)
    vision_max_images_per_page: Optional[int] = Field(default=None, ge=1, le=12)
    vision_timeout_seconds: Optional[int] = Field(default=None, ge=8, le=180)
    vision_min_image_ratio: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    vision_include_text_pages: Optional[bool] = None


def _current_pdf_ocr_config() -> PdfOcrConfigResponse:
    return PdfOcrConfigResponse(
        enabled=bool(settings.PDF_OCR_ENABLED),
        model_name=str(settings.PDF_OCR_MODEL_NAME),
        max_pages=int(settings.PDF_OCR_MAX_PAGES),
        timeout_seconds=int(settings.PDF_OCR_TIMEOUT_SECONDS),
        text_page_min_chars=int(settings.PDF_TEXT_PAGE_MIN_CHARS),
        scan_page_max_chars=int(settings.PDF_SCAN_PAGE_MAX_CHARS),
        scan_image_ratio_threshold=float(settings.PDF_SCAN_IMAGE_RATIO_THRESHOLD),
        vision_enabled=bool(settings.PDF_VISION_ENABLED),
        vision_model_name=str(settings.PDF_VISION_MODEL_NAME),
        vision_max_pages=int(settings.PDF_VISION_MAX_PAGES),
        vision_max_images_per_page=int(settings.PDF_VISION_MAX_IMAGES_PER_PAGE),
        vision_timeout_seconds=int(settings.PDF_VISION_TIMEOUT_SECONDS),
        vision_min_image_ratio=float(settings.PDF_VISION_MIN_IMAGE_RATIO),
        vision_include_text_pages=bool(settings.PDF_VISION_INCLUDE_TEXT_PAGES),
    )


@router.get("/pdf-ocr-config", response_model=PdfOcrConfigResponse)
async def get_pdf_ocr_config():
    return _current_pdf_ocr_config()


@router.put("/pdf-ocr-config", response_model=PdfOcrConfigResponse)
async def update_pdf_ocr_config(payload: PdfOcrConfigUpdate):
    updates = payload.model_dump(exclude_unset=True)
    if not updates:
        raise HTTPException(status_code=400, detail="No config fields provided")

    if "enabled" in updates:
        settings.PDF_OCR_ENABLED = bool(updates["enabled"])
    if "model_name" in updates:
        normalized = str(updates["model_name"]).strip()
        if not normalized:
            raise HTTPException(status_code=422, detail="model_name cannot be blank")
        settings.PDF_OCR_MODEL_NAME = normalized
    if "max_pages" in updates:
        settings.PDF_OCR_MAX_PAGES = int(updates["max_pages"])
    if "timeout_seconds" in updates:
        settings.PDF_OCR_TIMEOUT_SECONDS = int(updates["timeout_seconds"])
    if "text_page_min_chars" in updates:
        settings.PDF_TEXT_PAGE_MIN_CHARS = int(updates["text_page_min_chars"])
    if "scan_page_max_chars" in updates:
        settings.PDF_SCAN_PAGE_MAX_CHARS = int(updates["scan_page_max_chars"])
    if "scan_image_ratio_threshold" in updates:
        settings.PDF_SCAN_IMAGE_RATIO_THRESHOLD = float(updates["scan_image_ratio_threshold"])
    if "vision_enabled" in updates:
        settings.PDF_VISION_ENABLED = bool(updates["vision_enabled"])
    if "vision_model_name" in updates:
        normalized = str(updates["vision_model_name"]).strip()
        if not normalized:
            raise HTTPException(status_code=422, detail="vision_model_name cannot be blank")
        settings.PDF_VISION_MODEL_NAME = normalized
    if "vision_max_pages" in updates:
        settings.PDF_VISION_MAX_PAGES = int(updates["vision_max_pages"])
    if "vision_max_images_per_page" in updates:
        settings.PDF_VISION_MAX_IMAGES_PER_PAGE = int(updates["vision_max_images_per_page"])
    if "vision_timeout_seconds" in updates:
        settings.PDF_VISION_TIMEOUT_SECONDS = int(updates["vision_timeout_seconds"])
    if "vision_min_image_ratio" in updates:
        settings.PDF_VISION_MIN_IMAGE_RATIO = float(updates["vision_min_image_ratio"])
    if "vision_include_text_pages" in updates:
        settings.PDF_VISION_INCLUDE_TEXT_PAGES = bool(updates["vision_include_text_pages"])

    return _current_pdf_ocr_config()
