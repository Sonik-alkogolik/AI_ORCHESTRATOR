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

## PowerShell Commands (Windows)
```powershell
# 1) Go to project folder
cd C:\go_learning\AI_ORCHESTRATOR

# 2) Show current queue/status counters
powershell -NoProfile -ExecutionPolicy Bypass -File .\orchestrator.ps1 stats

# 3) Create a task from CLI
powershell -NoProfile -ExecutionPolicy Bypass -File .\orchestrator.ps1 create "Build Go API with /health and /tasks"

# 4) Start interactive orchestrator UI
powershell -NoProfile -ExecutionPolicy Bypass -File .\orchestrator.ps1
```

Notes:
- In UI: press `n` to create a task, `q` to quit.
- Reviewer uses `QWEN_CMD` from `config/agents.conf`.
- Executor uses `CODEX_CMD` from `config/agents.conf`.
- If `CODEX_CMD=codex` is missing, orchestrator auto-installs `@openai/codex` via npm.
- If `QWEN_CMD=qwen` is missing, orchestrator auto-installs `@qwen-code/qwen-code` via npm.

Optional cleanup:
```powershell
# Remove active tasks (start from clean queue)
Remove-Item .\workspace\tasks\* -Recurse -Force
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
