.PHONY: help build test push clean lint

# Default target
.DEFAULT_GOAL := help

# Variables
IMAGE_NAME := cf-xray
REGISTRY := ghcr.io
REPO := yourusername/cf-xray

# Read versions from upstream-ver.ini (robust parsing with -F'=' separator)
XRAY_VERSION := $(shell awk -F'=' '/\[xray-core\]/{f=1} f && $$1=="version"{gsub(/^[ \t]+|[ \t]+$$/,"",$$2); print $$2; exit}' upstream-ver.ini)
CLOUDFLARED_VERSION := $(shell awk -F'=' '/\[cloudflared\]/{f=1} f && $$1=="version"{gsub(/^[ \t]+|[ \t]+$$/,"",$$2); print $$2; exit}' upstream-ver.ini)
VERSION := v$(XRAY_VERSION)

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build Docker image for linux/amd64
	docker build \
		--build-arg XRAY_VERSION=$(XRAY_VERSION) \
		--build-arg CLOUDFLARED_VERSION=$(CLOUDFLARED_VERSION) \
		-t $(IMAGE_NAME):local .

test: build ## Test Docker image
	@echo "Testing configuration template..."
	@./scripts/test-config.sh
	@echo "Testing Docker image..."
	@docker run --rm \
		-e TUNNEL_TOKEN="test_token" \
		-e VLESS_UUID="12345678-1234-1234-1234-123456789abc" \
		-e DOMAIN="test.example.com" \
		$(IMAGE_NAME):local \
		xray version

lint: ## Lint Dockerfile
	@echo "Linting Dockerfile..."
	@docker run --rm -i hadolint/hadolint < Dockerfile || true

push: ## Push image to registry
	docker tag $(IMAGE_NAME):local $(REGISTRY)/$(REPO):latest
	docker push $(REGISTRY)/$(REPO):latest
	docker tag $(IMAGE_NAME):local $(REGISTRY)/$(REPO):$(VERSION)
	docker push $(REGISTRY)/$(REPO):$(VERSION)

clean: ## Remove built images
	docker rmi $(IMAGE_NAME):local 2>/dev/null || true
	docker system prune -f

run: ## Run container locally
	@echo "Starting container..."
	@docker run -d \
		--name $(IMAGE_NAME) \
		--rm \
		-e TUNNEL_TOKEN="$(TUNNEL_TOKEN)" \
		-e VLESS_UUID="$(VLESS_UUID)" \
		-e DOMAIN="$(DOMAIN)" \
		-p 10000:10000 \
		-p 8080:8080 \
		$(IMAGE_NAME):local

logs: ## Show container logs
	docker logs -f $(IMAGE_NAME)

stop: ## Stop running container
	docker stop $(IMAGE_NAME) || true

shell: ## Enter container shell
	docker exec -it $(IMAGE_NAME) sh

validate-config: ## Validate Xray configuration
	@docker run --rm \
		-e TUNNEL_TOKEN="test" \
		-e VLESS_UUID="12345678-1234-1234-1234-123456789abc" \
		-e DOMAIN="test.example.com" \
		$(IMAGE_NAME):local \
		xray -test -config /etc/xray/config.json
