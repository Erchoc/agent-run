# agent-run

构建和维护通用 Agent 运行时镜像(Claude Code + Codex + Node.js 24 + Python/uv),通过 GitHub Actions 每周自动跟进 agent CLI 版本,推送至阿里云 ACR,供 Mac Mini 上的 Apple container 消费。

## 架构

```
GitHub Actions (海外, 直连 Docker Hub / npm)
  └─ 每周一自动: 解析最新 CLI 版本 → 构建 arm64 镜像 → 冒烟测试 → 推送 ACR
       └─ registry.cn-hangzhou.aliyuncs.com/dfctl/agent-env:{latest, YYYYMMDD}
            └─ Mac Mini: container pull(ACR 公开仓库, 免登录, 国内高速)
```

CI 在海外构建是关键设计:Docker Hub 和 npm 直连无障碍,彻底绕开国内拉取 Docker Hub 的问题;Mac Mini 只和 ACR 打交道。

## API 配置

### Claude Code(环境变量驱动)

| 变量 | 用途 | 必填 |
|------|------|------|
| `ANTHROPIC_API_KEY` | API 密钥 | 是 |
| `ANTHROPIC_BASE_URL` | API 端点(第三方网关 / OpenRouter 等),不设则走官方 | 否 |
| `ANTHROPIC_MODEL` | 模型 ID,覆盖 CLI 默认模型 | 否 |

还有三个细粒度覆盖变量(按模型族分别指定):
`ANTHROPIC_DEFAULT_OPUS_MODEL`、`ANTHROPIC_DEFAULT_SONNET_MODEL`、`ANTHROPIC_DEFAULT_HAIKU_MODEL`

```bash
# Claude Code 使用第三方兼容端点
docker run --rm \
  -e ANTHROPIC_API_KEY=sk-xxx \
  -e ANTHROPIC_BASE_URL=https://your-gateway.example.com/v1 \
  -e ANTHROPIC_MODEL=claude-sonnet-4-6 \
  agent-env:latest claude -p "hello"
```

### Codex(config.toml + flag 驱动)

Codex 不通过环境变量配置 model / base_url,而是用 `~/.codex/config.toml` 或命令行 flag:

| 方式 | 示例 |
|------|------|
| config.toml | `model = "o3"` 写入 `~/.codex/config.toml` |
| 命令行 flag | `codex -m o3` 或 `codex -c 'model="o3"'` |
| API Key | `OPENAI_API_KEY` 环境变量(OpenAI SDK 标准) |

```bash
# Codex 使用自定义模型
docker run --rm \
  -e OPENAI_API_KEY=sk-xxx \
  -v ./codex-config.toml:/home/agent/.codex/config.toml:ro \
  agent-env:latest codex -m o3 -p "hello"
```

## 初始化(一次性)

1. 创建 GitHub 仓库,推入本项目文件。
2. 仓库 Settings → Secrets and variables → Actions,添加:
   - `ACR_USERNAME`:阿里云 ACR 访问凭证用户名
   - `ACR_PASSWORD`:ACR 固定密码(控制台「访问凭证」中设置,非阿里云登录密码)
   - `ACR_REGISTRY`(可选):registry 地址,默认 `registry.cn-hangzhou.aliyuncs.com`(个人版);企业版填 `<实例名>.cn-hangzhou.cr.aliyuncs.com`
   - `ACR_NAMESPACE`(可选):命名空间,默认 `dfctl`
   - `ANTHROPIC_API_KEY`(可选):配置后冒烟测试会做一次真实 API 调用
   - `ANTHROPIC_BASE_URL`(可选):第三方 API 端点,冒烟测试和手动触发均可使用
   - `ANTHROPIC_MODEL`(可选):指定冒烟测试使用的模型
3. 确认 ACR 命名空间为公开(拉取免登录)。
4. 手动触发一次 workflow(Actions → build-agent-image → Run workflow)验证全链路。

## 日常使用

- **自动**:每周一 02:00 UTC 自动重建,跟进 claude-code / codex 最新版。
- **手动指定版本**:Run workflow 时填入 `claude_code_version` / `codex_version`。
- **Mac Mini 侧升级**:

```bash
container pull registry.cn-hangzhou.aliyuncs.com/dfctl/agent-env:latest
# 重建容器即完成升级(工作区在宿主卷上,不丢)
```

- **回滚**:用日期 tag 重启容器即可,如 `agent-env:20260605`。ACR 中保留历史 tag,建议定期清理仅保留最近 4 个。

## 版本策略

- 镜像内 **钉死** agent CLI 版本(build ARG 注入),并设置 `DISABLE_AUTOUPDATER=1` 关闭自更新——"镜像即版本",同一 tag 行为永远一致,升级只走镜像重建。
- 版本写入镜像 label,可用 `container images inspect` 追溯。

## 本地构建(可选)

```bash
docker build \
  --build-arg CLAUDE_CODE_VERSION=$(npm view @anthropic-ai/claude-code version) \
  --build-arg CODEX_VERSION=$(npm view @openai/codex version) \
  -t agent-env:dev .
bash scripts/smoke-test.sh agent-env:dev
```

## 结构

```
agent-run/
├── Dockerfile                      # 镜像定义(node:24-trixie-slim 基底)
├── .github/workflows/build.yml    # 周期构建 + 手动触发
├── scripts/smoke-test.sh          # 推送前冒烟测试
└── README.md
```

## 后续扩展(按需)

- 镜像家族:遇到重依赖需求(如 torch)时从本镜像派生 `agent-ml`,不要预先做。
- 双通道:增加 `:stable` / `:edge` 两条 tag 线,生产 agent 固定 stable。
- 私有仓库注意:`ubuntu-24.04-arm` runner 若不可用,workflow 中改回 `ubuntu-latest` 并启用 QEMU 步骤。
