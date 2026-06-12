# agent-run: 通用 Agent 运行时镜像
# Base: Node 24 LTS + Debian 13 (trixie) slim
# 注意:不要换成 alpine(musl libc 与部分 npm 原生包不兼容)
ARG BASE=node:24-trixie-slim
FROM ${BASE}

# Agent CLI 版本由 CI 解析后注入,本地构建可手动指定
ARG CLAUDE_CODE_VERSION=latest
ARG CODEX_VERSION=latest

# ---- 系统工具层(变动少,放前面利用缓存) ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client ca-certificates \
    curl wget jq less procps tmux vim \
    ripgrep fd-find \
    build-essential \
    python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf "$(command -v fdfind)" /usr/local/bin/fd

# ---- uv:Python 版本/venv 由 agent 按需自助管理 ----
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# ---- Agent CLI 层(钉版本,保证镜像可复现) ----
RUN npm install -g \
    "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force

# 镜像即版本:关闭 CLI 自更新,升级统一走镜像重建
ENV DISABLE_AUTOUPDATER=1

# ---- API 配置层:第三方兼容 host 为默认姿态 ----
#
# Claude Code(环境变量驱动,容器 -e 注入即可):
#   ANTHROPIC_API_KEY              必填
#   ANTHROPIC_BASE_URL             API 端点,不设则走官方默认
#   ANTHROPIC_MODEL                模型 ID,覆盖 CLI 默认模型
#   ANTHROPIC_DEFAULT_OPUS_MODEL   可选,Opus 类模型默认值
#   ANTHROPIC_DEFAULT_SONNET_MODEL 可选,Sonnet 类模型默认值
#   ANTHROPIC_DEFAULT_HAIKU_MODEL  可选,Haiku 类模型默认值
#
# Codex(config.toml 驱动,非环境变量):
#   OPENAI_API_KEY                 API 密钥(OpenAI SDK 标准变量)
#   模型 / provider / base_url    → ~/.codex/config.toml 或 --model / -c flag
#   容器启动时挂载自定义 config.toml 到 /home/agent/.codex/config.toml
#
# 不在此处 ENV 赋空值:部分 CLI 区分"未设"与"空字符串",赋空反而报错。

# 版本信息写入 label,便于追溯
LABEL agent.claude-code.version="${CLAUDE_CODE_VERSION}" \
      agent.codex.version="${CODEX_VERSION}"

# ---- 非 root 运行 ----
RUN useradd -m -s /bin/bash agent
USER agent
WORKDIR /workspace

CMD ["sleep", "infinity"]
