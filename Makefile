.PHONY: init check security-audit up down logs generate rotate verify test-integration test-smoke

init:
	./scripts/init-local-config.sh

check:
	./scripts/check-repository.sh

security-audit:
	./scripts/security-audit.sh

up:
	docker compose --env-file .env up -d

down:
	docker compose --env-file .env down

logs:
	docker compose --env-file .env logs -f fluent-bit

generate:
	./scripts/generate-sample-logs.sh

rotate:
	./scripts/rotate-sample-log.sh

verify:
	./scripts/verify-objective-1.sh

test-integration:
	./tests/integration/run.sh

test-smoke:
	./tests/integration/smoke-production.sh
