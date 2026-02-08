import os
from pathlib import Path

class PromptLoader:
    _BASE_DIR = Path(__file__).parent.parent / "templates"

    @classmethod
    def _load(cls, subpath: str) -> str:
        """Loads a prompt template from the filesystem."""
        file_path = cls._BASE_DIR / subpath
        if not file_path.exists():
            raise FileNotFoundError(f"Prompt template not found: {file_path}")
        return file_path.read_text(encoding="utf-8")

    @property
    def studio_study_guide(self) -> str:
        return self._load("studio/study_guide.md")

    @property
    def studio_quiz(self) -> str:
        return self._load("studio/quiz.md")

# Singleton instance
prompts = PromptLoader()