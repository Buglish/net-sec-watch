#!/bin/sh
set -eu

endpoint="${OPENSEARCH_ENDPOINT:-https://opensearch:9200}"
template="/opensearch-config/index-template-v1.json"
policy="/opensearch-config/rollover-policy-v1.json"
cluster_settings="/opensearch-config/cluster-settings-v1.json"
snapshot_repository="/opensearch-config/snapshot-repository-v1.json"
snapshot_repository_name="net-sec-watch-local"
policy_id="net-sec-watch-rollover-v1"
credentials="$(printf '%s:%s' \
  "$OPENSEARCH_USERNAME" \
  "$OPENSEARCH_PASSWORD")"

curl --fail --insecure --silent --show-error \
  --user "$credentials" \
  --header "Content-Type: application/json" \
  --request PUT \
  --data-binary "@${cluster_settings}" \
  "${endpoint}/_cluster/settings"

echo
echo "Installed OpenSearch disk allocation watermarks"

curl --fail --insecure --silent --show-error \
  --user "$credentials" \
  --header "Content-Type: application/json" \
  --request PUT \
  --data-binary "@${snapshot_repository}" \
  "${endpoint}/_snapshot/${snapshot_repository_name}"

echo
echo "Registered OpenSearch snapshot repository ${snapshot_repository_name}"

curl --fail --insecure --silent --show-error \
  --user "$credentials" \
  --request POST \
  "${endpoint}/_snapshot/${snapshot_repository_name}/_verify"

echo
echo "Verified OpenSearch snapshot repository ${snapshot_repository_name}"

policy_response="/tmp/${policy_id}.json"
policy_status="$(
  curl --insecure --silent --show-error \
    --user "$credentials" \
    --output "$policy_response" \
    --write-out "%{http_code}" \
    "${endpoint}/_plugins/_ism/policies/${policy_id}"
)"

policy_url="${endpoint}/_plugins/_ism/policies/${policy_id}"
case "$policy_status" in
  200)
    sequence_number="$(
      sed -n \
        's/.*"_seq_no"[[:space:]]*:[[:space:]]*\([-0-9][0-9]*\).*/\1/p' \
        "$policy_response"
    )"
    primary_term="$(
      sed -n \
        's/.*"_primary_term"[[:space:]]*:[[:space:]]*\([-0-9][0-9]*\).*/\1/p' \
        "$policy_response"
    )"
    if [ -z "$sequence_number" ] || [ -z "$primary_term" ]; then
      echo "Could not read ISM policy concurrency metadata." >&2
      cat "$policy_response" >&2
      exit 1
    fi
    policy_url="${policy_url}?if_seq_no=${sequence_number}&if_primary_term=${primary_term}"
    ;;
  404)
    ;;
  *)
    echo "Could not inspect existing ISM rollover policy (HTTP ${policy_status})." >&2
    cat "$policy_response" >&2
    exit 1
    ;;
esac

curl --fail --insecure --silent --show-error \
  --user "$credentials" \
  --header "Content-Type: application/json" \
  --request PUT \
  --data-binary "@${policy}" \
  "$policy_url"

echo
echo "Installed OpenSearch ISM policy ${policy_id}"

curl --fail --insecure --silent --show-error \
  --user "$credentials" \
  --header "Content-Type: application/json" \
  --request PUT \
  --data-binary "@${template}" \
  "${endpoint}/_index_template/net-sec-watch-events-v1"

echo
echo "Installed OpenSearch index template net-sec-watch-events-v1"
