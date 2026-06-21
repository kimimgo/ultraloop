# 브랜치 & worktree — 병렬 레인 + GC 강화 (worktree-strategy)

## 0. baseRef — 레인 분기 기준 (bootstrap 에서 고정)
병렬 레인은 `isolation:"worktree"` 로 각자 별도 worktree(별도 디렉토리 + 별도 브랜치)에서 돈다.
이 격리가 "어느 지점에서 새 브랜치를 따는가"를 정하는 게 Claude Code 네이티브 `worktree.baseRef`
설정이며, `bootstrap_repo.sh`(§6.5)가 대상 레포 `.claude/settings.json` 에 기록한다(`config.worktree.base_ref`).

| 값 | 분기 기준 | 효과 |
|---|---|---|
| **`fresh`** (기본·권장) | `origin/<default>` | 모든 레인이 깨끗한 원격 기준에서 출발 → 재현가능. 로컬 미푸시 커밋은 레인에 **안 샌다** |
| `head` | 로컬 `HEAD` | 진행 중인 미푸시 커밋 위에서 레인을 빌드해야 할 때만 |

- 적용 범위는 3곳 동일: `claude --worktree`, `EnterWorktree` 도구, **agent/Workflow `isolation:"worktree"`**(=병렬 레인).
- ultraloop 권장 = **`fresh`**: 레인끼리 서로의 반쯤 한 작업을 상속하지 않아 병렬 머지 충돌·비결정성을 줄인다.
  미푸시 로컬 베이스 위에서 작업을 시켜야 하는 예외 상황에서만 `head`.

## 1. 원칙
- trunk-based + 단명 브랜치(이슈 1:1), squash merge 후 브랜치 삭제, `main` 보호.
- 병렬 = 레인별 **git worktree** 분리(`config.worktree.root`, 기본 `../.ue-worktrees/<issue#>-<slug>`),
  각 레인 1 (서브)에이전트.

## 2. 레인 비충돌 편성
오케스트레이터는 동시 레인으로 **다음만** 묶는다:
- `Depends-on` 위배 없음(선행 카드가 Done).
- **모듈 디렉토리 비충돌**(레인들이 같은 파일/디렉토리를 동시에 만지지 않음 → 머지 충돌 최소화).
- 충돌 가능성이 있으면 직렬화(한 레인씩).
동시 레인 수 상한 = `config.worktree.max_lanes`(기본 2).

## 3. 명령 (`worktree_mgr.sh`)
```bash
worktree_mgr.sh create <issue#> <slug>   # 레인 worktree 생성 + 브랜치 체크아웃
worktree_mgr.sh list                      # 현재 worktree + 카드 상태 매핑
worktree_mgr.sh gc                         # 종료된 레인만 정리(아래 규칙)
```

## 4. ★ GC 강화 — in-flight 보호 (REQ-WT-4)
루프 시작 시(①) GC. **제거 대상 = 카드가 종료 상태(Done/Closed)이고 브랜치가 main에 머지됨.**

**제외(보존) — 두 층으로 본다:**

| # | 보존규칙 | 누가 검사 |
|---|---|---|
| 1 | 미커밋 변경이 있는 worktree | `gc` 결정적(exit 10) |
| 2 | main보다 앞선 **미머지** 브랜치 | `gc` 결정적(exit 11) |
| 3 | **비종료 카드**(Ready/In-Progress/In-Review/E2E/**Parked**) | **오케스트레이터**가 gc 호출 전 거름 |
| 4 | **승인 큐 대기** 중인 항목(`ultraloop-approvals/*.pending` 이 issue# 참조) | `gc` best-effort 보존 |

- 규칙 ①②는 `gc`가 git 레벨에서 토큰 없이 **결정적**으로 검사한다.
- 규칙 ③은 보드 조회(project-scope 토큰)가 필요해 worktree마다 돌리면 무겁고 취약하다. 대신 **오케스트레이터가
  이미 읽은 보드로 Done 확정 레인만 gc에 넘긴다**(루프 ①②에서 보드를 보므로 컨텍스트가 거기 있다). gc는
  보드를 직접 보지 않는다.
- 규칙 ④는 `gc`가 승인 큐 pending 파일에서 해당 issue#를 grep해 **best-effort**로 보존한다(enqueue가 action에
  issue#를 안 넣었으면 못 잡을 수 있으나, 그 경우도 규칙 ②(ahead>0)가 대부분 막는다).

→ 애매하면 **보존**(careful). in-flight 병렬 작업을 GC가 삭제하는 레이스를 방지한다.

## 5. 제거는 고위험
worktree 제거(특히 미커밋/미머지)는 §14 고위험 → 차단·확인(승인 큐). `worktree_mgr.sh gc` 는 보존규칙에
걸리면 **exit 2(보존됨)** 로, 지울 것이 처음부터 없으면 **exit 0(nothing-to-do)** 으로 끝낸다(강제 삭제 안 함).
