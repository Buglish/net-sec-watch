# Phase 5 analyst usability test plan

This plan validates that target users can complete Net Sec Watch investigation
workflows through OpenSearch Dashboards without direct server access. It tests
the analyst experience; it is not a substitute for automated integration,
security, or performance testing.

## Exit criteria

The Phase 5 usability objective can be marked complete only when an anonymized
aggregate report produced by `scripts/usability-study.py` returns `PASS`.

- At least three participants complete the study.
- At least two approved profiles are represented.
- At least one participant is a security analyst or network analyst.
- Every scenario has at least an 80% completion rate.
- Median scenario difficulty is no more than 3 out of 5.
- Mean post-study confidence is at least 4 out of 5.
- No participant uses shell, container, OpenSearch API, or direct server access.

Approved profiles are security analyst, network analyst, and operations
engineer. A participant should perform comparable investigation work but
should not have implemented the feature under test.

## Privacy and consent

Use a pseudonymous participant ID such as `P01`; do not record names, email
addresses, employers, production IP addresses, credentials, or incident data.
Obtain consent before observation. Raw session JSON files are ignored by Git.
Commit only the aggregate report after reviewing free-text comments for
sensitive information.

## Facilitator preparation

1. Start the secured stack with `make up-dashboards-secure`.
2. Confirm Dashboards and the four managed data views are available.
3. Confirm each scenario has suitable test events in its approved stream.
4. Run `make ingestion-status` and resolve delayed or query-error states.
5. Give the participant the browser URL and analyst credentials.
6. Do not provide the analyst workflow guide unless the participant asks for
   help; record each facilitator hint as assistance.
7. Start each scenario from the Dashboards home page.

The facilitator may prepare the environment from the server. The participant
must use only the browser interface during the timed scenarios.

## Create a session record

Create a local, untracked result file:

```bash
mkdir -p usability/results

./scripts/usability-study.py new \
  --participant-id P01 \
  --profile security-analyst \
  --output usability/results/P01.json
```

Before the session, set `consent_confirmed`, experience, and start time. During
the session, record completion time, success, assistance, server access, a
1-to-5 difficulty rating, and concise non-sensitive notes. Complete the
post-study confidence and independent-use fields afterward.

## Scenario prompts

Read each prompt without naming the saved search, data view, query, or fields.
The versioned success criteria and time limits are in
`config/dashboards/usability-scenarios-v1.json`.

| Scenario ID | Prompt |
| --- | --- |
| `authentication-failure-triage` | Authentication failure triage |
| `firewall-drop-investigation` | Router or firewall DROP investigation |
| `parser-failure-diagnosis` | Parser failure diagnosis |
| `application-incident-investigation` | Application incident investigation |

### Authentication failure triage

“Review recent authentication failures. Identify where they came from, which
systems were affected, the relevant time window, and one source record that
supports your conclusion.”

### Router or firewall DROP investigation

“Review recent denied network traffic. Identify the source, destination,
protocol or port, frequency, and whether the original device record supports
your conclusion.”

### Parser failure diagnosis

“Find a record that failed parsing. Identify its source, the failed processing
stage, an example original record, and explain whether normal results can be
trusted while this failure exists.”

### Application incident investigation

“Investigate an application failure. Identify the affected service or host,
the first relevant failure in the selected time range, and the evidence fields
you would preserve.”

## Moderation rules

- Let the participant think aloud, but do not teach the interface mid-task.
- Record an assistance event whenever the facilitator provides directional
  help beyond restating the prompt.
- Stop a scenario at its catalog time limit and record it as unsuccessful.
- Record accidental server access immediately; it fails the no-server-access
  criterion even if the scenario otherwise succeeds.
- Ask what the participant expected before explaining unexpected behavior.
- Keep product defects separate from participant errors in the notes.

## Validate and summarize

Validate completed records:

```bash
./scripts/usability-study.py validate usability/results/P*.json
```

Generate the anonymized aggregate:

```bash
./scripts/usability-study.py summarize \
  usability/results/P*.json \
  --output docs/test-results/phase-5-usability.md
```

The summarize command exits with status 0 only when all exit criteria pass. A
status of 2 means the study is valid but incomplete or below threshold. Review
comments for sensitive data before committing the aggregate report.

When the report passes, mark **Perform usability testing with target users**
complete. Mark the first Phase 5 completion gate only if the successful
scenarios also demonstrate investigation completion without direct server
access.

## Follow-up

Classify each observed problem as blocker, major, minor, or suggestion. Create
a tracked issue for blockers and major findings, link it from the aggregate
report, and repeat affected scenarios after changes. Do not average away a
security-relevant failure.
