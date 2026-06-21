# N레포 오케스트레이션 (멀티 레포 / 1 공유 보드 / 세션 매니저 워커) — 메타 계층

> 워커 spawn 백엔드(세션 매니저)와 메시지 브로커는 **환경별 선택 통합**이다. 기본 동작은 tmux + send-keys이며, 외부 세션 매니저/브로커는 있으면 쓰고 없으면 graceful fallback 한다.

> 발동 조건: `config.repos:` 에 항목 **2개 이상**. 1개 이하면 이 문서는 무시 — 기존 단일 레포 루프 그대로.
> 실측 원형: 멀티레포 + 공유 보드 + 세션 매니저 워커 3 토폴로지(실제 멀티레포 토폴로지에서 검증). 이 문서가 그 일반화다.

## 1. 2계층 구조 — 누가 무엇을 하나

```
메타(호스트 cc, 이 스킬을 읽는 너) ── 공유 보드 1개 소유 · 이슈→레포 배정 · 교차 Depends-on 게이트
   │                                · 워커 spawn/관찰 · 사용량 throttle · 메타 /loop·/goal
   └─ 세션 매니저/tmux ──▶ 레포 워커 N개(tmux cc 세션) = 기존 single-repo ultraloop 그대로,
                    단 ① 자기 보드를 만들지 않고(board.shared=true) ② 공유 보드를 자기 레포로 필터해 읽는다.
```

- **병렬성 2층**: 레포 간(워커 N) × 레포 내(worktree 레인 M, 기존 모델 무변경).
- **워커 = 기존 루프 재사용.** 새로 만드는 건 얇은 메타 층뿐. 워커가 메타 역할을 겸하지 않는다.
- 인-프로세스 Agent 레인과의 차이 = **사람이 `ta <repo>`로 attach해 관찰·개입 가능**(이 구조의 존재 이유).

## 2. SSOT — 1 보드 / N 레포 link

- 보드는 **레포 위 공유 1개**(`board.shared: true`). 레포마다 보드를 만들면 안 된다(기존 §2 보드 부트스트랩은
  N레포 모드에서 보드 생성 부분만 스킵하고 `board_bootstrap.sh`가 대신한다).
- 필드: 기존 `Status`/`Depends-on`/`E2E-Evidence`/`Priority`/`Size` + **`Repository`(내장 — 워커 배정 키)** +
  **`Stage`(커스텀 단일선택 — 레포를 가로지르는 빌드 단계)**.
- **교차 레포 Depends-on(★ 메타만 안다)**: 레포 A 이슈가 레포 B 이슈에 의존하면 보드 `Depends-on`에만 표현된다.
  메타가 강제한다 — **선행 카드 Done 전에는 후행 이슈를 해당 워커의 Ready로 내려보내지 않는다.**
  워커는 교차 의존을 모른다(알 필요 없게 설계).
- 보고 = 채팅이 아니라 **카드 상태 + 이슈 코멘트 + E2E-Evidence**(SSOT 단일화). 상태는 GitHub, 제어는
  세션 매니저/tmux, 관찰은 capture-pane+보드 — 3분리.
- `PROGRESS.md` 뷰는 **허브 레포**(specs/ 있는 곳)에 레포별 섹션 + 전체 롤업 2단으로 재생성.

## 3. 보드 작업 — 네이티브 `gh project` 우선, graphql은 버전무관 폴백

`gh project`는 현대 gh(≥2.31)의 표준 명령이다. **gh 버전부터 확인하라** — 구버전(예: Ubuntu apt의
2.4.0/2022)이면 명령이 없고, 그땐 업그레이드가 정공법(공식 릴리스 바이너리 → `~/.local/bin`; 단 apt
잔존 구버전이 PATH에서 가리면 `sudo apt remove gh`로 제거). `roadmap_sync.sh`는 런타임에 가용성을
검사해 **자동 폴백**하므로 어느 쪽이든 동작한다. `board_bootstrap.sh`는 graphql 기반(버전무관 멱등).
토큰은 `project` 스코프 필수(`roadmap.token_env`). graphql 정본 스니펫:

```bash
# 항목 읽기(Repository·Status 포함) — 워커 필터·메타 배정 공용
gh api graphql -f query='query($id:ID!){ node(id:$id){ ... on ProjectV2 { items(first:100){ nodes {
  content{ ... on Issue { number title repository{ nameWithOwner } } }
  fieldValues(first:20){ nodes{ ... on ProjectV2ItemFieldSingleSelectValue {
    name field{ ... on ProjectV2FieldCommon { name } } } } } } } } } }' -f id="$PROJECT_NODE_ID"
# 생성/link/Stage 필드 = scripts/board_bootstrap.sh (멱등 query-then-create)
```

`roadmap_sync.sh`는 `gh project` 부재 시 자동으로 이 graphql 경로로 폴백하고, `board.shared=true`면
자기 레포(`repo:`) 카드만 필터한다. 공유 보드 모드의 승인 판정은 `roadmap.approved`(메타가 워커
config에 기록)로 본다 — 허브 레포 라벨을 워커마다 조회하지 않는다.

