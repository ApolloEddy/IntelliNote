import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List

import requests


@dataclass
class EvalCase:
    case_id: str
    notebook_id: str
    question: str
    expected_source_ids: List[str]
    expected_keywords: List[str]


def load_cases(path: Path) -> List[EvalCase]:
    cases: List[EvalCase] = []
    for idx, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        data = json.loads(line)
        cases.append(
            EvalCase(
                case_id=str(data.get("case_id") or f"case_{idx}"),
                notebook_id=str(data["notebook_id"]),
                question=str(data["question"]),
                expected_source_ids=[str(x) for x in data.get("expected_source_ids", [])],
                expected_keywords=[str(x) for x in data.get("expected_keywords", [])],
            )
        )
    return cases


def parse_sse_events(lines: Iterable[str]) -> Iterable[dict]:
    for line in lines:
        if not line.startswith("data: "):
            continue
        payload = line[6:].strip()
        if payload == "[DONE]":
            break
        try:
            parsed = json.loads(payload)
            if isinstance(parsed, dict):
                yield parsed
        except json.JSONDecodeError:
            continue


def run_case(api_base: str, case: EvalCase, timeout_seconds: int = 120) -> dict:
    url = f"{api_base.rstrip('/')}/chat/query"
    body = {
        "notebook_id": case.notebook_id,
        "question": case.question,
    }
    resp = requests.post(url, json=body, headers={"Accept": "text/event-stream"}, stream=True, timeout=timeout_seconds)
    resp.raise_for_status()

    answer_tokens: List[str] = []
    citations = []
    stream_error = ""
    for event in parse_sse_events(resp.iter_lines(decode_unicode=True)):
        if "token" in event:
            answer_tokens.append(str(event.get("token") or ""))
        if "citations" in event and isinstance(event["citations"], list):
            citations = event["citations"]
        if "error" in event:
            stream_error = str(event["error"])

    answer = "".join(answer_tokens)
    citation_source_ids = {
        str(c.get("source_id"))
        for c in citations
        if isinstance(c, dict) and c.get("source_id")
    }
    source_hit = any(sid in citation_source_ids for sid in case.expected_source_ids)
    answer_low = answer.lower()
    keyword_hit = any(k.lower() in answer_low for k in case.expected_keywords)

    return {
        "case_id": case.case_id,
        "source_hit": source_hit,
        "keyword_hit": keyword_hit,
        "citations": len(citations),
        "stream_error": stream_error,
        "answer_preview": answer[:180],
    }


def summarize(results: List[dict]) -> dict:
    total = len(results)
    if total == 0:
        return {"total": 0, "source_hit_rate": 0.0, "keyword_hit_rate": 0.0}
    source_hits = sum(1 for r in results if r.get("source_hit"))
    keyword_hits = sum(1 for r in results if r.get("keyword_hit"))
    return {
        "total": total,
        "source_hit_rate": round(source_hits / total, 4),
        "keyword_hit_rate": round(keyword_hits / total, 4),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run lightweight RAG quality eval against IntelliNote API")
    parser.add_argument("--api-base", default="http://127.0.0.1:8000/api/v1")
    parser.add_argument("--cases", default=str(Path(__file__).with_name("rag_eval_cases.jsonl")))
    parser.add_argument("--out", default=str(Path(__file__).with_name("rag_eval_report.json")))
    args = parser.parse_args()

    cases = load_cases(Path(args.cases))
    results = [run_case(args.api_base, case) for case in cases]
    report = {
        "summary": summarize(results),
        "results": results,
    }
    out_path = Path(args.out)
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report["summary"], ensure_ascii=False))
    print(f"report saved: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
