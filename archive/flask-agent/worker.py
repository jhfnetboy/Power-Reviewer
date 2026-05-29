"""RQ worker 任务入口。坑#5:每次 review 都建全新 state,无历史。"""
from graph import graph


def review_pr(repo: str, pr_number: int) -> dict:
    state = {"repo": repo, "pr": pr_number, "diff": "", "evidence": "", "findings": []}
    return graph.invoke(state)
