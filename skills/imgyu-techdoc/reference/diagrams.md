# Mermaid 다이어그램 쿡북 (범용 규약 · 예시 포함)

기술 문서에 쓰는 6종 아키타입과 공통 규약. 아래 코드 블록의 라벨(SSO·PostgreSQL 등)은 어디까지나
**원리를 보여주는 예시**이며, 규약 자체는 도메인 불문 적용된다. 모든 코드는 HTML 안
`<pre class="mermaid">…</pre>` 에 넣는다. Mermaid init은 **`theme:'base'` + `themeVariables`(문서
`:root` 팔레트에 1:1 매핑) + `themeCSS`(라운드 코너)** 로 다이어그램을 문서와 **일체화**한다 — 회색
`theme:'neutral'`이 아니라 base라야 브랜드색·한글 폰트가 먹는다. `securityLevel:'loose'`,
`htmlLabels:true`, `curve:'basis'` 고정. 정확한 값은 `template.html` 맨 아래 init 스크립트가 정본.

---

## 공통 규약 (전 다이어그램 공통 — 어기면 깨지거나 의미가 흐려진다)

1. **줄바꿈 = `&lt;br/&gt;`**. HTML 문서 안이라 `<`,`>`를 반드시 엔티티로. 예:
   `SSO["사내 계정&lt;br/&gt;+ IdP (SSO)"]`. 화살표 라벨/노드 텍스트의
   `&`도 `&amp;`로. **라벨 안 비교연산자도 이스케이프** — 결정 다이아몬드의 `>`,`<`,`>=`는
   `&gt;`,`&lt;`,`&gt;=`로(예: `{"점수 &gt;= 0.9 ?"}`). 따옴표가 든 라벨은 `["..."]`로 감싼다.
2. **노드 ID는 영문 대문자, 표시 라벨은 한글.** `ENTRY["서비스 포털&lt;br/&gt;(랜딩 홈)"]`.
   ID 재사용으로 같은 노드를 여러 곳에서 참조.
3. **노드 모양 = 의미.**
   - `(["…"])` 스타디움 = 사람/액터 (예: 사용자).
   - `["…"]` 사각 = 시스템/컴포넌트/서비스 (기본형).
   - `{"…"}` 다이아몬드 = 결정/게이트 (예: `{"승인 게이트"}`, `{"점수 &gt;= 0.9 ?"}`).
   - `[("…")]` 또는 `[(DB)]` = 저장소(필요 시).
4. **실선 vs 점선 = 의미 (절대 혼용 금지).**
   - `A --> B` 실선 = 필수·동기·주(主) 흐름.
   - `A -. 라벨 .-> B` 점선 = **조건부 / SSO 페더레이션 / 비동기·ETL / 설정 전환**.
   - 라벨 엣지 `A -->|develop| B` = 분기 조건/트리거 명시.
5. **subgraph = 계층/구역 스윔레인.** `subgraph ID["한글 라벨"]`. 내부에 `direction LR`로
   가로 배치. 중첩 가능(클라우드 > 앱 서비스 > …). 구역으로 묶어 시선을 정리한다.
6. **변경 강조 = classDef chg.** 본문 `.chg`(노랑)와 시각적으로 일치시킨다. 다이어그램 끝에:
   ```
   classDef chg fill:#fff3cd,stroke:#f4b400,stroke-width:2px,color:#3a2e00;
   class LBQ chg;
   ```
   여러 노드면 `class LBQ,PG1 chg;`.
