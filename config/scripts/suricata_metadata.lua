-- Adds vendor-neutral fields to Suricata EVE JSON without removing EVE fields.

local function copy(record, source, target, convert)
    local value = record[source]
    if value == nil then
        return
    end
    if convert == "number" then
        value = tonumber(value) or value
    elseif convert == "lower" and type(value) == "string" then
        value = string.lower(value)
    end
    record[target] = value
end

local function nested(record, object, source, target, convert)
    local container = record[object]
    if type(container) ~= "table" then
        return
    end
    local value = container[source]
    if value == nil then
        return
    end
    if convert == "number" then
        value = tonumber(value) or value
    elseif convert == "lower" and type(value) == "string" then
        value = string.lower(value)
    end
    record[target] = value
end

function enrich_suricata(tag, timestamp, record)
    local event_type = record["event_type"] or "unknown"
    record["event.dataset"] = "suricata." .. tostring(event_type)
    record["event.module"] = "suricata"
    record["event.kind"] =
        (event_type == "alert") and "alert" or "event"
    record["observer.vendor"] = "OISF"
    record["observer.product"] = "Suricata"

    copy(record, "flow_id", "event.id")
    copy(record, "community_id", "network.community_id")
    copy(record, "src_ip", "source.ip")
    copy(record, "src_port", "source.port", "number")
    copy(record, "dest_ip", "destination.ip")
    copy(record, "dest_port", "destination.port", "number")
    copy(record, "proto", "network.transport", "lower")
    copy(record, "app_proto", "network.protocol", "lower")

    nested(record, "alert", "signature_id", "rule.id", "number")
    nested(record, "alert", "signature", "rule.name")
    nested(record, "alert", "category", "rule.category")
    nested(record, "alert", "severity", "event.severity", "number")
    nested(record, "alert", "action", "event.action", "lower")

    nested(record, "flow", "bytes_toserver", "source.bytes", "number")
    nested(record, "flow", "bytes_toclient", "destination.bytes", "number")
    nested(record, "flow", "pkts_toserver", "source.packets", "number")
    nested(record, "flow", "pkts_toclient", "destination.packets", "number")

    nested(record, "dns", "rrname", "dns.question.name")
    nested(record, "dns", "rrtype", "dns.question.type")
    nested(record, "http", "hostname", "url.domain")
    nested(record, "http", "url", "url.path")
    nested(record, "http", "http_method", "http.request.method")
    nested(record, "tls", "sni", "tls.server.name")
    nested(record, "tls", "version", "tls.version")

    return 1, timestamp, record
end
