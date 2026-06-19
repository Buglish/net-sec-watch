# Onboard a file or container log source

Use this checklist when adding a new file-based source to Net Sec Watch.

## 1. Classify the source

- Identify the source owner and operational contact.
- Record whether the source is an application, system, container, security, or
  network log.
- Review sample events for credentials, tokens, personal data, or regulated data.
- Decide the required retention and access restrictions.
- Estimate normal and peak event volume.

Never commit real production logs. Add sanitized fixtures under `examples/` or
`tests/fixtures/`.

## 2. Define the input

Add a dedicated Fluent Bit `tail` input with:

- A unique tag.
- A narrow path pattern.
- `Path_Key` to retain the source path.
- A dedicated SQLite `DB`.
- `Rotate_Wait`.
- `Skip_Long_Lines`.
- `storage.type filesystem`.
- A bounded `Mem_Buf_Limit` where appropriate.

Do not reuse an offset database between unrelated inputs.

## 3. Define parsing

- Prefer structured JSON emitted by the application.
- Add a named parser to `config/parsers-custom.conf` when required.
- Add a multiline parser for stack traces or multi-record messages.
- Preserve the original message.
- Route parse failures visibly rather than silently dropping them.

## 4. Configure private paths

Put machine-specific paths in `.env`, not in committed configuration:

```dotenv
HOST_LOG_ROOT=/var/log
CONTAINER_LOG_ROOT=/var/lib/docker/containers
```

Use `config/fluent-bit.local.conf` for private host-specific filters or outputs.
Both files are ignored by Git.

## 5. Add fixtures and tests

- Add sanitized positive examples.
- Add malformed and edge-case examples.
- Test initial collection.
- Test multiline assembly if applicable.
- Test rotation.
- Test collector restart and offset persistence.
- Test downstream interruption and buffer recovery.

Run:

```bash
make verify
make test-integration
```

## 6. Document and approve

- Update the supported-input table.
- Document required permissions and mounts.
- Document expected fields and known limitations.
- Record the source owner and parser owner outside public configuration when sensitive.
- Obtain security/privacy approval before enabling production collection.

