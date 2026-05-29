#!/usr/bin/env bash
# Power-Reviewer —— 一次性:fork Kodus 并挂为 submodule(结构①)。
# 前置:① gh 已登录(gh auth login)② 代理/网络可达 GitHub。
set -euo pipefail

FORK_OWNER="${FORK_OWNER:-jhfnetboy}"      # 你的 GitHub 用户名
UPSTREAM="kodustech/kodus-ai"              # Kodus 原仓(上游)
FORK_NAME="${FORK_NAME:-kodus-ai}"         # 你 fork 后的仓名
SUBMOD_PATH="vendor/kodus"

echo "==> 0. 检查 gh 登录状态"
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh 未登录,先跑 gh auth login"; exit 1; }

echo "==> 1. 在你账户下 fork ${UPSTREAM} 为 ${FORK_OWNER}/${FORK_NAME}(已存在则跳过)"
gh repo fork "$UPSTREAM" --fork-name "$FORK_NAME" --clone=false || true

echo "==> 2. 把你的 fork 挂为 submodule 到 ${SUBMOD_PATH}"
if [ ! -e "$SUBMOD_PATH/.git" ]; then
  git submodule add "git@github.com:${FORK_OWNER}/${FORK_NAME}.git" "$SUBMOD_PATH"
fi

echo "==> 3. 在 submodule 内设置 upstream = ${UPSTREAM}"
git -C "$SUBMOD_PATH" remote get-url upstream >/dev/null 2>&1 \
  && git -C "$SUBMOD_PATH" remote set-url upstream "https://github.com/${UPSTREAM}.git" \
  || git -C "$SUBMOD_PATH" remote add upstream "https://github.com/${UPSTREAM}.git"
git -C "$SUBMOD_PATH" fetch upstream

echo "==> 4. 初始化 submodule"
git submodule update --init --recursive

cat <<EOF

✅ 完成。
   submodule: ${SUBMOD_PATH}
     origin   = ${FORK_OWNER}/${FORK_NAME}   (你推 feature 的地方)
     upstream = ${UPSTREAM}                  (拉 Kodus 更新)

同步上游(以后定期做):
   cd ${SUBMOD_PATH} && git fetch upstream && git merge upstream/main && cd -
   git add ${SUBMOD_PATH} && git commit -m "chore: bump kodus submodule"

记得在本仓提交 submodule 引用:
   git add .gitmodules ${SUBMOD_PATH} && git commit -m "chore: add kodus fork as submodule"
EOF
