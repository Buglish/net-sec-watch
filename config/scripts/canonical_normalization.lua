-- Applies the Net Sec Watch canonical event schema after source parsing.

local SCHEMA_VERSION = "1.0.0"
local MAX_EVENT_FIELDS = 128
local MAX_NESTING_DEPTH = 8
local MAX_FIELD_NAME_LENGTH = 128

local SYSLOG_OTEL_SEVERITY = {
    [0] = 24, -- emerg -> FATAL4
    [1] = 21, -- alert -> FATAL
    [2] = 18, -- crit -> ERROR2
    [3] = 17, -- err -> ERROR
    [4] = 13, -- warning -> WARN
    [5] = 10, -- notice -> INFO2
    [6] = 9,  -- info -> INFO
    [7] = 5,  -- debug -> DEBUG
}

local TEXT_OTEL_SEVERITY = {
    trace = 1,
    debug = 5,
    info = 9,
    notice = 10,
    warn = 13,
    warning = 13,
    error = 17,
    err = 17,
    critical = 18,
    crit = 18,
    alert = 21,
    emergency = 24,
    emerg = 24,
    fatal = 24,
}

local TAG_DEFAULTS = {
    ["file.text"] = {"file.text", "file-text-1"},
    ["test.text"] = {"file.text", "file-text-1"},
    ["file.application"] = {"application.json", "application-json-1"},
    ["test.application"] = {"application.json", "application-json-1"},
    ["host.system"] = {"host.system", "host-system-1"},
    ["test.system"] = {"host.system", "host-system-1"},
    ["container.docker"] = {"container.docker", "docker-json-1"},
    ["test.container"] = {"container.docker", "docker-json-1"},
    ["net.syslog.udp"] = {"syslog.rfc3164", "syslog-rfc3164-1"},
    ["net.syslog.tcp"] = {"syslog.rfc3164", "syslog-rfc3164-1"},
    ["net.syslog.tls"] = {"syslog.rfc5424", "syslog-rfc5424-1"},
    ["net.syslog.deadletter"] = {"syslog.deadletter", "syslog-deadletter-1"},
}

local PARSER_REQUIREMENTS = {
    ["file.application"] = {"message", "application JSON"},
    ["test.application"] = {"message", "application JSON"},
    ["container.docker"] = {"stream", "Docker JSON"},
    ["test.container"] = {"stream", "Docker JSON"},
    ["sensor.zeek"] = {"ts", "Zeek JSON"},
    ["sensor.suricata"] = {"event_type", "Suricata EVE JSON"},
}

local function timestamp_seconds(timestamp)
    if type(timestamp) == "table" then
        return tonumber(timestamp.sec) or os.time()
    end
    return math.floor(tonumber(timestamp) or os.time())
end

local function utc(epoch)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(epoch))
end

-- Howard Hinnant's civil-date conversion, adapted for Lua.
local function days_from_civil(year, month, day)
    year = year - ((month <= 2) and 1 or 0)
    local era = math.floor(year / 400)
    local yoe = year - era * 400
    local shifted_month = month + ((month > 2) and -3 or 9)
    local doy = math.floor((153 * shifted_month + 2) / 5) + day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) -
        math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function parse_iso8601(value)
    if type(value) ~= "string" then
        return nil, nil
    end

    local year, month, day, hour, minute, second, zone =
        string.match(value,
            "^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)" ..
            "[%d%.]*([Zz%+%-].*)$")
    if not year then
        return nil, nil
    end

    local offset = 0
    local timezone = string.upper(zone)
    if timezone ~= "Z" then
        local sign, offset_hour, offset_minute =
            string.match(timezone, "^([%+%-])(%d%d):?(%d%d)$")
        if not sign then
            return nil, nil
        end
        offset = tonumber(offset_hour) * 3600 + tonumber(offset_minute) * 60
        if sign == "-" then
            offset = -offset
        end
    end

    local epoch = days_from_civil(
        tonumber(year), tonumber(month), tonumber(day)
    ) * 86400 + tonumber(hour) * 3600 + tonumber(minute) * 60 +
        tonumber(second) - offset
    return epoch, timezone
end

local function find_source_time(record, fallback)
    if tonumber(record["ts"]) then
        return math.floor(tonumber(record["ts"])), "UTC", false
    end

    for _, key in ipairs({"timestamp", "time"}) do
        local epoch, timezone = parse_iso8601(record[key])
        if epoch then
            return epoch, timezone, false
        end
    end

    local raw = record["event.original"] or record["log"]
    if type(raw) == "string" then
        local candidate = string.match(
            raw,
            "^(%d%d%d%d%-%d%d%-%d%d[T ][%d:%.]+[Zz%+%-][%d:]*)"
        )
        local epoch, timezone = parse_iso8601(candidate)
        if epoch then
            return epoch, timezone, false
        end
    end

    return fallback, "UTC", true
end

local function normalize_level(record)
    local level = record["level"] or record["log.level"] or
        record["log.syslog.severity.name"]
    if type(level) == "string" then
        record["log.level"] = string.lower(level)
    end

    local syslog_code = tonumber(record["log.syslog.severity.code"])
    if syslog_code and SYSLOG_OTEL_SEVERITY[syslog_code] then
        record["log.severity.number"] = SYSLOG_OTEL_SEVERITY[syslog_code]
        return
    end

    if type(level) == "string" then
        record["log.severity.number"] =
            TEXT_OTEL_SEVERITY[string.lower(level)] or 0
    elseif record["log.severity.number"] == nil then
        record["log.severity.number"] = 0
    end
