-- Enriches syslog records after RFC 3164 / RFC 5424 parsing.
-- Adds: log.syslog.facility.code, log.syslog.severity.code,
--       event.receive_time, event.original

local FACILITY = {
    [0]="kern",    [1]="user",     [2]="mail",   [3]="daemon",
    [4]="auth",    [5]="syslog",   [6]="lpr",    [7]="news",
    [8]="uucp",    [9]="clock",    [10]="authpriv", [11]="ftp",
    [12]="ntp",    [13]="audit",   [14]="alert", [15]="cron",
    [16]="local0", [17]="local1",  [18]="local2", [19]="local3",
    [20]="local4", [21]="local5",  [22]="local6", [23]="local7",
}

local SEVERITY = {
    [0]="emerg", [1]="alert", [2]="crit",    [3]="err",
    [4]="warning", [5]="notice", [6]="info", [7]="debug",
}

local function parse_asus_firewall(record)
    local message = record["message"]
    if type(message) ~= "string" then
        return
    end

    local action = string.match(message, "^(%u+)%s")
    if action ~= "DROP" and action ~= "REJECT" and action ~= "ACCEPT" then
        return
    end

    local values = {}
    for key, value in string.gmatch(message, "([A-Z][A-Z0-9_]*)=([^%s]+)") do
        values[key] = value
    end

    -- Require the core fields emitted by the Asuswrt kernel firewall logger.
    if not values["SRC"] or not values["DST"] or not values["PROTO"] then
        return
    end

    local normalized_action = string.lower(action)
    record["event.action"] = normalized_action
    record["event.category"] = "network"
    record["event.kind"] = "event"
    record["event.outcome"] =
        (action == "ACCEPT") and "success" or "failure"
    record["event.type"] =
        (action == "ACCEPT") and "connection" or "denied"
    record["event.module"] = "asuswrt"
    record["event.dataset"] = "asuswrt.firewall"
    record["event.parser_version"] = "asuswrt-firewall-1"

    record["source.ip"] = values["SRC"]
    record["destination.ip"] = values["DST"]
    record["network.transport"] = string.lower(values["PROTO"])

    if values["SPT"] then
        record["source.port"] = tonumber(values["SPT"]) or values["SPT"]
    end
    if values["DPT"] then
        record["destination.port"] = tonumber(values["DPT"]) or values["DPT"]
    end
    if values["IN"] and values["IN"] ~= "" then
        record["observer.ingress.interface.name"] = values["IN"]
    end
    if values["OUT"] and values["OUT"] ~= "" then
        record["observer.egress.interface.name"] = values["OUT"]
    end
    if values["MAC"] then
        record["network.forwarded_ip_mac"] = values["MAC"]
    end
    if values["LEN"] then
        record["network.bytes"] = tonumber(values["LEN"]) or values["LEN"]
    end

    record["observer.vendor"] = "ASUS"
    record["observer.product"] = "Asuswrt"
    if type(record["host"]) == "string" then
        local model = string.match(record["host"], "^(RT%-[A-Z0-9]+)")
        if model then
            record["observer.name"] = record["host"]
            record["observer.product"] = model
        end
    end
end

function enrich_syslog(tag, timestamp, record)
    local ts
    if type(timestamp) == "table" then
        ts = timestamp.sec
    else
        ts = math.floor(timestamp)
    end

    local pri = tonumber(record["pri"])
    if pri then
        local fac = math.floor(pri / 8)
        local sev = pri % 8
        record["log.syslog.facility.code"] = fac
        record["log.syslog.severity.code"] = sev
        record["log.syslog.facility.name"] = FACILITY[fac] or tostring(fac)
        record["log.syslog.severity.name"] = SEVERITY[sev] or tostring(sev)
    end

    record["event.receive_time"] = os.date("!%Y-%m-%dT%H:%M:%SZ", ts)

    -- Reconstruct a best-effort raw syslog line for audit retention.
    local parts = {}
    if record["pri"] then
        parts[#parts + 1] = "<" .. tostring(record["pri"]) .. ">"
    end
    if record["time"] then parts[#parts + 1] = record["time"] end
    if record["host"] then parts[#parts + 1] = record["host"] end
    if record["ident"] and record["pid"] then
        parts[#parts + 1] = record["ident"] .. "[" .. record["pid"] .. "]:"
    elseif record["ident"] then
        parts[#parts + 1] = record["ident"] .. ":"
    end
    if record["message"] then parts[#parts + 1] = record["message"] end
    if #parts > 0 then
        record["event.original"] = table.concat(parts, " ")
    end

    parse_asus_firewall(record)

    return 1, timestamp, record
end
