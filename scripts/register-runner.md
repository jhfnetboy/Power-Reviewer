# 把这台 Mac 注册成 GitHub self-hosted runner

目的:让 GitHub Actions 把"本地模型 review" job 派发到这台 Mac(它能访问 localhost 的 Ollama/LiteLLM)。
公开仓库自托管 runner **免费**;私有仓注意 2026 计费变动(已推迟,留意官方最新口径)。

## 步骤(仓库级 runner)

1. GitHub 仓库 → **Settings → Actions → Runners → New self-hosted runner → macOS**。
2. 按页面给出的命令下载并配置(示例,以页面实际 token 为准):
   ```bash
   mkdir -p ~/actions-runner && cd ~/actions-runner
   # 下载 + 解压(版本以页面为准)
   ./config.sh --url https://github.com/<owner>/<repo> --token <REGISTRATION_TOKEN> \
     --labels power-reviewer,macos --name mac-power-reviewer
   ```
   > `--labels` 必须包含 `power-reviewer`,与 `review.yml` 里 `runs-on: [self-hosted, macos, power-reviewer]` 对应。
3. 常驻运行(随开机启动):
   ```bash
   ./svc.sh install
   ./svc.sh start
   ```
4. 多个仓库共用:用 **organization 级 runner**(Org Settings → Actions → Runners),省得每仓注册。

## 24/7 注意

- Mac 别休眠:`sudo pmset -a sleep 0 disablesleep 1`(或"防止自动进入睡眠")。
- 先确保本地服务常驻:`ollama serve` + `litellm --config orchestrator/litellm.config.yaml --port 4000`(可用 launchd 或 pm2 守护)。
- 代理:若用 Clash(7890),确认 runner 进程的 `HTTPS_PROXY`/`NO_PROXY` 设置不影响连 GitHub 与本地 localhost。