## 4. 메타 루프 (가이드 — 스크립트가 아니라 네가 돈다)

메타도 /loop(ScheduleWakeup 동적) + /goal(Stop훅)로 돈다. 1 메타 사이클:

1. **보드 읽기 → 배정 산출 = `meta_sync.sh assign`** (결정적 코어): Ready 상태(`roadmap.ready_status` —
   GitHub 기본 보드는 `Todo`) + blocked 라벨 없음 + **`depends_on:` 전부 충족**(본문 줄 파싱, 의존 토큰을
   보드 카드 제목의 선두 코드로 해석 — 교차 레포 무관, 해석 불가=미충족 안전 기본값)인 카드만 JSON으로.
   `--verbose`로 게이트 사유 확인. 롤업은 `meta_sync.sh rollup` → 허브 레포 PROGRESS에 붙임.
   배정 전 **`meta_sync.sh reconcile`** 로 보드 정합부터 수렴(닫힌 이슈인데 카드≠Done → Done; Done인데
   이슈 OPEN → 경고만, 자동 close 금지). 게이트 로직 회귀 검증은 `meta_sync.sh self-test`(네트워크 0).
   이어서 **N레포 전략 정합 점검(매 메타 사이클)**: 보드 전체가 기획 게이트의 `outcome-roadmap` 플랫폼
   전략과 맞는가 — 레포 간 균형(한 레포만 비대), 교차 의존 묶음의 outcome 정렬을 본다. 드리프트면
   새 카드를 만들지 말고 게이트 재진입 신호로 보고. 전략 자체 재검증이 필요하면 `strategy-red-team`.
2. **사용량 게이트**: 주간 한도 잔량이 `budgets.weekly_usage_floor_percent` 이상 소진이면 **신규 워커 기동 중단**
   (진행분만 마감). 잔량 SoT가 불명확하면(열린질문) 보수적으로 — 모르면 기동하지 않는다.
3. **워커 보장**: 배정할 일이 있는 레포만 `worker_spawn.sh`로 기동(`max_concurrent_workers` 캡 + 스태거).
4. **지시 주입**: 멀티라인 직접 주입 금지 — task 파일을 쓰고 `worker_spawn.sh inject <name> <file>`.
   채널 1순위 = **message broker**(예시 브로커 API: HTTP `POST /team/messages` — `worker_spawn.sh inject`가 호출, inbox 영속,
   워커가 SessionStart auto-inbox/① 폴로 수신, send-keys는 깨우기 보너스라 실패해도 유실 없음).
   브로커 불가 시 send-keys 폴백(수신확인+재시도, 부록 B).
5. **관찰**: `capture-pane` + 보드 카드 이동을 함께 본다. 워커가 죽었으면(`tmux has-session` 실패) 재기동 판단.
6. **롤업**: `PROGRESS.md` 재생성(레포별+전체). dead-man·heartbeat 기존 그대로.
7. **메타 /goal 평가**: "전 레포 카드 Done + 전역 DoD + 교차 레포 E2E + 프로덕션 HITL" — 미충족이면 다음
   사이클 페이싱, 충족이면 종료 보고.

## 5. 워커 계약 (single-repo 루프와의 차이만)

- config에 `board.shared: true` + 공유 `roadmap.project_node_id` → **보드를 만들지 않는다**(생성 시도 자체 금지).
- 보드 읽기는 자기 레포 카드만(자동 필터, §3). **카드 이동·필드·증거는 `board.sh`로**(raw graphql 금지).
- **매 loop ①에서 자기 inbox 확인**: MCP team_inbox_peek/team_inbox_consume(또는 HTTP
  `GET /team/inbox/<자기세션명>?consume=true`, 예시 브로커 API) — 메타의 지시가 여기 영속된다
  (message broker 채널). 세션명 = 세션 매니저 모드면 레포 basename, 아니면 `ul-<basename>`.
- **outward/파괴 행위는 메타 게이트**: 이슈 대량 생성(taskstoissues)·merge·프로덕션 배포는 독단 금지 —
  보드/승인큐 신호로 메타 승인 경유(무인 bypassPermissions의 안전 보상).
- **spawn 권한은 메타 단독.** 워커의 Stop훅·세션이 또 다른 워커/claude 세션을 만들지 않는다(재귀 금지 기존 규칙).

## 6. 하드 가드 — 2계층 = 무한루프 위험 2배 (의무)

runaway 세션 폭주 사고 + tmux 다중 세션 hang 인시던트(실제 멀티레포 토폴로지에서 검증)가 직접 근거다.

- 메타·워커 **각자** §15 가드 전부: `goal.max_iterations` · lock · budgets · dead-man. **lock 경로 분리**
  (메타=`ultraloop-meta-$(id -u).lock`, 워커=레포별 — goal-stop-gate.sh 기본값이 이미 uid별이라 cwd가 다르면 분리됨).
