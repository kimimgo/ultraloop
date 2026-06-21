# ultraloop 실패 모드 & 노하우 (현장 ledger)

실제 루프 운영에서 관측된 실패와 그 대처. 매 loop ①계획 점검에서 해당 징후가 보이면 여기 규칙을 따른다.
새 실패를 만나면 같은 형식으로 추가하라(증거 세션ID 포함).

---

## FM1 — DoD 천장: 사용자 보류/blocked 카드만 남았는데 게이트가 무한 재촉 ★최우선
**징후**: Stop 게이트가 `[N/200] 아직 안 끝났다 — 보드에 미종료 카드 M개 남음`을 매번 반복. 그런데 그
M개를 자율로 진행하면 금지 행위(인용 날조, In Review→Done 자기승인, 교수/저자 결정 대체, GPU 무단 실행)다.
**근원**: `goal_check.sh`는 Done이 아닌 카드를 전부 "미종료"로 카운트한다 — "사용자 보류/blocked"를 구분하지
않는다. 그래서 보드 카운트가 영원히 안 줄고 게이트가 max_iterations 까지 busywork를 강요한다. 폭주 시
classifier가 429에 걸리고 세션이 죽는다(→ FM2).
**대처**:
1. **무진척 stall 가드**(`goal-stop-gate.sh` 가드4, 2026-06-15 추가): goal_check reason이 K회
   (`engine.goal.max_stall_iterations`, 기본 10) 연속 동일하면 정지 허용 + 에스컬레이션. iteration 상한
   훨씬 전에 끊는다.
2. **보류 카드는 보드에 신호를 남겨라** — 자율 불가 카드는 `Status: Blocked` 또는 `on-hold`/`blocked` 라벨로
   표시하고, 차단 사유를 이슈 코멘트에 적는다. 그래야 다음 세션이 "보류=내 일 아님"을 안다.
3. **비게이트·비보류 자율 카드 = 0**이면 **보고 후 대기**가 정답이다. 루프를 더 돌리지 마라. goal 수렴은
   사용자가 자기 보류(In Review 해제·CS/bib 착수·affiliation·GPU 승인 등)를 풀어야 가능하다.
4. 사용자가 현재 대화에 있고 자율로 더 할 게 없으면 `engine.goal.enabled: false`로 게이트를 끄고
   직접(통제 패스) 진행한다. 보류 해제 후 `/ultraloop`로 재무장.

## FM2 — 컨텍스트 유실: transcript 증발 + classifier 429
**징후**: 새 세션이 직전 작업을 전혀 모름. `~/.claude/projects/<key>/`에 `.jsonl`이 0개(`memory/`만 생존).
**근원**: 무인 루프가 토큰을 키우다 auto-mode classifier가 429(rate limit)에 반복 실패 → 세션 붕괴.
transcript는 표준 위치에서 사라지고 `/tmp/claude-1000/<key>/`에 task 출력·classifier 에러 잔재만 남는다.
**대처**:
1. **복구는 transcript가 아니라 디스크 산출물로**: `ultraloop.mission.md`(DoD) → `ultraloop.roadmap.md` →
   프로젝트 메모리(`MEMORY.md` + `*-dod-ceiling`/`*-context-recovery`) → `evidence/*.md` → 브랜치 커밋.
2. **예방**: 사용자가 옆에 있으면 무인 자기페이싱(ScheduleWakeup) 대신 **통제 패스**로 돌려 토큰·429 폭주를
   막는다. 큰 작업은 verifiable 한 덩어리로 끊어 자주 커밋/증거화(컨텍스트가 날아가도 손실 최소).
3. 경로 변경 의심 시 먼저 `pwd -P`(심볼릭 링크?) + 프로젝트 키 전수 grep(에이전트 태그)로 확인 —
   대개 경로가 아니라 transcript 증발이 원인이다.

