"""LangGraph review 流水线:fetch_diff → analyze → post_comment。
坑#4:/no_think 前缀关掉 Qwen3 thinking,普通 review 提速 30s+;复杂 bug 才手动开。
坑#5:无状态——每次都用全新 state,不保留对话历史,避免长跑后推理质量漂移。"""
from typing import TypedDict

from langchain_ollama import ChatOllama
from langgraph.graph import END, StateGraph

NO_THINK = "/no_think "  # 坑#4

# 坑#3:keep_alive=-1 让模型常驻显存(配合 OLLAMA_KEEP_ALIVE=-1 与 LaunchAgent)
llm = ChatOllama(
    model="qwen2.5-coder:32b",   # 先用 dense 跑通;切 MoE 见研究文档 §13
    base_url="http://localhost:11434",
    temperature=0,
    keep_alive=-1,
    num_ctx=8192,                # 本地上下文有限——大 PR 需在 analyze 里做 token-aware 分块
)


class ReviewState(TypedDict):
    repo: str
    pr: int
    diff: str
    evidence: str   # GitHub Actions 跑出的 Semgrep/CodeQL SARIF(免费托管 runner)
    findings: list


def fetch_diff(state: ReviewState) -> ReviewState:
    # TODO: PyGithub 读 PR diff;可选拉对应 Actions run 的 SARIF artifact 填 evidence
    raise NotImplementedError


def analyze(state: ReviewState) -> ReviewState:
    # TODO: 大 PR 按 token 预算分块(借鉴 PR-Agent);逐块审后合并去重
    system = (
        "你是严格的代码审查器。只报高置信度问题,按 Critical/High/Medium/Low 分级。"
        "聚焦:安全、明显 bug、文档/注释是否同步、测试是否完备。只输出 JSON 数组,绝不改代码。"
    )
    user = NO_THINK + f"在以下确定性证据基础上审查 diff:\n\n[证据]\n{state['evidence']}\n\n[diff]\n{state['diff']}"
    resp = llm.invoke([("system", system), ("user", user)])
    # TODO: 解析 JSON;失败则 self-reflection 重试一次(借鉴 PR-Agent §10.3)
    state["findings"] = [{"raw": resp.content}]
    return state


def post_comment(state: ReviewState) -> ReviewState:
    # TODO: GitHub Reviews API 发评论;分级 + 折叠 + 每 PR 上限以降噪;绝不写回代码
    raise NotImplementedError


def build_graph():
    g = StateGraph(ReviewState)
    g.add_node("fetch_diff", fetch_diff)
    g.add_node("analyze", analyze)
    g.add_node("post_comment", post_comment)
    g.set_entry_point("fetch_diff")
    g.add_edge("fetch_diff", "analyze")
    g.add_edge("analyze", "post_comment")
    g.add_edge("post_comment", END)
    return g.compile()


graph = build_graph()