- **훅 안에서 claude 세션 생성 금지**(기존 규칙). spawn은 메타의 일반 도구 호출로만.
- tmux 부하: 운영 공유 서버 보호가 필요하면 `orchestration.tmux_socket: ultraloop`(격리 소켓 `-L`).
  과부하 징후(세션 응답 지연)면 직렬 기동으로 강등. stale 소켓은 mv 후 재기동(인시던트 런북).
- 워커 기동은 **스태거**(`stagger_seconds`) — 동시 N개 기동 금지(사용량 스파이크+서버 부하).
- effort 절약: 스캐폴드/분석류 태스크는 `budgets.effort_by_task` 티어를 task 파일에 명시해 워커가 낮춰 돈다.

## 7. 기획 게이트(speckit) — N레포 분배

- 플랫폼 스펙은 **하나의 speckit 체인**으로, `specs/`는 **허브 레포 1곳**(예: 컨트롤플레인)에 둔다.
- `speckit-taskstoissues`(gh issue create 매핑, SKILL §4.1.3) 시 **이슈를 각 소관 레포에 생성**하고 보드에
  올린 뒤 `Repository`는 자동(내장 필드 — 이슈 소속 레포에서 파생, 수동 set 불가), `Stage`·`Depends-on`을
  지정해 분배한다. 교차 의존은 이 시점에 보드에 명시.
- **★ 이슈 대량 생성은 반드시 `issue_populate.sh` 경유** (이중 이슈화 레이스가 직접 동기, 실제 멀티레포 토폴로지에서 검증 —
  두 cc 세션이 같은 계획을 동시에 이슈화해 중복 4건):
  ```bash
  issue_populate.sh lock <허브레포>          # GitHub-측 잠금. exit 4 = 타 세션 작성 중 → 중단
  issue_populate.sh ensure <repo> "<제목>" [--body-file F] [--label L]   # 카드마다 — 멱등
  issue_populate.sh unlock <허브레포>
  ```
  `ensure`는 제목을 정규화(선두 `[O1]`/`O1` 류 코드 토큰 제거·소문자화)해 기존 open 이슈와 비교 —
  표기 변형 중복까지 거른다. lock 존재 검사는 검색 API가 아닌 일반 list(검색 인덱싱 지연 실측).
- 승인 마커 `roadmap:approved`는 **허브 레포** 이슈에 1회(기존 게이트 그대로). 승인 후 워커 기동.

## 8. 구현 상태 (정직하게)

| 구역 | 상태 |
|---|---|
| config 스키마(`repos:`/`board:`/`orchestration:`/budgets 확장) | ✅ 구현(하위호환: repos 비우면 기존 동작) |
| 공유 보드 부트스트랩(graphql 멱등 생성+link+Stage) | ✅ `scripts/board_bootstrap.sh` |
| 워커 spawn/주입(세션 매니저·tmux+worktree 격리+스태거+수신확인) | ✅ `scripts/worker_spawn.sh` |
| `roadmap_sync.sh` graphql 폴백 + 공유보드 레포 필터 | ✅ 구현 |
| 멱등 이슈화 + 다중 세션 population lock | ✅ `scripts/issue_populate.sh` (레이스 실증 후 추가) |
| 메타 배정 + 교차 Depends-on 게이트 + N레포 롤업 | ✅ `scripts/meta_sync.sh` (실 멀티레포 보드에서 정합 검증) |
| ready_status 설정화(GitHub 기본 보드 Todo 대응) | ✅ `roadmap.ready_status` (없으면 워커 영원히 0건이던 실버그) |
| 보드 쓰기 통합 CLI(카드 이동·필드·증거) | ✅ `scripts/board.sh` (실보드 무해쓰기+에러경로 검증) |
| message broker 내구성 채널(§12 send-keys 열린질문 해소) | ✅ `worker_spawn.sh inject` channel=auto (라운드트립 검증) |
| 세션 매니저 세션 통합(ta 호환 명명 + bookmark 영속) | ✅ `orchestration.spawn: session_mgr` (ensure-hot은 CC 안 띄움 — 실측 정정) |
| 보드 정합 reconcile + self-test(픽스처) | ✅ `meta_sync.sh reconcile/self-test` (gh-project-sync 패턴 차용, 4/4) |
| GAN 품질 루프(레인 ⑥ 선택 게이트) | ✅ `quality.gan_evaluator` 배선(가이드) — gan-style-harness 차용, max_rounds 하드가드 |
| PM 전략 단계(스펙킷 전·이슈화 전후·매 루프 점검) | ✅ pm-skills 4종 vendored(phuryn/pm-skills d384f0c) + gstack-autoplan 검수 배선 |
| 메타 루프 자동화 | 📖 가이드(§4)만 — 메타 cc가 이 문서대로 수행. 스크립트화는 차기 |
| 교차 레포 계약 E2E · 사용량 잔량 SoT · message broker 채널 격상 | ❓ 열린 질문(PLAN §12) — 미구현 |
