#!/usr/bin/env bash
# 把 reviewerd 装成 launchd 常驻服务(开机自启、崩溃自重启)。默认 DRY_RUN=1(只审不发)。
# 用法:  OMLX_API_KEY=你的key bash scripts/install-service.sh
set -euo pipefail
: "${OMLX_API_KEY:?请先 export OMLX_API_KEY=...(不会写进仓库,只注入本地 plist)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/deploy/com.power-reviewer.reviewerd.plist"
DST="$HOME/Library/LaunchAgents/com.power-reviewer.reviewerd.plist"

# 注入 key,并把 reviewerd 路径校正为本机实际路径
sed -e "s#__SET_OMLX_API_KEY__#${OMLX_API_KEY}#" \
    -e "s#/Users/jason/Dev/tools/Power-Reviewer#${ROOT}#g" "$SRC" > "$DST"

launchctl unload "$DST" 2>/dev/null || true
launchctl load -w "$DST"

cat <<EOF
✅ 常驻服务已安装并启动(DRY_RUN=1:只发现+审查,不发评论)
   看日志:   tail -f /tmp/reviewerd.out.log
   转真发:   编辑 $DST,把 DRY_RUN 的 1 改成 0,然后:
              launchctl unload "$DST" && launchctl load -w "$DST"
   停止:     launchctl unload "$DST"
   说明:     模型=Qwen3-Coder-30B-A3B;范围=prbot 的 3 个 org;PR 优先,P2 巡检空闲跑。
EOF
