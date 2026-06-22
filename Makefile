.PHONY: init check telemetry-readiness security-audit ingestion-status up up-opensearch up-opensearch-secure up-dashboards up-dashboards-secure up-zeek up-suricata update-suricata-rules down down-opensearch-secure logs logs-opensearch logs-dashboards logs-zeek logs-suricata generate rotate verify gen-tls-certs test-integration test-golden test-opensearch test-opensearch-secure test-opensearch-restore test-opensearch-searchability test-opensearch-retention test-opensearch-dashboards test-event-export test-analyst-states measure-opensearch-storage capacity-plan test-capacity-plan test-failover test-telemetry-policy test-smoke

init:
	./scripts/init-local-config.sh

check:
	./scripts/check-repository.sh

telemetry-readiness:
	./scripts/check-telemetry-readiness.sh

security-audit:
	./scripts/security-audit.sh

ingestion-status:
	./scripts/check-ingestion-status.py

up:
	docker compose --env-file .env up -d

up-opensearch:
	docker compose --env-file .env --profile opensearch up -d opensearch

up-opensearch-secure:
	FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.opensearch.conf \
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--profile opensearch up -d opensearch fluent-bit

up-dashboards:
	docker compose --env-file .env --profile opensearch \
		up -d opensearch opensearch-dashboards

up-dashboards-secure:
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--profile opensearch \
		up -d opensearch-dashboards-bootstrap

down-opensearch-secure:
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--profile opensearch down

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

logs-dashboards:
	docker compose --env-file .env --profile opensearch \
		logs -f opensearch-dashboards

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

test-opensearch-secure:
	./tests/opensearch/secure-ingestion.sh

test-opensearch-restore:
	./tests/opensearch/snapshot-restore.sh

test-opensearch-searchability:
	./tests/opensearch/searchability-slo.sh

test-opensearch-retention:
	./tests/opensearch/retention-lifecycle.sh

test-opensearch-dashboards:
	./tests/opensearch/dashboards-smoke.sh

test-event-export:
	./tests/opensearch/export-events.sh

test-analyst-states:
	./tests/opensearch/analyst-states.sh

measure-opensearch-storage:
	./tests/opensearch/storage-expansion.sh

capacity-plan:
	./scripts/calculate-capacity.py

test-capacity-plan:
	python3 ./tests/opensearch/test-capacity-calculator.py

test-failover:
	./tests/failover/run-failover.sh

test-telemetry-policy:
	./tests/telemetry-policy/run.sh

test-smoke:
	./tests/integration/smoke-production.sh
