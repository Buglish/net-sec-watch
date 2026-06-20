.PHONY: init check telemetry-readiness security-audit up up-opensearch up-zeek up-suricata update-suricata-rules down logs logs-opensearch logs-zeek logs-suricata generate rotate verify gen-tls-certs test-integration test-golden test-opensearch test-failover test-telemetry-policy test-smoke

init:
	./scripts/init-local-config.sh

check:
	./scripts/check-repository.sh

telemetry-readiness:
	./scripts/check-telemetry-readiness.sh

security-audit:
	./scripts/security-audit.sh

up:
	docker compose --env-file .env up -d

up-opensearch:
	docker compose --env-file .env --profile opensearch up -d opensearch

up-zeek:
	docker compose --env-file .env --profile zeek up -d

up-suricata:
	docker compose --env-file .env --profile suricata up -d fluent-bit suricata

update-suricata-rules:
	docker compose --env-file .env run --rm suricata-update
	docker compose --env-file .env restart suricata

down:
	docker compose --env-file .env down

logs:
	docker compose --env-file .env logs -f fluent-bit

logs-opensearch:
	docker compose --env-file .env --profile opensearch logs -f opensearch

logs-zeek:
	docker compose --env-file .env --profile zeek logs -f zeek fluent-bit

logs-suricata:
	docker compose --env-file .env --profile suricata logs -f suricata fluent-bit

generate:
	./scripts/generate-sample-logs.sh

rotate:
	./scripts/rotate-sample-log.sh

verify:
	./scripts/verify-objective-1.sh
	./scripts/verify-objective-2.sh

gen-tls-certs:
	./scripts/gen-tls-certs.sh

test-integration:
	./tests/integration/run.sh

test-golden:
	@echo "Golden cases execute as part of make test-integration."
	@python3 tests/golden/verify.py --help >/dev/null

test-opensearch:
	./tests/opensearch/smoke.sh

test-failover:
	./tests/failover/run-failover.sh

test-telemetry-policy:
	./tests/telemetry-policy/run.sh

test-smoke:
	./tests/integration/smoke-production.sh
