#!/usr/bin/env bash
# 常驻 24h 调度器:发现 → 按优先级 → 去重 → 派 opencode 审查(只评论)→ 记状态 →(限流)升级深审。
# 起停:launchctl(见 deploy/com.power-reviewer.reviewerd.plist),或前台 `bash daemon/reviewerd.sh`。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/config.env"
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"   # 坑#7:别让代理吞本地 omlx 请求

mkdir -p "$STATE_DIR"
SEEN="$STATE_DIR/seen.tsv"          # repo<TAB>num<TAB>head:已审过的 PR commit,去重防刷屏
ESC_LOG="$STATE_DIR/escalations.$(date +%Y%m%d)"     # 当日升级计数
touch "$SEEN"

log(){ printf '%s %s\n' "$(date '+%F %T')" "$*"; }
reviewed(){ grep -qF "$(printf '%s\t%s\t%s' "$1" "$2" "$3")" "$SEEN"; }
mark(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$SEEN"; }
esc_count(){ [[ -f "$ESC_LOG" ]] && wc -l < "$ESC_LOG" | tr -d ' ' || echo 0; }

# 本地多维度审查(只评论,绝不改代码)
review_pr(){ # repo num
  local repo="$1" num="$2"
  log "  → 直评 $repo#$num (Qwen2.5-Coder via omlx, 非agentic)"
  # 路径2:直评。不用 opencode agentic(本地模型 tool-call omlx 解析不了),纯 chat completion。
  OMLX_API_KEY="${OMLX_API_KEY:-}" OMLX_BASE="${OMLX_BASE:-http://localhost:8088/v1}" \
    python3 "$REPO_ROOT/review/direct_review.py" --repo "$repo" --pr "$num" \
      --model "$REVIEW_MODEL" --lenses "$REVIEW_LENSES" ${DRY_RUN:+--dry-run}
}

# 升级深审:仅高价值/被本地标 critical 的 PR,且当日未超配额。官方 CLI,合规。
escalate_pr(){ # repo num
  local repo="$1" num="$2"
  if (( $(esc_count) >= ESCALATE_DAILY_CAP )); then log "  ⚠ 升级配额已满($ESCALATE_DAILY_CAP/日),跳过深审"; return 0; fi
  log "  ↑ 升级深审 $repo#$num via $ESCALATE_CLI(官方 CLI,计入当日配额)"
  # TODO: $ESCALATE_CLI -p "深审 $repo#$num 的安全与业务一致性,给建议不改代码"
  echo "$repo#$num" >> "$ESC_LOG"
}

run_once(){
  local items; items="$("$HERE/discover.sh" 2>/dev/null)" || { log "discover 失败"; return 1; }

  # ── P0:PR 审查(去重:同 head SHA 不重审)──
  local p0; p0="$(jq -c 'select(.prio=="P0" and .num!=null)' <<<"$items")"
  while IFS= read -r it; do
    [[ -z "$it" ]] && continue
    local repo num sha; repo=$(jq -r .repo <<<"$it"); num=$(jq -r .num <<<"$it"); sha=$(jq -r .head <<<"$it")
    if reviewed "$repo" "$num" "$sha"; then log "skip(已审) $repo#$num@${sha:0:7}"; continue; fi
    review_pr "$repo" "$num" && mark "$repo" "$num" "$sha"
    # escalate_pr "$repo" "$num"   # ← 接好本地审查、能判定 severity 后再开
  done <<< "$p0"

  # ── P2:背景巡检(长线、低优先、空闲填充;每轮只推进 $SWEEP_PER_CYCLE 个)──
  # TODO: 文档完整性/文档一致性/整仓代码质量评估。维护 $STATE_DIR/sweep-ledger 轮转,避免重复扫同一处。
  log "P0 处理完。背景巡检(P2)待实现。"
}

log "reviewerd 启动 | 间隔=${POLL_INTERVAL}s | orgs=${ORGS_CONF}"
while true; do
  run_once || log "本轮出错(忽略,继续)"
  sleep "$POLL_INTERVAL"
done
