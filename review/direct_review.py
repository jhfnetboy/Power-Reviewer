#!/usr/bin/env python3
"""路径2:非 agentic 直评。diff(+证据) → omlx 每个 lens 出结构化 JSON → 聚合 → gh 发 inline review。
不用工具调用(本地 2.5-Coder 的 tool-call omlx 解析不了),纯 chat completion,对 24h 跑更稳。

用法:
  OMLX_API_KEY=... python3 review/direct_review.py --repo owner/repo --pr 123 [--dry-run]
  python3 review/direct_review.py --diff-file some.diff --dry-run        # 离线测
  --lenses security,testing,docs,consistency   # 默认全开
  --model omlx/Qwen2.5-Coder-32B-Instruct-MLX-8bit
"""
import argparse, json, os, re, subprocess, sys, urllib.request

OMLX_BASE = os.environ.get("OMLX_BASE", "http://localhost:8088/v1")
OMLX_KEY  = os.environ.get("OMLX_API_KEY", "")
MAX_DIFF_CHARS = int(os.environ.get("MAX_DIFF_CHARS", "40000"))  # 本地上下文有限,先粗暴截断(TODO:按 token 分块)
MAX_INLINE = int(os.environ.get("MAX_INLINE", "10"))  # 每个 PR 最多发几条 inline(降噪,防刷屏)
SEV_RANK = {"critical": 0, "major": 1, "minor": 2, "nit": 3}
# 生成/机械文件:这些上的非 critical 问题基本是噪声(ABI/lock/min/生成目录),docs/consistency 尤其爱在这刷屏
SKIP_PATHS = re.compile(r"(\.abi\.json|/abi/|abi\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|"
                        r"\.min\.|/generated/|/dist/|/build/|/vendor/|\.lock$|\.svg$|\.snap$)", re.I)

# 每个 lens:聚焦点 + 严重度指引。security 含 Web3 专项。输出统一 JSON schema。
LENSES = {
    "security": "安全审查(只看安全):OWASP(注入/越权/密钥硬编码/加密误用/SSRF)+ Web3/Solidity 专项"
                "(重入、签名重放/EIP-712 domain、Paymaster gas griefing、access control、unchecked call、"
                "整数与精度、EIP-7702 相关)。只报高置信度。",
    "testing":  "测试完备性(只看测试):改动的函数/分支是否有对应单测/E2E;缺失则指出该补哪类测试。"
                "纯文档/格式/配置改动不要求测试。",
    "docs":     "文档/注释同步(只看文档):改了公共签名/接口/CLI/路由/ABI 而文档或 doc 注释没同步则报;"
                "明显与代码矛盾的注释也报。纯内部重构不要求。",
    "consistency": "代码库一致性(只看一致性):命名/目录组织/错误处理/API 设计/导入风格是否沿用既有约定。"
                   "【不要】报安全/密钥/SQL注入/测试/文档问题——那些不属于一致性维度。",
}

SCHEMA_HINT = (
    '只输出一个 JSON 对象,不要任何解释或 markdown 代码围栏。格式:\n'
    '{"lens":"<名>","verdict":"APPROVE|REQUEST_CHANGES","summary":"<2-3句>",'
    '"findings":[{"severity":"critical|major|minor|nit","path":"<相对路径>","line":<新文件行号或null>,'
    '"description":"<问题>","suggestion":"<改法>"}]}\n'
    '只报高置信度问题;不确定就不报。findings 可为空数组。'
)


_STOP = set("the a an is are be to of in on for and or with without due using use code source which "
            "both critical major minor issue issues should must this that it its present used vulnerable "
            "vulnerability via from into not no key".split())


def _sig(desc):
    """从描述里抽显著关键词集合,用于跨 lens 语义去重。"""
    return {w for w in re.findall(r"[a-z0-9]+", (desc or "").lower()) if len(w) > 3 and w not in _STOP}


