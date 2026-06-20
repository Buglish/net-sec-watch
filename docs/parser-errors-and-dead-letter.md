# Parser errors and dead-letter routing

Malformed structured records are retained rather than dropped. The collector
marks them with:

- `event.kind=pipeline_error`
- `event.dataset=pipeline.deadletter`
- `error.type=parsing_error`
- `error.stage=source_parser` or `syslog_input`
- `error.message` containing a bounded, non-sensitive explanation
- `error.source_dataset` identifying the intended source dataset
- `_dead_letter=true`

The original record remains in `event.original`. Structured parser failures
are retagged as `pipeline.deadletter`, allowing the Phase 4 storage layer to
write them to a separate data stream without duplicating the failed record in
the normal source stream.

Supported dead-letter detection currently covers application JSON, Docker JSON,
Zeek JSON, Suricata EVE JSON, and malformed syslog. Parser failures must never
copy arbitrary source content into field names or into `error.message`.

Operators should alert on sustained dead-letter volume and investigate by
`error.source_dataset`, collector, and source path. Reprocessing must use a
versioned parser and preserve the original failed record for audit comparison.
