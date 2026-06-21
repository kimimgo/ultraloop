# 로드맵 모델 (roadmap-model) — GitHub Projects/Issues = 유일 가변 SoT

## 1. SoT = GitHub Project(v2) 보드
로드맵의 **유일한 가변 상태원**은 Project v2 보드다. 필드(`assets/project-fields.json`):
- `Status`: Backlog / Ready / In-Progress / In-Review / E2E / Done / Blocked / **Parked**
- `Roadmap-Item(Epic)` · `Priority`(P0~P2) · `Size`(XS~XL) · `Depends-on` · **`E2E-Evidence`**(증거 경로/URL)

계층: **Roadmap-Item(Milestone/`epic:*`) ⊃ Issue(작업 단위 = 카드)**.

`PROGRESS.md` 는 보드에서 재생성되는 **읽기전용 뷰**다(`regen_progress.sh`). 병렬 레인은 PROGRESS.md를
직접 쓰지 않으므로 경합·푸시충돌이 없다. 가변 상태는 **오직 보드**에만 쓴다.

## 2. 표준 컨벤션 (부트스트랩이 심음)
이슈/PR 템플릿(PR에 **E2E 증거 섹션**) · Conventional Commits · 브랜치 `type/<issue#>-<slug>` ·
라벨(`assets/labels.json` — 승인 게이트 마커 **`roadmap:approved`** 포함) · **보드 자동화는
project-scope PAT/App**(기본 `GITHUB_TOKEN` 불가). 상세 `git-and-issues.md`.

## 3. loop 단위 = 오케스트레이터 + 병렬 레인
1 loop = 다음 Ready 이슈 N개를 병렬 레인으로 편성 → 각 레인 issue→TDD→push→CI→**merge 전 E2E**→
merge-ready → join 후 merge → 보드 Done. (`loop-protocol.md`)

## 4. 멱등 보드 (query-then-create)
보드/필드 생성은 **제목으로 조회 후 없을 때만 생성**. 생성된 project node-id를 `config.roadmap.project_node_id`
에 기록해 재부트스트랩 시 **중복 생성 금지**. 라벨·필드·옵션도 같은 방식(`bootstrap_repo.sh`).

## 5. 선행 게이트 — 로드맵 필수 / 기획 제안
`roadmap_sync.sh` 종료코드로 분기:
- **exit 0 (있음+승인)** → 루프 진입. "승인"은 이슈 라벨 **`roadmap:approved`**(`assets/labels.json`,
  부트스트랩이 생성)로 확인. milestones 폴백 경로는 `config.roadmap.approved=true` 플래그로 확인.
- **exit 3 (로드맵 없음)** → 루프 **미시작 → 기획 제안 모드**. 스펙 권위 = **GitHub Spec Kit**(SKILL §4.1.3):
  1. **신규 레포면** `gh repo create` → `bootstrap_repo.sh`(라벨·보드·`specs/` 자리).
  2. 레포 정찰 → **PM 전략 단계(스펙킷 전 의무, pm-skills vendored)**: `product-strategy`(전략 캔버스) →
     `outcome-roadmap`(outcome 로드맵 — 매 루프 점검 기준) → **`strategy-red-team`**(가정 공격·kill criteria
     적대 검증 — 통과 못 하면 스펙킷 진입 금지; N레포면 메타가 플랫폼 차원 1회) →
     `specify init . --integration claude --script sh` (v0.10.x: 슬래시 아닌
     `.claude/skills/speckit-*` 스킬 + `.specify/` 인프라 설치) → **Spec Kit 체인**:
     `speckit-constitution → speckit-specify → speckit-clarify → speckit-plan → speckit-tasks →
     speckit-analyze`. 산출 스펙은 `specs/<NNN-feature>/`에 남는다(버전 관리 원본). 스펙엔 항목 +
     가치 + **수용기준 + E2E 시나리오 후보** + 우선순위 + 의존성.
  3. 사용자에게 승인/편집 요청(정당한 차단). 범위·우선순위 최종 권한은 사용자.
  4. **보드쓰기 전**: `prioritization-frameworks`(RICE/ICE 등)로 이슈 우선순위·Wave 검증. 승인 시 →
     `speckit-taskstoissues`로 이슈화(issue_populate.sh lock→ensure→unlock) → **보드쓰기 후**:
     `gstack-autoplan`(CEO/eng/DX 자동 검수)으로 보드 전체를 한 번 훑어 빠진 것·과한 것 점검 →
     보드 카드 연결 + **`roadmap:approved` 라벨** 부여 +
     **수용기준·시나리오를 스냅샷 동결**(§9.7 무결성 기준선, `e2e-production.md`) → 진입.
- **exit 5 (일시적 읽기 실패: API/네트워크)** → 기획 모드로 가지 **말고** 재시도/백오프(진행 중 프로젝트
  오초기화 방지 — REQ-RM-5). 반복 실패면 알림 후 대기.

> **부재 vs 일시 불가 구분이 핵심.** 네트워크 한 번 끊겼다고 멀쩡한 프로젝트를 "로드맵 없음"으로 보고
> 기획 모드로 리셋하면 안 된다. `roadmap_sync.sh` 가 이 둘을 exit 3 / exit 5 로 구분한다.

## 5.1 스펙 진화 정책 (in-flight 동결 / 게이트 재진입) — SKILL §4.1.4
스펙은 루프를 거치며 바뀔 수 있다(정상). 단 **루프 중(in-flight) `specs/` 수정 금지**(§9.7 스냅샷 동결).
변경이 필요하면: 진행 중 레인 완료/Park → **게이트 재진입** → 해당 feature spec만 Spec Kit으로 증분 수정
(`speckit-specify` 재실행) → 사용자 재승인 → 재동결 → **변경분만** `speckit-taskstoissues`로 이슈화.
기존 이슈 중복 생성 금지(§4 멱등 query-then-create). `specs/`가 git에 있으므로 스펙 변경 이력도 추적된다.
⚠️ 진행 중 루프 레포에 `specify init` 재실행 금지 — 게이트 (재)진입 시점에만.

## 6. 폴백 (PAT/App 없을 때, R2)
project-scope 토큰이 없으면 Projects v2 자동화가 불가. 부트스트랩은 **명확히 실패를 알리고**, 폴백으로
**Milestone + 라벨** 기반 로드맵으로 전환(보드 필드는 라벨/마일스톤으로 근사). 이 사실을 PROGRESS 뷰에 기록.
