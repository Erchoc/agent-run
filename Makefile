# agent-env Makefile
# make help      查看所有命令

-include .env

IMAGE         ?= agent-env
TAG           ?= dev
CC_VERSION    ?= $(shell npm view @anthropic-ai/claude-code version 2>/dev/null || echo latest)
CX_VERSION    ?= $(shell npm view @openai/codex version 2>/dev/null || echo latest)
ACR           ?= crpi-qiclkwmeg0rcfork.cn-hangzhou.personal.cr.aliyuncs.com
NS            ?= dfctl
FULL_IMAGE     = $(ACR)/$(NS)/$(IMAGE)

# .env 中读取,也可命令行覆盖: make cc-run API_KEY=sk-xxx
API_KEY       ?=
PROXY         ?=
USER          ?= dev

# 代理 flag
_PROXY_FLAG   := $(if $(PROXY),-x,)
_PROXY_X_FLAG := $(if $(filter-out 127.0.0.1:7890,$(PROXY)),-X $(PROXY),)

.PHONY: help build build-no-cache test run cc-run cx-run push pull versions clean info

help: ## 显示帮助
	@echo "☁  空岛云 · AgentRun"
	@echo "────────────────────────────────────"
	@grep -E '^[a-z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-16s %s\n", $$1, $$2}'
	@echo ""
	@echo "快速测试(配置 .env 后一键启动):"
	@echo "  make cc-run                          # Claude Code + DeepSeek"
	@echo "  make cx-run                          # Codex + DeepSeek"
	@echo "  make cc-run USER=alice ARGS='-r ...'  # 自定义用户 + 额外参数"
	@echo ""
	@echo "构建相关:"
	@echo "  make build                           # 本地构建(自动拉最新版本)"
	@echo "  make build CC_VERSION=2.1.174        # 指定 Claude Code 版本"
	@echo "  make test                            # 冒烟测试本地镜像"
	@echo "  make push TAG=20260612               # 推送到 ACR"
	@echo ""
	@echo "配置: 复制 .env.example 为 .env 填入 API_KEY"

build: ## 本地构建镜像
	docker build \
	  --build-arg CLAUDE_CODE_VERSION=$(CC_VERSION) \
	  --build-arg CODEX_VERSION=$(CX_VERSION) \
	  -t $(IMAGE):$(TAG) .
	@echo ""
	@echo "构建完成: $(IMAGE):$(TAG)"
	@echo "  claude-code: $(CC_VERSION)"
	@echo "  codex:       $(CX_VERSION)"

build-no-cache: ## 无缓存构建
	docker build --no-cache \
	  --build-arg CLAUDE_CODE_VERSION=$(CC_VERSION) \
	  --build-arg CODEX_VERSION=$(CX_VERSION) \
	  -t $(IMAGE):$(TAG) .

test: ## 冒烟测试本地镜像
	bash scripts/smoke-test.sh $(IMAGE):$(TAG)

run: ## 自由启动(ARGS 传参)
	bash scripts/run.sh $(ARGS)

cc-run: _check-key ## Claude Code + DeepSeek 一键启动
	bash scripts/run.sh -a claude -u $(USER) -p \
	  -b https://api.deepseek.com/anthropic \
	  -k $(API_KEY) $(_PROXY_FLAG) $(_PROXY_X_FLAG) $(ARGS)

cx-run: _check-key ## Codex + DeepSeek 一键启动
	bash scripts/run.sh -a codex -u $(USER) -p \
	  -b https://api.deepseek.com/v1 \
	  -k $(API_KEY) \
	  -m deepseek-chat $(_PROXY_FLAG) $(_PROXY_X_FLAG) $(ARGS)

push: ## 推送到 ACR
	docker tag $(IMAGE):$(TAG) $(FULL_IMAGE):$(TAG)
	docker tag $(IMAGE):$(TAG) $(FULL_IMAGE):latest
	docker push $(FULL_IMAGE):$(TAG)
	docker push $(FULL_IMAGE):latest
	@echo "已推送: $(FULL_IMAGE):$(TAG) + :latest"

pull: ## 从 ACR 拉取最新
	docker pull $(FULL_IMAGE):latest

versions: ## 查看最新 CLI 版本
	@echo "claude-code: $(CC_VERSION)"
	@echo "codex:       $(CX_VERSION)"

info: ## 查看本地镜像信息
	@docker images $(IMAGE):$(TAG) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" 2>/dev/null || echo "镜像不存在,先 make build"
	@echo ""
	@docker inspect $(IMAGE):$(TAG) --format '  claude-code: {{index .Config.Labels "agent.claude-code.version"}}' 2>/dev/null || true
	@docker inspect $(IMAGE):$(TAG) --format '  codex:       {{index .Config.Labels "agent.codex.version"}}' 2>/dev/null || true

clean: ## 删除本地镜像
	docker rmi $(IMAGE):$(TAG) 2>/dev/null || true
	@echo "已清理: $(IMAGE):$(TAG)"

_check-key:
	@test -n "$(API_KEY)" || { echo "错误: 未配置 API_KEY,请创建 .env 文件或传参 make cc-run API_KEY=sk-xxx"; exit 1; }
