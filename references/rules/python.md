# Python 룰

`_base.md`와 함께 적용. 아래는 기본값 — 프로젝트 관례가 있으면 그쪽을 존중한다.

> `python-patterns` / `fastapi-patterns` 스킬이 설치돼 있으면 관용구·구조·테스트 패턴은 그 스킬을 참조한다.

## 도구

- **lint**: `ruff` (`ruff check`, `ruff format`)
- **type**: `mypy` 또는 `pyright` (strict 지향)
- **test**: `pytest` (+ `pytest-cov`로 커버리지)
- **패키지**: `uv` 우선, 없으면 `pip` + `venv`

## 레이아웃

- **src 레이아웃** 권장:

  ```
  pyproject.toml
  src/<package>/...
  tests/unit/  tests/integration/  tests/e2e/
  ```

- 설정은 `pyproject.toml` 한 곳에(`[tool.ruff]`, `[tool.mypy]`, `[tool.pytest.ini_options]`).

## 명령 예시

```bash
# 설치
uv sync                 # 또는: pip install -e ".[dev]"

# lint + format
ruff check .
ruff format --check .

# type
mypy src/              # 또는: pyright

# test + coverage (목표: coverage_target, 기본 80)
pytest --cov=src --cov-report=term-missing --cov-fail-under=80
```

## 규약

- 함수/공개 API에 타입 힌트. 신규 코드는 mypy/pyright 통과.
- 신규 기능은 테스트 먼저(TDD). 엣지 케이스는 라벨 `edge-case` 이슈로도 추적.
- 의존성은 `pyproject.toml`에 고정. lock 파일(`uv.lock`) 커밋.