7. **의미별 색(classDef) 팔레트 — 모양 + 색 둘 다로 의미를 준다.** 문서 팔레트에 맞춘 재사용
   classDef를 다이어그램 끝에 붙이고 노드에 `class`로 적용한다. 색만 봐도 종류가 읽히고,
   흑백/색맹 대응은 여전히 **모양**이 담당한다(색은 보조). 표준 5색:
   ```
   classDef actor    fill:#eef2f7,stroke:#5b6678,color:#1a2233;   %% 액터(사람)
   classDef external fill:#f7f2ff,stroke:#7c5cbf,color:#241a33;   %% 외부 연계
   classDef store    fill:#eef7f0,stroke:#0f9d58,color:#123;      %% 저장소/DB
   classDef chg      fill:#fff3cd,stroke:#f4b400,stroke-width:2px,color:#3a2e00;  %% 변경
   %% 시스템/서비스(기본)는 theme base의 primaryColor(연블루+브랜드테두리)를 그대로 쓴다 — 별도 class 불필요.
   ```
   문서에 색 범례 한 줄(HTML `.legend`)을 같이 두면 독자가 색↔의미를 바로 안다.
8. **접근성 = accTitle/accDescr.** 각 다이어그램 첫 줄에 넣는다(스크린리더가 읽음, 화면엔 안 보임):
   ```
   flowchart LR
       accTitle: 전체 아키텍처
       accDescr: 클라이언트가 앱 서비스를 거쳐 DB 이중화·시크릿에 닿고 외부 IdP와 연계한다.
   ```

---

## 1) 시스템 개념도 — `flowchart TB` + 가로 스윔레인

용도: 사용자 진입부터 최종 시스템까지 **엔드투엔드 개념**. 구역을 위→아래로 쌓고 각 구역 안은
`direction LR`로 가로 흐름. 주 발급 경로는 실선, 조건부 자동화는 점선.
시작점이 사람이 아니라 **이벤트·거래·메시지**면 스타디움 `(["…"])` 대신 사각 `["…"]`로 둔다
(스타디움은 사람 액터 전용). 예: `TXN(["결제 거래"])`가 아니라 `TXN["결제 거래 이벤트"]`.

```
flowchart TB
    subgraph R1["사용자 접점"]
        direction LR
        USR(["사용자"]) --> SSO["사내 계정&lt;br/&gt;+ IdP (SSO)"] --> ENTRY["서비스 포털&lt;br/&gt;(랜딩 홈)"]
    end
    subgraph R2["사용자 서비스 (Day 1)"]
        direction LR
        ACC["계정&lt;br/&gt;신청·변경"]
        CRD["크레딧&lt;br/&gt;추가 신청"]
    end
    APRV["결재 페이지&lt;br/&gt;(승인·합의)"]
    PROV["관리자 수동 발급&lt;br/&gt;(Day 1 기본)"]
    SCIM["SCIM 자동 발급&lt;br/&gt;(조건부)"]
    TGT["대상 시스템"]
    ENTRY --> R2
    ACC --> APRV
    APRV --> PROV --> TGT
    PROV -. 설정 전환 .-> SCIM -.-> TGT
```

## 2) 논리 아키텍처 — `flowchart LR` + 중첩 subgraph + classDef chg

용도: 배포 토폴로지. 클라우드 경계 안에 App/DB/시크릿/모니터링을 중첩 subgraph로, 외부 연계는
별도 구역. 페더레이션·ETL·조건부 호출은 전부 점선. 이번 개정에서 바뀐 노드는 `class … chg`.

```
flowchart LR
    subgraph CLIENT["클라이언트"]
        BR["사용자 브라우저"]
    end
    subgraph CLOUD["클라우드 (운영/개발 각각 분리)"]
        subgraph APP["앱 서비스 (PaaS)"]
            WEB["웹/API"]
        end
        subgraph DB["DB 이중화 (3노드 · failover 합의)"]
            LBQ["LB + witness&lt;br/&gt;단일 엔드포인트 · failover 합의"]
            PGP["Primary"]
            PGS["Standby&lt;br/&gt;(비동기 스트리밍 복제)"]
            LBQ --> PGP
            PGP --> PGS
            LBQ -. 감시·합의 .-> PGS
        end
        KV["시크릿 스토어&lt;br/&gt;(연결정보)"]
    end
    subgraph EXT["외부 연계"]
        SSO["IdP (SSO)"]
        ADM["외부 API&lt;br/&gt;(조건부)"]
        DWH["데이터 웨어하우스&lt;br/&gt;(보관·집계)"]
    end
    BR --> WEB
    WEB --> LBQ
    WEB --> KV
    classDef chg fill:#fff3cd,stroke:#f4b400,stroke-width:2px,color:#3a2e00;
    class LBQ chg;
    WEB -. SSO 페더레이션 .-> SSO
    WEB -. 조건부 .-> ADM
    PGP -. 적재/ETL .-> DWH
```

