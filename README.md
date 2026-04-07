# AI Orchestrator (Codex + Qwen)

Two-agent orchestration system:
- `executor` (Codex): writes code
- `reviewer` (Qwen): reviews and returns `OK` or issues
- `orchestrator`: creates tasks and monitors statuses

## Structure
- `orchestrator.sh` main entry point
- `agents/` agent scripts and shared utilities
- `config/agents.conf` runtime configuration
- `workspace/` task data and logs
- `tools/` utility scripts
- `tests/` syntax and system tests (with mocks)

## Quick start
```bash
chmod +x orchestrator.sh start_all.sh agents/*.sh tools/*.sh tests/*.sh tests/fixtures/*.sh
./start_all.sh
```

## Create task from CLI
```bash
./orchestrator.sh create "Write a JSON parser in Python"
```

## Tests
```bash
./tests/test_executor.sh
./tests/test_reviewer.sh
./tests/test_system.sh
```

## Status lifecycle
`pending -> working -> review -> reviewing -> done`

If reviewer finds issues:
`reviewing -> bug -> working -> ...`

If max iterations reached:
`reviewing -> failed`