def omlx_chat(system, user, model, max_tokens=2000):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": 0, "max_tokens": max_tokens, "stream": False,
    }).encode()
    req = urllib.request.Request(OMLX_BASE + "/chat/completions", data=body,
                                 headers={"Authorization": "Bearer " + OMLX_KEY, "Content-Type": "application/json"})
    # 绕过系统代理(localhost 直连,避免 Clash 7890 吞请求)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=600) as r:
        return json.load(r)["choices"][0]["message"]["content"]


def parse_json(text):
    """模型可能裹 ```json 围栏或带前后废话,尽量抠出第一个 JSON 对象。"""
    text = re.sub(r"^```(?:json)?|```$", "", text.strip(), flags=re.M).strip()
    try:
        return json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text, re.S)
        if m:
            try:
                return json.loads(m.group(0))
            except Exception:
                pass
    return {"lens": "?", "verdict": "?", "summary": "(模型未返回合法JSON)", "findings": [], "_raw": text[:500]}


def run_lens(key, diff, evidence, model):
    scope = ("⚠️ 你只负责【%s】这一个维度。**本维度之外的问题——尤其是其它审查器负责的:"
             "安全漏洞→由 security 负责、测试→testing、文档→docs、一致性→consistency——"
             "即使你看到了也【绝对不要】报告**,会被判为越界/噪声。"
             "若本次改动与【%s】无关,findings 直接返回空数组 []。") % (key, key)
    system = (f"你是严格的代码审查器,专职【{key}】维度。\n{LENSES[key]}\n{scope}\n"
              f"绝不修改代码,只给建议。\n{SCHEMA_HINT}")
    user = f"[确定性证据(Semgrep/Slither,可能为空)]\n{evidence or '(无)'}\n\n[PR diff]\n{diff}"
    raw = omlx_chat(system, user, model)
    obj = parse_json(raw)
    obj["lens"] = key
    return obj