## 3) 네트워크 구성 — `flowchart TB` + 가상 네트워크/서브넷 중첩

용도: 망 격리·접근 통제. 가상 네트워크 안에 App 서브넷·DB 서브넷(격리). 외부 인터넷→App만 실선,
복제는 라벨 엣지, 헬스체크는 점선.

```
flowchart TB
    subgraph VNET["가상 네트워크 (Dev/Prod 분리)"]
        subgraph SUB_APP["App 서브넷"]
            APPS["앱 서비스&lt;br/&gt;(가상 네트워크 통합)"]
        end
        subgraph SUB_DB["DB 서브넷 (격리)"]
            LB["LB + witness&lt;br/&gt;(단일 엔드포인트)"]
            PG1["Primary"]
            PG2["Standby"]
        end
        PE["프라이빗 엔드포인트&lt;br/&gt;(시크릿 스토어 등)"]
    end
    INET["인터넷"] --> APPS
    APPS --> LB
    LB --> PG1
    LB -. 헬스체크 .-> PG2
    PG1 -->|비동기 복제| PG2
    APPS --> PE
    classDef chg fill:#fff3cd,stroke:#f4b400,stroke-width:2px,color:#3a2e00;
    class LB chg;
```

## 4) 상태 정의 — `stateDiagram-v2`

용도: 신청/결재 같은 워크플로 상태(결재뿐 아니라 모델 배포→섀도우→운영→재학습 같은 자동
라이프사이클에도 동일하게 쓴다). 상태 명칭은 한글로 고정. 진행 단계는 자기 루프
(`결재중 --> 결재중`). 종료는 `[*]`. 부가 설명은 `note right of …`.

```
stateDiagram-v2
    [*] --> 신청
    신청 --> 결재중: 결재 흐름 시작
    결재중 --> 결재중: 다음 결재 단계로 진행
    결재중 --> 처리완료: 모든 결재 완료
    결재중 --> 반려
    신청 --> 반려
    반려 --> 신청: 재신청
    처리완료 --> [*]
    note right of 처리완료
        계정 = "발급완료"
        크레딧 = "처리완료"
    end note
```

## 5) CI/CD 파이프라인 — `flowchart LR` + 결정 게이트

용도: 코드→빌드→배포 흐름. 브랜치 분기는 라벨 엣지(`-->|develop|`, `-->|main|`), 운영 승인은
다이아몬드 게이트 `{"승인 게이트"}`, 무중단 배포는 `-->|slot swap|`.

```
flowchart LR
    DEV["개발자&lt;br/&gt;(IDE)"] --> REPO["Repos"]
    REPO --> CI["CI: 빌드·테스트&lt;br/&gt;(설치, lint, build, test)"]
    CI -->|develop| CDD["CD: Dev 배포&lt;br/&gt;앱 서비스 (Dev)"]
    CI -->|main| APPRV{"승인 게이트"}
    APPRV -->|승인| CDS["CD: Prod staging 슬롯 배포"]
    CDS -->|slot swap| PROD["운영 무중단 배포"]
```

## 6) 일정 — `gantt`

용도: Day 1 타임라인. `dateFormat YYYY-MM-DD`, `axisFormat %m/%d`. 작업은 `:id, 시작일, 기간`
(`2d`,`6d`…), 분기점은 `:milestone, 날짜, 0d`. `section`으로 묶음.

