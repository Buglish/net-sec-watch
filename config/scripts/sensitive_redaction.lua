-- Collector-side sensitive-field redaction for Net Sec Watch.
--
-- The filter replaces approved sensitive values with "[REDACTED]" and adds a
-- deterministic non-reversible pseudonym next to the original key where the
-- downstream analyst still needs correlation. It intentionally runs before any
-- output so secrets do not leave the collector process.

local sensitive_exact = {
  ["authorization"] = true,
  ["cookie"] = true,
  ["password"] = true,
  ["passwd"] = true,
  ["pwd"] = true,
  ["secret"] = true,
  ["token"] = true,
  ["api_key"] = true,
  ["apikey"] = true,
  ["access_key"] = true,
  ["private_key"] = true
}

local sensitive_patterns = {
  "authorization",
  "cookie",
  "password",
  "secret",
  "token",
  "api[_%-]?key",
  "private[_%-]?key"
}

local function lower(value)
  return string.lower(tostring(value or ""))
end

local function is_sensitive_key(key)
  local lowered = lower(key)
  if sensitive_exact[lowered] then
    return true
  end
  for _, pattern in ipairs(sensitive_patterns) do
    if string.find(lowered, pattern) then
      return true
    end
  end
  return false
end

local function stable_hash(value)
  local text = tostring(value or "")
  local hash = 2166136261
  for index = 1, #text do
    hash = (hash + string.byte(text, index)) * 16777619
    hash = hash % 4294967296
  end
  return string.format("fnv1a32:%08x", hash)
end

local function redact_table(record)
  local additions = {}
  for key, value in pairs(record) do
    if type(value) == "table" then
      redact_table(value)
    elseif is_sensitive_key(key) and value ~= nil and value ~= "" then
      additions[tostring(key) .. ".hash"] = stable_hash(value)
      record[key] = "[REDACTED]"
      record["event.sensitive_redaction.applied"] = true
    end
  end
  for key, value in pairs(additions) do
    record[key] = value
  end
end

function redact_sensitive_fields(tag, timestamp, record)
  redact_table(record)
  return 1, timestamp, record
end