end

local function parse_plain_text(tag, record)
    if tag ~= "file.text" and tag ~= "test.text" then
        return
    end

    local raw = record["event.original"] or record["log"]
    if type(raw) ~= "string" then
        return
    end

    local level, message = string.match(
        raw,
        "^%d%d%d%d%-%d%d%-%d%d[T ][^%s]+%s+(%u+)%s+(.+)"
    )
    if level then
        record["level"] = record["level"] or level
        record["message"] = record["message"] or message
    end
end

local function source_metadata(record)
    if record["host.name"] == nil and type(record["host"]) == "string" then
        record["host.name"] = record["host"]
    end
    if record["service.name"] == nil then
        record["service.name"] = record["service"] or record["ident"]
    end
    if record["device.name"] == nil then
        record["device.name"] = record["observer.name"]
    end
    if record["deployment.environment.name"] == nil then
        record["deployment.environment.name"] = record["environment"]
    end
end

local function mark_pipeline_error(tag, record)
    if tag == "net.syslog.deadletter" then
        record["event.kind"] = "pipeline_error"
        record["event.dataset"] = "pipeline.deadletter"
        record["error.type"] = "parsing_error"
        record["error.stage"] = "syslog_input"
        record["error.message"] =
            "syslog record did not satisfy the configured RFC parser"
        record["error.source_dataset"] = "syslog"
        record["_dead_letter"] = true
        record["_route"] = "deadletter"
        return
    end

    local requirement = PARSER_REQUIREMENTS[tag]
    if requirement == nil or record[requirement[1]] ~= nil then
        return
    end

    local source_dataset = record["event.dataset"]
    local defaults = TAG_DEFAULTS[tag]
    if defaults then
        source_dataset = defaults[1]
    end

    record["event.kind"] = "pipeline_error"
    record["event.dataset"] = "pipeline.deadletter"
    record["error.type"] = "parsing_error"
    record["error.stage"] = "source_parser"
    record["error.message"] =
        requirement[2] .. " record could not be parsed"
    record["error.source_dataset"] = source_dataset or tag
    record["_dead_letter"] = true
    record["_route"] = "deadletter"
end

local function inspect_fields(value, depth, state)
    if type(value) ~= "table" or state.violation then
        return
    end
    if depth > MAX_NESTING_DEPTH then
        state.violation = "maximum nesting depth exceeded"
        return
    end

    for key, child in pairs(value) do
        state.count = state.count + 1
        if state.count > MAX_EVENT_FIELDS then
            state.violation = "maximum field count exceeded"
            return
        end
        if type(key) == "string" and #key > MAX_FIELD_NAME_LENGTH then
            state.violation = "maximum field name length exceeded"
            return
        end
        inspect_fields(child, depth + 1, state)
        if state.violation then
            return
        end
    end
end

local function apply_schema_guard(record)
    if record["event.kind"] == "pipeline_error" then
        return
    end

    local source_dataset = record["event.dataset"] or "unknown"
    local state = {count = 0, violation = nil}
    inspect_fields(record, 1, state)
    record["event.field_count"] = state.count

    if state.violation == nil then
        return
    end

    record["event.kind"] = "pipeline_error"
    record["event.dataset"] = "pipeline.deadletter"
    record["error.type"] = "mapping_guard_error"
    record["error.stage"] = "schema_guard"
    record["error.message"] = state.violation
    record["error.source_dataset"] = source_dataset
    record["_dead_letter"] = true
    record["_route"] = "deadletter"
end

function normalize_canonical_event(tag, timestamp, record)
    local observed_epoch = os.time()
    local fallback_epoch = timestamp_seconds(timestamp)
    local source_epoch, timezone, inferred =
        find_source_time(record, fallback_epoch)

    if record["event.original"] == nil then
        record["event.original"] = record["log"] or record["message"]
    end
    parse_plain_text(tag, record)

    local defaults = TAG_DEFAULTS[tag]
    if defaults then
        record["event.dataset"] = record["event.dataset"] or defaults[1]
        record["event.parser_version"] =
            record["event.parser_version"] or defaults[2]
    end

    mark_pipeline_error(tag, record)
    record["event.kind"] = record["event.kind"] or "event"
    record["event.schema_version"] = SCHEMA_VERSION
    record["@timestamp"] = utc(source_epoch)
    record["event.observed"] = utc(observed_epoch)
    record["event.ingested"] = utc(observed_epoch)
    record["event.timezone"] = timezone
    record["event.timestamp_inferred"] = inferred
    record["event.clock_skew_seconds"] = observed_epoch - source_epoch

    record["collector.name"] =
        os.getenv("COLLECTOR_NAME") or "net-sec-watch-fluent-bit"
    record["collector.type"] = "fluent-bit"
    record["site.name"] = os.getenv("SITE_NAME") or "default"

    source_metadata(record)
    normalize_level(record)
    apply_schema_guard(record)

    return 1, timestamp, record
end