```
gantt
    dateFormat YYYY-MM-DD
    axisFormat %m/%d
    title Day 1 일정 (예시)
    section 준비/인프라
    클라우드 리소스·환경 분리 구성      :a1, 2026-01-06, 2d
    DB 이중화·CI/CD 셋업              :a2, 2026-01-07, 3d
    section 개발
    개발 착수                         :milestone, 2026-01-08, 0d
    P1 핵심 플로우                    :b1, 2026-01-08, 6d
    API 접근 확인                     :milestone, 2026-01-09, 0d
    P2 기능군                         :b2, 2026-01-12, 4d
    section 검증/오픈
    통합 검증                         :milestone, 2026-01-15, 0d
```

---

## ELK 레이아웃 (선택 · 밀집 아키텍처도 전용)

기본 dagre 레이아웃은 subgraph가 많은 아키텍처도에서 엣지가 대각선으로 교차하며 세로로 길게
퍼진다. **ELK**로 바꾸면 엣지를 **직교(right-angle)로 라우팅**하고 교차를 최소화해 훨씬 압축·정돈된다.
`flowchart`에만 효과 있고 `stateDiagram`/`gantt`엔 영향 없다.

⚠ **트레이드오프 (켜기 전에 판단):**
- 외부 의존이 **1개→2개**(mermaid + `@mermaid-js/layout-elk`)로 는다 → SKILL §0-1 "외부 의존 0" 철칙과 상충.
- **ESM 모듈 로딩**이라 UMD `<script src>`의 **SRI 무결성 해시를 못 붙인다**(보안 하향).
- 모듈 2개를 fetch하므로 오프라인/사내망에서 더 취약.
- **결론: 다이어그램이 단순하면 켜지 마라.** 중첩 subgraph 3개 이상 + 교차 많은 아키텍처도에서만 값을 한다.

켜는 법 — `template.html`의 UMD 로더 + init `<script>`를 지우고 아래로 교체:
```html
<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  import elkLayouts from 'https://cdn.jsdelivr.net/npm/@mermaid-js/layout-elk@0/dist/mermaid-layout-elk.esm.min.mjs';
  mermaid.registerLayoutLoaders(elkLayouts);
  mermaid.initialize({
    startOnLoad:false, securityLevel:'loose', theme:'base', layout:'elk',
    htmlLabels:true, flowchart:{ htmlLabels:true, curve:'basis' },
    themeVariables:{ /* …template.html init과 동일하게 복사… */ },
    themeCSS:'.cluster rect{rx:10;ry:10} .node rect,.node polygon{rx:8;ry:8} .edgeLabel{background:#ffffff;color:#33415c}'
  });
  await mermaid.run();   // ESM은 startOnLoad 대신 명시 run()
</script>
```
개별 다이어그램만 ELK로 하려면 그 블록 첫 줄에 `%%{init:{'layout':'elk'}}%%`를 넣어도 된다.
`elk.stress` 변형은 노드가 아주 많을 때 더 균형 잡힌다.

---

## 흔한 실수

- `<br/>`를 이스케이프 안 함 → 라벨이 통째로 안 보이거나 파싱 에러. **항상 `&lt;br/&gt;`**.
- 결정 다이아몬드에 생(raw) `>`,`<` 사용 → 파싱 깨짐. `&gt;`,`&lt;`,`&gt;=`로 이스케이프.
- 실선/점선을 의미 없이 섞음 → 독자가 "필수"와 "조건부"를 구분 못 함.
- classDef를 정의만 하고 `class N chg;`로 적용 안 함 → 강조 안 됨.
- 엣지가 참조하는 노드 ID가 선언 안 됨 → 빈(orphan) 노드로 떠버림. 쓰는 ID는 반드시 선언.
- gantt 작업명에 `:`가 들어가면 파싱 깨짐(콜론은 id 구분자). 콜론이 꼭 필요하면 작업명에서 빼고 별도 표로 옮긴다.
- stateDiagram에서 한글 상태명은 OK지만 공백 포함 시 따옴표 필요할 수 있음(짧게 유지).
