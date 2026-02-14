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


class PdfOcrConfigUpdate(BaseModel):
    enabled: Optional[bool] = None
    model_name: Optional[str] = Field(default=None, min_length=1, max_length=128)
    max_pages: Optional[int] = Field(default=None, ge=1, le=200)
    timeout_seconds: Optional[int] = Field(default=None, ge=10, le=180)
    text_page_min_chars: Optional[int] = Field(default=None, ge=1, le=2000)
    scan_page_max_chars: Optional[int] = Field(default=None, ge=0, le=200)
    scan_image_ratio_threshold: Optional[float] = Field(default=None, ge=0.0, le=1.0)


def _current_pdf_ocr_config() -> PdfOcrConfigResponse:
    return PdfOcrConfigResponse(
        enabled=bool(settings.PDF_OCR_ENABLED),
        model_name=str(settings.PDF_OCR_MODEL_NAME),
        max_pages=int(settings.PDF_OCR_MAX_PAGES),
        timeout_seconds=int(settings.PDF_OCR_TIMEOUT_SECONDS),
        text_page_min_chars=int(settings.PDF_TEXT_PAGE_MIN_CHARS),
        scan_page_max_chars=int(settings.PDF_SCAN_PAGE_MAX_CHARS),
        scan_image_ratio_threshold=float(settings.PDF_SCAN_IMAGE_RATIO_THRESHOLD),
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

    return _current_pdf_ocr_config()

