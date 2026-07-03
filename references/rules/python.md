# Python rules

Applied together with `_base.md`. Below are defaults — when the project has its own conventions, respect those.

> If the `python-patterns` / `fastapi-patterns` skills are installed, consult them for idioms, structure, and test patterns.

## Tools

- **lint**: `ruff` (`ruff check`, `ruff format`)
- **type**: `mypy` or `pyright` (strict-leaning)
- **test**: `pytest` (+ `pytest-cov` for coverage)
- **packaging**: `uv` first; otherwise `pip` + `venv`

## Layout

- **src layout** recommended:

  ```
  pyproject.toml
  src/<package>/...
  tests/unit/  tests/integration/  tests/e2e/
  ```

- Configuration in one place, `pyproject.toml` (`[tool.ruff]`, `[tool.mypy]`, `[tool.pytest.ini_options]`).

## Command examples

```bash
# install
uv sync                 # or: pip install -e ".[dev]"

# lint + format
ruff check .
ruff format --check .

# type
mypy src/              # or: pyright

# test + coverage (target: coverage_target, default 80)
pytest --cov=src --cov-report=term-missing --cov-fail-under=80
```

## Contract

- Type hints on functions/public APIs. New code passes mypy/pyright.
- New features start with tests (TDD). Edge cases are also tracked as `edge-case`-labeled issues.
- Dependencies are pinned in `pyproject.toml`. Commit the lock file (`uv.lock`).
