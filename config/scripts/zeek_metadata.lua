-- Adds vendor-neutral fields to Zeek JSON logs without removing native fields.

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

function enrich_zeek(tag, timestamp, record)
    local path = record["log.file.path"] or ""
    local dataset = string.match(path, "([^/]+)%.log$")
    if dataset then
        record["event.dataset"] = "zeek." .. dataset
    else
        record["event.dataset"] = "zeek.unknown"
    end

    record["event.module"] = "zeek"
    record["event.kind"] = "event"
    record["observer.vendor"] = "Zeek"
    record["observer.product"] = "Zeek Network Security Monitor"

    copy(record, "uid", "event.id")
    copy(record, "id.orig_h", "source.ip")
    copy(record, "id.orig_p", "source.port", "number")
    copy(record, "id.resp_h", "destination.ip")
    copy(record, "id.resp_p", "destination.port", "number")
    copy(record, "proto", "network.transport", "lower")
    copy(record, "service", "network.protocol", "lower")
    copy(record, "duration", "event.duration", "number")
    copy(record, "orig_bytes", "source.bytes", "number")
    copy(record, "resp_bytes", "destination.bytes", "number")
    copy(record, "query", "dns.question.name")
    copy(record, "qtype_name", "dns.question.type")
    copy(record, "host", "url.domain")
    copy(record, "uri", "url.path")
    copy(record, "server_name", "tls.server.name")

    return 1, timestamp, record
end
