#!/usr/bin/env bash
# 手动前台跑 Power-Reviewer(适合先挂几天观察)。配置全从 .env 读。
# 多日挂着建议放 tmux/screen,免得关终端就停:
#   tmux new -s pr 'bash run.sh'        # 进会话跑;detach: Ctrl-b d;回来: tmux attach -t pr
# 或后台 + 日志:
#   nohup bash run.sh > /tmp/reviewerd.out.log 2>&1 &   ; tail -f /tmp/reviewerd.out.log
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "❌ 缺 .env。先:cp .env.example .env 并填好 OMLX_API_KEY"; exit 1; }
set -a; . ./.env; set +a              # 读入并导出所有变量(reviewerd + direct_review 都用)

echo "▶ Power-Reviewer 启动"
echo "  模型: ${REVIEW_MODEL}  | DRY_RUN=${DRY_RUN}  | 间隔=${POLL_INTERVAL}s  | 每轮上限=${MAX_REVIEWS_PER_CYCLE}"
echo "  范围: ${ORGS_CONF}"
[ "${DRY_RUN:-1}" = "0" ] && echo "  ⚠️ DRY_RUN=0 —— 会真发评论到 GitHub!" || echo "  (DRY_RUN=1:只审不发)"
echo ""
exec bash daemon/reviewerd.sh
