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

# 版本信息写入 label,便于追溯
LABEL agent.claude-code.version="${CLAUDE_CODE_VERSION}" \
      agent.codex.version="${CODEX_VERSION}"

# ---- 非 root 运行 ----
RUN useradd -m -s /bin/bash agent
USER agent
WORKDIR /workspace

CMD ["sleep", "infinity"]
