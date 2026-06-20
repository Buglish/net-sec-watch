-- Applies the shared Net Sec Watch schema to network observations.
--
-- Events are deliberately preserved as separate source observations. The
-- correlation key lets a later detection or incident layer group an ASUS
-- firewall record, Zeek connection, and Suricata flow describing the same
-- five-tuple in the same five-minute window.

local SCHEMA_VERSION = "net-sec-watch-network-1.0"
local CORRELATION_WINDOW_SECONDS = 300

local function text(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function endpoint(ip, port)
    return text(ip) .. ":" .. text(port)
end

local function correlation_key(ingest_time, record)
    local source_ip = record["source.ip"]
    local destination_ip = record["destination.ip"]
    local transport = record["network.transport"]
    if source_ip == nil or destination_ip == nil or transport == nil then
        return nil
    end

    local bucket = math.floor(
        ingest_time / CORRELATION_WINDOW_SECONDS
    )
    return table.concat({
        string.lower(text(transport)),
        endpoint(source_ip, record["source.port"]),
        endpoint(destination_ip, record["destination.port"]),
        tostring(bucket),
    }, "|")
end

local function observation_id(record)
    local module = text(record["event.module"])
    local native_id = record["event.id"] or record["uid"] or record["flow_id"]
    if native_id ~= nil then
        return module .. "|" .. text(record["event.dataset"]) .. "|" ..
            text(native_id)
    end

    local original = record["event.original"] or record["message"] or
        record["log.file.path"] or ""
    return module .. "|" .. text(record["event.dataset"]) .. "|" .. text(original)
end

function normalize_network_event(tag, timestamp, record)
    local module = record["event.module"]
    if module ~= "asuswrt" and module ~= "zeek" and
        module ~= "suricata" then
        return 0, timestamp, record
    end

    local ingest_time = os.time()
    record["event.schema_version"] = SCHEMA_VERSION
    record["event.observation_id"] = observation_id(record)
    record["event.deduplication.strategy"] = "correlate-preserve"
    record["event.deduplication.window_seconds"] =
        CORRELATION_WINDOW_SECONDS
    record["event.correlation_time_basis"] = "collector_ingest_time"

    if record["event.parser_version"] == nil then
        record["event.parser_version"] =
            text(record["event.module"]) .. "-network-1"
    end

    local key = correlation_key(ingest_time, record)
    if key ~= nil then
        record["event.correlation_key"] = key
    else
        record["event.correlation_status"] = "insufficient-network-fields"
    end

    return 1, timestamp, record
end