## FM3 — 툴체인 단정 금물: "내 PATH의 그 바이너리"가 프로젝트가 쓰는 것과 다름
**징후**: "어제는 빌드/명령이 됐는데 오늘 안 됨." 패키지/클래스 not found, 또는 하위호환 안 되는 구버전 동작.
**근원**: PATH 선두의 시스템 바이너리가 프로젝트의 실제 도구를 가린다.
- **TeX**: `/bin/pdflatex`(시스템 TeX Live 2021)엔 `elsarticle`·`siunitx`가 없다. 프로젝트 실제 도구는
  **`~/.TinyTeX`**(현대 TeX Live, 전 패키지 보유). 증거: `*.fls`에 `~/.TinyTeX/texmf.cnf` 입력.
  → 빌드는 `PATH=~/.TinyTeX/bin/x86_64-linux:$PATH latexmk ...`.
- **gh**: `/bin/gh`(apt 2.4.0)는 `gh project`(Projects v2)가 깨진다. **`~/.local/bin/gh`(≥2.9x)** 사용.
**대처**: 환경을 단정하기 전에 *프로젝트가 실제로 무엇을 쓰는지* 확인하라 — `*.fls`/lockfile/`which -a`/
sibling 산출물. **성급한 폴백(예: elsarticle→article) 금지** — 진짜 도구를 못 찾은 상태의 결론일 수 있다.
느린 전역 탐색(`find /`)은 background로 돌리고 결과를 기다린 뒤 판단.

