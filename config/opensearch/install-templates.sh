#!/bin/sh
set -eu

endpoint="${OPENSEARCH_ENDPOINT:-https://opensearch:9200}"
template="/opensearch-config/index-template-v1.json"
credentials="$(printf '%s:%s' \
  "$OPENSEARCH_USERNAME" \
  "$OPENSEARCH_PASSWORD")"

curl --fail --insecure --silent --show-error \
  --user "$credentials" \
  --header "Content-Type: application/json" \
  --request PUT \
  --data-binary "@${template}" \
  "${endpoint}/_index_template/net-sec-watch-events-v1"

echo
echo "Installed OpenSearch index template net-sec-watch-events-v1"
