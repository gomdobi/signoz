# Foundry generated compose history

This directory stores versioned snapshots of generated Docker Compose files for
upgrade comparison only.

Runtime deployment uses:

```text
deploy/foundry/pours/deployment/compose.yaml
```

Do not deploy directly from this history directory.

The snapshots can contain the Foundry-generated ClickHouse named volume mount.
The current runtime storage customization is applied from
`deploy/foundry/casting.yaml` and is documented in
`deploy/foundry/CLICKHOUSE_DATA_STORAGE_RUNBOOK.md`. A named volume in a
historical snapshot must not be treated as the current runtime mount or copied
back into the generated deployment Compose file.
