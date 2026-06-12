# agent-env Makefile
# make build     本地构建镜像
# make run       快速启动(等同 ./scripts/run.sh)
# make test      冒烟测试
# make push      推送到 ACR
# make versions  查看最新 CLI 版本
# make help      查看所有命令

IMAGE         ?= agent-env
TAG           ?= dev
CC_VERSION    ?= $(shell npm view @anthropic-ai/claude-code version 2>/dev/null || echo latest)
CX_VERSION    ?= $(shell npm view @openai/codex version 2>/dev/null || echo latest)
ACR           ?= crpi-qiclkwmeg0rcfork.cn-hangzhou.personal.cr.aliyuncs.com
NS            ?= dfctl
FULL_IMAGE     = $(ACR)/$(NS)/$(IMAGE)

.PHONY: help build build-no-cache test run push pull versions clean info

help: ## 显示帮助
	@echo "☁  空岛云 · AgentRun"
	@echo "────────────────────────────────────"
	@grep -E '^[a-z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-16s %s\n", $$1, $$2}'
	@echo ""
	@echo "变量覆盖:"
	@echo "  CC_VERSION=x.x.x   指定 Claude Code 版本"
	@echo "  CX_VERSION=x.x.x   指定 Codex 版本"
	@echo "  TAG=xxx             镜像 tag (默认 dev)"
	@echo ""
	@echo "示例:"
	@echo "  make build                           # 构建本地镜像(自动拉最新版本)"
	@echo "  make build CC_VERSION=2.1.174        # 指定 Claude Code 版本"
	@echo "  make test                            # 冒烟测试本地镜像"
	@echo "  make run                             # 最简启动"
	@echo "  make run ARGS='-u alice -x -p'       # 带参数启动"
	@echo "  make push TAG=20260612               # 推送到 ACR"

build: ## 本地构建镜像
	docker build \
	  --build-arg CLAUDE_CODE_VERSION=$(CC_VERSION) \
	  --build-arg CODEX_VERSION=$(CX_VERSION) \
	  -t $(IMAGE):$(TAG) .
	@echo ""
	@echo "构建完成: $(IMAGE):$(TAG)"
	@echo "  claude-code: $(CC_VERSION)"
	@echo "  codex:       $(CX_VERSION)"

build-no-cache: ## 无缓存构建(全量重建)
	docker build --no-cache \
	  --build-arg CLAUDE_CODE_VERSION=$(CC_VERSION) \
	  --build-arg CODEX_VERSION=$(CX_VERSION) \
	  -t $(IMAGE):$(TAG) .

test: ## 冒烟测试本地镜像
	bash scripts/smoke-test.sh $(IMAGE):$(TAG)

run: ## 启动容器(通过 run.sh,用 ARGS 传参)
	bash scripts/run.sh $(ARGS)

push: ## 推送到 ACR(需先 docker login)
	docker tag $(IMAGE):$(TAG) $(FULL_IMAGE):$(TAG)
	docker tag $(IMAGE):$(TAG) $(FULL_IMAGE):latest
	docker push $(FULL_IMAGE):$(TAG)
	docker push $(FULL_IMAGE):latest
	@echo "已推送: $(FULL_IMAGE):$(TAG) + :latest"

pull: ## 从 ACR 拉取最新镜像
	docker pull $(FULL_IMAGE):latest

versions: ## 查看最新 CLI 版本
	@echo "claude-code: $(CC_VERSION)"
	@echo "codex:       $(CX_VERSION)"

info: ## 查看本地镜像信息
	@docker images $(IMAGE):$(TAG) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" 2>/dev/null || echo "镜像不存在,先 make build"
	@echo ""
	@docker inspect $(IMAGE):$(TAG) --format '  claude-code: {{index .Config.Labels "agent.claude-code.version"}}' 2>/dev/null || true
	@docker inspect $(IMAGE):$(TAG) --format '  codex:       {{index .Config.Labels "agent.codex.version"}}' 2>/dev/null || true

clean: ## 删除本地构建的镜像
	docker rmi $(IMAGE):$(TAG) 2>/dev/null || true
	@echo "已清理: $(IMAGE):$(TAG)"
