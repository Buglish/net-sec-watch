.PHONY: init check telemetry-readiness security-audit ingestion-status dashboards-bundle up up-opensearch up-opensearch-secure up-dashboards up-dashboards-secure up-identity up-zeek up-suricata update-suricata-rules down down-opensearch-secure down-identity logs logs-opensearch logs-dashboards logs-identity logs-zeek logs-suricata generate rotate verify gen-tls-certs test-tls-config test-oidc test-integration test-golden test-opensearch test-opensearch-secure test-opensearch-restore test-opensearch-searchability test-opensearch-retention test-opensearch-dashboards test-dashboards-reproducibility test-event-export test-analyst-states test-usability-study test-seven-day-searches measure-opensearch-storage capacity-plan test-capacity-plan test-failover test-telemetry-policy test-smoke

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

dashboards-bundle:
	./scripts/build-dashboards-bundle.py

up:
	docker compose --env-file .env up -d

up-opensearch:
	docker compose --env-file .env --profile opensearch up -d opensearch

up-opensearch-secure: gen-tls-certs
	FLUENT_BIT_CONFIG_PATH=./config/fluent-bit.opensearch.conf \
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--profile opensearch up -d opensearch fluent-bit

up-dashboards:
	docker compose --env-file .env --profile opensearch \
		up -d opensearch opensearch-dashboards

up-dashboards-secure: gen-tls-certs
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--profile opensearch \
		up -d opensearch-dashboards-bootstrap

up-identity: gen-tls-certs
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--file compose.identity.yaml \
		--profile opensearch \
		--profile identity \
		up -d --wait keycloak opensearch
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--file compose.identity.yaml \
		--profile opensearch \
		--profile identity \
		exec -T opensearch \
		/usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh \
		-f /usr/share/opensearch/config/opensearch-security/config.yml \
		-t config -icl -nhnv \
		-cacert /usr/share/opensearch/config/root-ca.pem \
		-cert /usr/share/opensearch/config/kirk.pem \
		-key /usr/share/opensearch/config/kirk-key.pem
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--file compose.identity.yaml \
		--profile opensearch \
		--profile identity \
		up -d opensearch-dashboards-bootstrap

down-opensearch-secure:
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--profile opensearch down

down-identity:
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--file compose.identity.yaml \
		--profile opensearch \
		--profile identity down

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

logs-identity:
	docker compose --env-file .env \
		--file compose.yaml \
		--file compose.opensearch-secure.yaml \
		--file compose.identity.yaml \
		--profile opensearch \
		--profile identity logs -f keycloak opensearch-dashboards

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

test-tls-config:
	./tests/opensearch/tls-certificate-config.sh

test-oidc:
	./tests/opensearch/oidc-integration.sh

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

test-dashboards-reproducibility:
	./tests/opensearch/dashboards-reproducibility.sh

test-event-export:
	./tests/opensearch/export-events.sh

test-analyst-states:
	./tests/opensearch/analyst-states.sh

test-usability-study:
	python3 ./tests/dashboards/test-usability-study.py

test-seven-day-searches:
	./scripts/benchmark-seven-day-searches.py --insecure

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