def valid_diff_lines(diff):
    """解析 unified diff,收集每个文件新侧可评论的行号(用于 inline 校验)。"""
    valid = {}
    path = None
    newln = 0
    for ln in diff.splitlines():
        if ln.startswith("+++ b/"):
            path = ln[6:]; valid.setdefault(path, set())
        elif ln.startswith("@@"):
            m = re.search(r"\+(\d+)", ln)
            newln = int(m.group(1)) if m else 0
        elif path and ln.startswith("+") and not ln.startswith("+++"):
            valid[path].add(newln); newln += 1
        elif path and ln.startswith(" "):
            valid[path].add(newln); newln += 1
        elif path and ln.startswith("-"):
            pass
    return valid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo"); ap.add_argument("--pr", type=int)
    ap.add_argument("--diff-file"); ap.add_argument("--evidence-file")
    ap.add_argument("--model", default="omlx/Qwen2.5-Coder-32B-Instruct-MLX-8bit")
    ap.add_argument("--lenses", default="security,testing,docs,consistency")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--note", default="", help="在评论顶部加一行说明(如:测试)")
    a = ap.parse_args()
    model = a.model.split("/", 1)[-1]  # omlx 端只要模型名

    if a.diff_file:
        diff = open(a.diff_file).read()
    elif a.repo and a.pr:
        diff = subprocess.run(["gh", "pr", "diff", str(a.pr), "--repo", a.repo],
                              capture_output=True, text=True).stdout
    else:
        sys.exit("需要 --repo+--pr 或 --diff-file")

    if not diff.strip():
        sys.exit("空 diff(或 gh 取 diff 失败/被代理 reset)")
    truncated = len(diff) > MAX_DIFF_CHARS
    if truncated:
        diff = diff[:MAX_DIFF_CHARS]
    evidence = open(a.evidence_file).read() if a.evidence_file and os.path.exists(a.evidence_file) else ""

    reports = []
    for key in [x.strip() for x in a.lenses.split(",") if x.strip()]:
        print(f"  [lens] {key} … ", end="", flush=True)
        try:
            rep = run_lens(key, diff, evidence, model)
            print(f"{len(rep.get('findings', []))} findings, verdict={rep.get('verdict')}")
            reports.append(rep)
        except Exception as e:
            print(f"失败: {e}")

    # 聚合 + 语义去重:同文件、描述关键词高度重叠的 finding 跨 lens 合并(防小模型串味刷屏)。
    raw_f = [{**f, "lens": r["lens"]} for r in reports for f in r.get("findings", [])]
    all_f = []
    for f in raw_f:
        s = _sig(f.get("description"))
        hit = next((g for g in all_f if g.get("path") == f.get("path") and s and g["_sig"]
                    and len(s & g["_sig"]) / max(1, len(s | g["_sig"])) >= 0.4), None)
        if hit:
            if f["lens"] not in hit["lens"].split("+"):
                hit["lens"] += "+" + f["lens"]
            continue
        all_f.append({**f, "_sig": s})
    # ── 降噪(C):① 机械/生成文件上的非 critical 丢弃 ② 按严重度排序 ③ inline 只发 major+ 且封顶 MAX_INLINE ──
    def _kept(f):
        return not (f.get("path") and SKIP_PATHS.search(f["path"]) and f.get("severity") != "critical")
    dropped_noise = [f for f in all_f if not _kept(f)]
    kept = sorted([f for f in all_f if _kept(f)], key=lambda f: SEV_RANK.get(f.get("severity"), 2))
    inline_pool = [f for f in kept if f.get("severity") in ("critical", "major")][:MAX_INLINE]

    body = ["## 🤖 Power-Reviewer 本地审查 (Qwen2.5-Coder via omlx, 直评模式)\n"]
    if a.note:
        body.append(f"> {a.note}\n")
    if truncated:
        body.append("> ⚠️ diff 过大已截断,仅审查前部分(TODO: token 分块)。\n")
    for r in reports:
        body.append(f"- **{r['lens']}**: {r.get('verdict','?')} — {r.get('summary','').strip()}")
    note = f"({len(kept)} 条" + (f";已过滤 {len(dropped_noise)} 条生成/机械文件噪声" if dropped_noise else "") + ")"
    body.append(f"\n### Findings {note}")
    if not kept:
        body.append("未发现高置信度问题 ✅")
    for f in kept:
        loc = f.get("path", "?") + (f":{f['line']}" if f.get("line") else "")
        body.append(f"- **[{f.get('severity','?')}|{f['lens']}]** `{loc}` — {f.get('description','')}\n"
                    f"  - 建议: {f.get('suggestion','')}")
    review_body = "\n".join(body)

    if a.dry_run or not (a.repo and a.pr):
        print("\n" + "=" * 60 + "\n" + review_body)
        print(f"\n[降噪] 保留 {len(kept)} 条 | inline {len(inline_pool)}/{MAX_INLINE} | 过滤噪声 {len(dropped_noise)}")
        return

    # 发 inline review:只发 inline_pool(major+, 封顶)且行号在 diff 内的;其余在汇总 body 里。event=COMMENT。
    valid = valid_diff_lines(diff)
    comments = []
    for f in inline_pool:
        p, l = f.get("path"), f.get("line")
        if p and l and l in valid.get(p, set()):
            comments.append({"path": p, "line": l, "side": "RIGHT",
                             "body": f"**[{f.get('severity','?')}|{f['lens']}]** {f.get('description','')}\n\n"
                                     f"**建议:** {f.get('suggestion','')}"})
    payload = {"event": "COMMENT", "body": review_body, "comments": comments}
    proc = subprocess.run(["gh", "api", "--method", "POST",
                           f"/repos/{a.repo}/pulls/{a.pr}/reviews", "--input", "-"],
                          input=json.dumps(payload), capture_output=True, text=True)
    if proc.returncode == 0:
        print(f"\n✅ 已发评论到 {a.repo}#{a.pr}({len(comments)} 条 inline + 汇总,过滤噪声 {len(dropped_noise)})")
    else:
        print(f"\n⚠️ 发评论失败(可能 422 行号越界): {proc.stderr[:300]}\n回退:请看 body-only。")


if __name__ == "__main__":
    main()
