#!/bin/sh
set -eu

endpoint="${OPENSEARCH_DASHBOARDS_ENDPOINT:-http://opensearch-dashboards:5601}"
credentials="$(printf '%s:%s' \
  "$OPENSEARCH_DASHBOARDS_USERNAME" \
  "$OPENSEARCH_DASHBOARDS_PASSWORD")"
data_views="/dashboards-config/data-views-v1.ndjson"
attempt=0

until curl --fail --silent --show-error \
  --user "$credentials" \
  "${endpoint}/api/status" >/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 80 ]; then
    echo "OpenSearch Dashboards did not become ready for data-view import." >&2
    exit 1
  fi
  sleep 3
done

curl --fail --silent --show-error \
  --user "$credentials" \
  --header "osd-xsrf: true" \
  --form "file=@${data_views};type=application/ndjson" \
  "${endpoint}/api/saved_objects/_import?overwrite=true"

echo
echo "Installed Net Sec Watch OpenSearch Dashboards data views"
