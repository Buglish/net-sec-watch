# Contributing to Net Sec Watch

Thank you for helping improve Net Sec Watch. The project handles security and
operational log data, so changes must be testable, reviewable, and safe by
default.

## Before contributing

1. Read [OBJECTIVES.md](OBJECTIVES.md) and identify the relevant phase.
2. Open or reference an issue describing the problem, proposed outcome, and
   acceptance criteria.
3. Do not include production logs, credentials, tokens, private keys, internal
   addresses, customer data, or other sensitive information.
4. Use only dependencies with approved OSI open-source licenses.

## Local setup

```bash
git clone git@github.com:Buglish/net-sec-watch.git
cd net-sec-watch
make init
make check
```

Docker Desktop with WSL integration is required for runtime tests:

```bash
make test-smoke
make test-integration
```

## Branches and commits

- Create a focused branch from `main`.
- Prefer the prefixes `feat/`, `fix/`, `docs/`, `test/`, or `chore/`.
- Keep commits small and coherent.
- Use an imperative commit summary, for example:
  `feat: add TLS syslog receiver`.
- Never rewrite shared history or force-push `main`.

## Pull-request requirements

Every pull request must:

- Explain the problem and approach.
- Link the relevant objective or issue.
- Include tests or explain why tests do not apply.
- Update documentation and examples.
- State security, privacy, storage, and compatibility effects.
- Confirm examples contain no private values.
- Pass repository checks, secret scanning, smoke tests, and applicable
  integration tests.
- Receive at least one approving review before merge.

## Review checklist

Reviewers should verify:

- The change satisfies its stated acceptance criteria.
- Failure, retry, restart, and rollback behavior are considered.
- Credentials and private configuration remain outside Git.
- New inputs use dedicated offset databases and bounded buffering.
- Parsers preserve original events and expose failures.
- Dependencies are necessary, maintained, pinned where practical, and
  license-compatible.
- Documentation is sufficient for another operator to reproduce the result.

## Security reports

Do not open a public issue for a suspected vulnerability or exposed secret.
Use GitHub's private security advisory feature for the repository.

## Definition of done

The shared definition of done is maintained at the end of
[OBJECTIVES.md](OBJECTIVES.md).

