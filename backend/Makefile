# Time of Life backend — common commands
.PHONY: build test lint run deploy help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build the Go binary
	go build ./...

test: ## Run all tests (no Docker required)
	go test ./... -cover

lint: ## Run all linters
	gofmt -l .
	go vet ./...
	golangci-lint run

run: ## Run the server locally (needs Postgres via docker-compose)
	go run ./cmd/server

docker-build: ## Build the Docker image
	docker build -t time-of-life-backend .

docker-run: ## Run with docker-compose (local)
	docker compose up -d postgres
	go run ./cmd/server

deploy: ## Deploy to production (requires CI/CD secrets)
	@echo "Deployment is handled by GitHub Actions CI/CD pipeline."
	@echo "Push to main branch to trigger automatic deployment."

# --- Production docker-compose shortcuts ---

prod-up: ## Start production services on the VM
	docker compose -f docker-compose.prod.yml up -d

prod-down: ## Stop production services
	docker compose -f docker-compose.prod.yml down

prod-logs: ## View production logs
	docker compose -f docker-compose.prod.yml logs -f

prod-ps: ## List production services
	docker compose -f docker-compose.prod.yml ps
