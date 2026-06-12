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
# Claude Code — 支持任意 Anthropic API 兼容端点(OpenRouter / 自建网关 / Bedrock 等)
#   ANTHROPIC_API_KEY        必填,运行时 -e 注入
#   ANTHROPIC_BASE_URL       API 端点,不设则 CLI 走官方默认
#   ANTHROPIC_MODEL          模型 ID,覆盖 CLI 默认模型选择
# Codex — 支持任意 OpenAI API 兼容端点
#   OPENAI_API_KEY           必填,运行时 -e 注入
#   OPENAI_BASE_URL          API 端点,不设则 CLI 走官方默认
#   OPENAI_MODEL             模型 ID,覆盖 CLI 默认模型选择
#
# 不在此处 ENV 赋空值:部分 CLI 区分"未设"与"空字符串",赋空反而报错。
# 运行容器时按需 -e 注入即可。

# 版本信息写入 label,便于追溯
LABEL agent.claude-code.version="${CLAUDE_CODE_VERSION}" \
      agent.codex.version="${CODEX_VERSION}"

# ---- 非 root 运行 ----
RUN useradd -m -s /bin/bash agent
USER agent
WORKDIR /workspace

CMD ["sleep", "infinity"]
