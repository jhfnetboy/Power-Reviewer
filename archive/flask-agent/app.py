"""Flask webhook 接收端。唯一职责:验签 → 入队 → 立即 202。
坑#2:GitHub webhook 10s 超时,LLM 推理 7~30s,绝不能在这里同步等,否则 GitHub 反复重试。"""
import hashlib
import hmac
import os

from flask import Flask, abort, request
from redis import Redis
from rq import Queue

app = Flask(__name__)
queue = Queue("reviews", connection=Redis())
WEBHOOK_SECRET = os.environ["GH_WEBHOOK_SECRET"].encode()


def _verify(req) -> None:
    sig = req.headers.get("X-Hub-Signature-256", "")
    mac = "sha256=" + hmac.new(WEBHOOK_SECRET, req.data, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(mac, sig):
        abort(401)


@app.post("/webhook")
def webhook():
    _verify(request)
    event = request.headers.get("X-GitHub-Event")
    payload = request.get_json(silent=True) or {}
    if event == "pull_request" and payload.get("action") in {"opened", "synchronize", "reopened"}:
        repo = payload["repository"]["full_name"]
        pr_number = payload["pull_request"]["number"]
        # 入队即返回;真正的 review 在 worker 里跑
        queue.enqueue("worker.review_pr", repo, pr_number, job_timeout=600)
    return "", 202


@app.get("/healthz")
def healthz():
    return "ok", 200
