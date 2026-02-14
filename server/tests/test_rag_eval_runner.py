import json
from pathlib import Path

from tools.rag_eval_runner import EvalCase, load_cases, summarize


def test_load_cases_parses_jsonl(tmp_path: Path):
    case_path = tmp_path / "cases.jsonl"
    case_path.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "case_id": "c1",
                        "notebook_id": "nb-1",
                        "question": "Q1",
                        "expected_source_ids": ["s1"],
                        "expected_keywords": ["k1"],
                    },
                    ensure_ascii=False,
                ),
                json.dumps(
                    {
                        "notebook_id": "nb-2",
                        "question": "Q2",
                    },
                    ensure_ascii=False,
                ),
            ]
        ),
        encoding="utf-8",
    )

    cases = load_cases(case_path)
    assert len(cases) == 2
    assert isinstance(cases[0], EvalCase)
    assert cases[0].case_id == "c1"
    assert cases[1].case_id == "case_2"
    assert cases[1].expected_source_ids == []


def test_summarize_returns_hit_rates():
    report = summarize(
        [
            {"source_hit": True, "keyword_hit": False},
            {"source_hit": True, "keyword_hit": True},
            {"source_hit": False, "keyword_hit": False},
        ]
    )
    assert report["total"] == 3
    assert abs(report["source_hit_rate"] - 0.6667) < 1e-6
    assert abs(report["keyword_hit_rate"] - 0.3333) < 1e-6

