"""Проверка доступа к Gemini: разбор ответов Google, ключ не попадает в результат."""
from app.ai import gemini


def test_explain_region_and_key():
    assert gemini._explain(400, '{"error":{"message":"User location is not supported for the API use."}}')[0] == "region"
    assert gemini._explain(400, '{"error":{"message":"API key not valid. Please pass a valid API key."}}')[0] == "bad_key"
    assert gemini._explain(429, "quota")[0] == "quota"


def test_no_key(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    r = gemini.check()
    assert r["status"] == "no_key" and not r["ok"]
