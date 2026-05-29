#!/usr/bin/env bash
# 常驻 24h 调度器:发现 → 按优先级 → 去重 → 派 opencode 审查(只评论)→ 记状态 →(限流)升级深审。
# 起停:launchctl(见 deploy/com.power-reviewer.reviewerd.plist),或前台 `bash daemon/reviewerd.sh`。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
# 配置优先读仓库根 .env(单一真相源);没有则回退 daemon/config.env
# shellcheck disable=SC1091
if [ -f "$REPO_ROOT/.env" ]; then set -a; . "$REPO_ROOT/.env"; set +a
else . "$HERE/config.env"; fi
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
  log "  → 直评 $repo#$num (${REVIEW_MODEL##*/} via omlx, 非agentic)"
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
  log "🔍 发现工作项中…(gh search 走代理可能慢/需重试 + 枚举 org 仓,请耐心 ~10-60s)"
  local items; items="$("$HERE/discover.sh" 2>/dev/null)" || { log "discover 失败(代理?下轮重试)"; return 1; }
  local n0 n2
  n0=$(jq -c 'select(.prio=="P0" and .num!=null)' <<<"$items" 2>/dev/null | grep -c . || true)
  n2=$(jq -c 'select(.prio=="P2")'                <<<"$items" 2>/dev/null | grep -c . || true)
  log "📋 发现 P0 待审 PR=${n0:-0} | P2 巡检仓=${n2:-0}"

  # ── P0:PR 审查。去重(同 head SHA 不重审)+ 每轮上限(防第一轮 marathon)──
  local cap="${MAX_REVIEWS_PER_CYCLE:-3}" done=0 skipped=0
  while IFS= read -r it; do
    [[ -z "$it" ]] && continue
    local repo num sha; repo=$(jq -r .repo <<<"$it"); num=$(jq -r .num <<<"$it"); sha=$(jq -r .head <<<"$it")
    reviewed "$repo" "$num" "$sha" && { skipped=$((skipped+1)); continue; }
    if [[ "$done" -ge "$cap" ]]; then log "⏸ 本轮已审 $cap 个(上限 MAX_REVIEWS_PER_CYCLE),其余下轮继续"; break; fi
    done=$((done+1)); log "[$done/$cap] 开始审 $repo#$num@${sha:0:7}"
    review_pr "$repo" "$num" && mark "$repo" "$num" "$sha"
    # escalate_pr "$repo" "$num"   # ← 接好 severity 判定后再开
  done <<< "$(jq -c 'select(.prio=="P0" and .num!=null)' <<<"$items")"

  # P2 背景巡检(文档完整性/一致性/质量)待实现:维护 sweep-ledger 轮转。
  log "✅ 本轮完成:新审 $done 个,跳过(已审)$skipped 个。💤 睡 ${POLL_INTERVAL}s"
}

log "reviewerd 启动 | 间隔=${POLL_INTERVAL}s | orgs=${ORGS_CONF}"
while true; do
  run_once || log "本轮出错(忽略,继续)"
  sleep "$POLL_INTERVAL"
done