## FM4 — 수치 출처: 기획 문서(outline/계획)는 stale, 진실은 커밋된 스크립트 출력
**징후**: outline.md의 표 값과 실제 채점 스크립트 출력이 다름(예: EXP-B B0를 outline은 67%, 스크립트는 72.2%).
**근원**: 기획 초안은 실험 전 추정치다. 실험 후 스크립트 출력으로 갱신 안 된 채 남는다.
**대처**(IRON RULE #2 강화): 논문/리포트의 모든 수치 = **커밋된 분석 스크립트의 출력**. 손입력·기획문서
인용 금지. 표 작성 전 스크립트를 재실행(또는 출력 파일을 파싱)해 값을 뽑고, 표 캡션에 **데이터 출처 경로를
명시**해 감사 가능하게 한다(`evidence/*_audit.md`).

## FM5 — 출처 간 미세 불일치는 숨기지 말고 캡션에 공개
**징후**: 같은 지표가 출처마다 다름(예: Qwen3 32B 평균이 정확값 82.25 vs figure 정수반올림 82.4).
**대처**: 표가 자기 figure와 일치하도록 figure 출처 값을 쓰되, 다른 표와의 ≤0.x pp 차이를 **캡션에 명시**
("figure pipeline의 정수반올림 때문"). 모순이 아니라 출처 차이임을 드러내면 심사자 지적을 선제 차단.

## FM6 — 자율 루프의 bypassPermissions 는 의도적이나 위험: 트레이드오프를 표면화
**징후**: 보안 리뷰가 `orchestration.permission_mode: bypassPermissions`를 HIGH로 플래그.
**근원**: 무인 운영엔 승인 모달에 답할 사람이 없어 bypass가 사실상 필수. 그러나 Bash 허용목록이 없으면
워커가 임의 명령 실행 가능.
**대처**: 사용자에게 트레이드오프를 명시(이미 했으면 진행 가능). 무인 유지 시 ① Bash 허용목록
(`go build/test/vet`, `latexmk`, `gh`, `git` 읽기 등)으로 제한 ② 격리 경계(컨테이너/worktree) ③ 고위험
(GPU·외부 push)은 HITL. 사용자가 직접 운전 중이면 `default`/`acceptEdits`가 더 안전.

## FM7 — 보드 mutation 은 결정적 코어, raw graphql 손작성 금지
**징후**: 보드 카드 이동/필드 갱신이 들쭉날쭉, 또는 `gh project` 조회가 빈 JSON 반환.
**대처**: 보드 쓰기는 `scripts/board.sh`(또는 multi-repo `meta_sync.sh`) 경유. 조회 실패 시 gh 버전(FM3)
먼저 의심. 추적성(IRON RULE #6)이 어려우면 최소한 **이슈 코멘트로 증거 링크**라도 남긴다(보드 status 이동은
별도) — In Review→Done 자율 이동은 classifier가 "사람검토게이트 자기승인"으로 차단함(정당).
⚠️ `board.sh`가 `roadmap.project_node_id 미설정` 경고 내며 status 갱신 실패 시: config의 `board.project_node_id`
확인, 임시로는 보드 수동 갱신(머지는 영향 없음). (2026-06-15 OCMS 온보딩 세션)

## FM8 — 같은 이름의 브랜치+태그 공존: `git fetch origin <name>`이 태그를 우선 → origin/<branch> stale ★
**징후**: PR이 MERGED인데 로컬 `git show origin/master:파일`엔 그 변경이 없다. `git fetch origin master`가
`* [new tag] master -> master` 또는 `tag master -> FETCH_HEAD` 출력. (2026-06-15 OCMS PR #26·#31·온보딩에서
반복 — "stale fetch" 미스터리의 진짜 원인.)
**근원**: origin에 `refs/heads/master`(브랜치) + `refs/tags/master`(태그)가 공존하면 `git fetch origin master`가
모호해 **태그를 가져온다** → remote-tracking 브랜치 `origin/master`가 갱신 안 됨. (누군가 실수로 만든 태그.)
**대처**: ① 진실 확인은 GitHub 직접 — `gh api "repos/O/R/contents/PATH?ref=master"`(**따옴표 필수** — zsh가 `?`를
glob). ② 브랜치 명시 fetch: `git fetch origin +refs/heads/master:refs/remotes/origin/master --force`. ③ 근본해결
= 원격 태그 삭제 `git push origin :refs/tags/master` 인데 **원격 ref 삭제 = 파괴적 → 사용자 명시 승인 필요**
("정리해/완료해" 류 모호 지시로는 classifier가 차단함, 정당).

## FM9 — 설계 옵션을 사용자에게 제시하기 *전에* `docs/adr/` 를 먼저 읽어라 (IRON RULE 5) ★
**징후**: 사용자가 고른 안이 기존 ADR이 명시적으로 **거부한** 안. (2026-06-15: 결제 적재를 "일정ID 기반
Visit/Billing"(Ⓑ)로 옵션 제시 → 사용자 선택 → 구현 직전 `ADR 0003` 발견: Ⓑ는 합성 Visit이 불변 #1/#4
위반·라이브 플로우 보드 오염으로 **거부**, 채택안은 LegacyPayment 분리. 사용자를 잘못된 결정으로 유도할 뻔.)
**대처**: 데이터 모델·스키마·아키텍처 선택지를 제시하기 **전에** `ls docs/adr/ && grep -rl <주제> docs/adr/`.
기존 ADR이 있으면 그 결정을 옵션의 *기본값*으로 두고 근거를 함께 제시. 사용자가 ADR을 뒤집으려면 "ADR 갱신
후" 변형(IRON RULE 5). dry-run/구현 중 ADR을 늦게 발견하면 즉시 정정하고 사용자에게 실수를 정직히 알린다.

## FM10 — 실 데이터(PII) 본 적재 전 dry-run 은 선택이 아니라 게이트 ★
**징후**: 마이그레이션/대량 적재를 바로 본 DB에 실행하려는 충동. (2026-06-15 dry-run이 *본 적재 전에* 성별
미상 1398명 손실·결제 적재 모델 미결을 잡아냄 — 추측 적재했다면 1398명이 조용히 사라지거나 가짜 성별로 오염.)
**대처**: 러너를 `MigrationDb` 같은 **mock 인터페이스**로 설계해 실 DB 없이 dry-run(매핑·크로스워크·reject
사유별 히스토그램). reject 행은 *지어내지 않고* 정직히 집계. 손실이 크면(성별처럼) 정책 결정은 사용자에게
(추측 금지 — UNKNOWN enum 추가 vs 손실 등). 본 적재는 dry-run 무결성 통과 + **사용자 최종 승인** 후에만(실
PII는 FM1 park 대상).

## FM11 — AskUserQuestion preview/description 의 한글은 깨진 \u 이스케이프로 반복 거부
**징후**: AskUserQuestion이 `InputValidationError: questions type expected array but provided string`로 거부
(여러 번). **원인**: preview/description에 손상된 유니코드 이스케이프(`\uc—์ฒ` 류 혼입)가 섞이면 JSON 파싱 실패.
**대처**: preview는 짧고 단순한 한글/ASCII만(개행 `\n` OK). 의심되면 **preview 생략**하고 label+description만.
한 번 실패하면 preview를 더 줄여 재시도.

## FM12 — `gh pr create` 로컬 브랜치 인식 실패 → push 후 `gh api` 로 PR / merge 는 `--admin` 금물
**징후**: `gh pr create`가 "No commits between / Head sha can't be blank / Head ref must be a branch". 또는
`git branch -r`엔 origin/X 보이나 GitHub 실제엔 없음(stale remote-tracking, 404).
**대처**: ① `git push origin <branch>` 로 GitHub에 브랜치 실재화 → ② `gh api -X POST repos/O/R/pulls -f
head=<branch> -f base=master -f title=... -f body=...`. ③ merge는 `--admin`(보호우회) 금물 — classifier 차단
(정당). 보호규칙 없는 Free private면 정상 `gh pr merge --squash`가 CI 통과 후 머지된다(머지 출력이 빈칸이어도
실제론 성공 — `gh pr view N --json state`로 확인). self-hosted CI watch는 `--watch` 직후 별도 `gh pr merge`.

## FM13 — 워크스페이스가 도구로 관리되면 새 레포는 그 도구 경유, 루트에 날것 디렉토리 금지 ★
**징후**: `mkdir ~/work/<name>`·`git init`으로 워크스페이스 루트에 프로젝트를 바로 만든다 — 세션/프로젝트
매니저가 관리하는 공간인데 등록 절차를 우회. **원인**: 많은 환경이 워크스페이스를 `<folder>/<repo>` 분류 +
레지스트리로 관리한다(세션 attach·부팅 복원·언어서버 활성화가 레지스트리에 의존). 날것 디렉토리는 그 도구
눈에 안 보여 세션 관리·복원에서 누락된다. **대처**: 새 프로젝트는 워크스페이스 매니저의 등록 명령(예:
`<tool> new <owner/repo> <folder>`)으로 만든다. 이미 잘못 만들었으면 등록 → 내용 이전 → 루트 잔재 제거.
워크스페이스 폴더/세션을 손으로 만지려는 충동이 들면 관리 도구를 먼저 본다.

## FM14 — 보드/이슈/PR/커밋 외부 가시 텍스트에 도구·에이전트·자동화 정체 노출 금지 ★
**징후**: 보드 카드·이슈 코멘트·PR·커밋에 `ultraloop`·"자동 루프"·"에이전트"·"레인"·`ue-` 같은 도구/내부
메커니즘 흔적이 들어간다. (2026-06-19 협업 보드의 blocked 카드 코멘트에 "eng 자동 루프(ultraloop)가 집어가지
않도록…"이라 적어 도구 정체를 노출 — 협업자에겐 사람이 쓴 제품 언어로 보여야 한다.)
**대처**: 외부 가시 문구는 **제품·프로젝트 언어로만**. 도구 메커니즘은 비노출 — "eng 루프 제외" → "개발 작업
큐와 구분(기획/탐색 단계)". 이미 노출했으면 `gh issue comment <n> --edit-last`로 중립 표현으로 정정.
`assets/pr_template.md`·`assets/issue_templates/*`의 `ultraloop`/`레인`/`ue-` 토큰도 같이 정리.

## FM15 — 도구 부재를 단일 `which` 한 번으로 단정하지 말 것 ★
**징후**: `which <tool>` 한 번 실패로 "없음" 단정 → 잘못된 전제로 대안 설계. (2026-06-19 `which codex` 실패로
"codex 없음" 단정했으나 실제론 codex가 nvm Node v24 bin에 설치돼 있었고 `codex-image` 스킬까지 존재 — 헛
대안(openai)을 제시할 뻔.) **원인**: PATH가 현재 셸의 한 Node/py 버전만 가리킴.
**대처**: 부재 판단 전 ① 다른 nvm/pyenv 버전 bin ② `npm ls -g`/`pip list` 전역 ③ 관련 스킬 존재 여부를
교차확인. "없음"은 비싼 단정 — 한 PATH가 아니라 설치 자체를 본다.

> FM11 재발(2026-06-19): AskUserQuestion이 또 `questions ... expected array but provided string`로 거부 —
> 옵션 라벨/설명의 한글이 손상된 `\u` 이스케이프로 직렬화될 때. 재시도 시 텍스트를 단순 한글로 다시 쓰면 통과.
