# API cheatsheet — verified mutations + token scopes

Verified against the live schema (2026-06-13). All graphql (gh version agnostic). Token via `_lib.sh` `ghr_token` (config
`board.token_env` or the gh default). Token scopes used for the E2E: `project, repo, workflow`.

## Token scopes (what for which operation)
- **Board/project** (create/copy/field/item/status/link, ProjectV2 mutations): `project` scope.
- **Issue hierarchy/dependencies** (addSubIssue·addBlockedBy — issue level): `repo` (or fine-grained `issues:write`).
  → Works even in environments without a board. ⚠️ If you need both, put `project`+`repo` on the token at the same time.
- **actions/add-to-project**: PAT with `repo`+`project` (classic) or org `projects: read&write` (fine-grained).

## Hierarchy (sub-issue)
```graphql
mutation($i:ID!,$s:ID!){ addSubIssue(input:{issueId:$i, subIssueId:$s}){ subIssue{ number } } }
# issueId=parent, subIssueId=child. Cross-repo OK (verified). Move to another parent with replaceParent:Boolean.
# read: issue{ parent{ number } subIssues(first:n){ nodes{...} } subIssuesSummary{ total completed } }
```

## Dependencies (blocked-by)
```graphql
mutation($i:ID!,$b:ID!){ addBlockedBy(input:{issueId:$i, blockingIssueId:$b}){ issue{ number } } }
# issueId=the blocked side, blockingIssueId=the blocking side. removeBlockedBy has the same shape.
# read: issue{ blockedBy(first:n){ totalCount nodes{...} } issueDependenciesSummary{...} }
```

## Board creation / template clone
```graphql
mutation($oid:ID!,$t:String!){ createProjectV2(input:{ownerId:$oid,title:$t}){ projectV2{ id number } } }
mutation($pid:ID!,$oid:ID!,$t:String!){ copyProjectV2(input:{projectId:$pid,ownerId:$oid,title:$t,includeDraftIssues:true}){ projectV2{ id number } } }
# ownerId = repositoryOwner(login){ id } (both user/org). copy clones views·fields·workflows (except auto-add)·Insights.
```

## Fields / item values
```graphql
# create (SINGLE_SELECT/DATE/NUMBER/TEXT; ITERATION needs special setup):
mutation($p:ID!){ createProjectV2Field(input:{projectId:$p,dataType:SINGLE_SELECT,name:"Horizon",singleSelectOptions:[{name:"Long-term",color:BLUE,description:""}]}){ projectV2Field{ ... on ProjectV2FieldCommon{ id name } } } }
# ★ replace the default Status options (verified — fresh board Todo→config):
mutation($f:ID!){ updateProjectV2Field(input:{fieldId:$f,singleSelectOptions:[...]}){ projectV2Field{ ... on ProjectV2SingleSelectField{ options{ name } } } } }
# board add (idempotent) + set values:
mutation($p:ID!,$c:ID!){ addProjectV2ItemById(input:{projectId:$p,contentId:$c}){ item{ id } } }
mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){ updateProjectV2ItemFieldValue(input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}}){ projectV2Item{ id } } }
# value:{date:$d} / {text:$t} / {number:$n} have the same shape.
```
⚠️ Known bug (community): `updateProjectV2ItemFieldValue` does not always refresh the board view grouping index, so
card moves between columns may show up late in the UI. The value itself is stored.

## Multi-repo link / status updates
```graphql
mutation($p:ID!,$r:ID!){ linkProjectV2ToRepository(input:{projectId:$p,repositoryId:$r}){ repository{ nameWithOwner } } }
mutation($p:ID!,$s:ProjectV2StatusUpdateStatus!,$b:String,$t:Date){ createProjectV2StatusUpdate(input:{projectId:$p,status:$s,body:$b,targetDate:$t}){ statusUpdate{ id status } } }
# status: ON_TRACK | AT_RISK | OFF_TRACK | COMPLETE | INACTIVE
```

## Read/verify (views·workflows cannot be created — read only)
```graphql
query($id:ID!){ node(id:$id){ ... on ProjectV2 {
  views(first:n){ nodes{ name layout filter groupByFields{...} } }       # layout: BOARD_LAYOUT|TABLE_LAYOUT|ROADMAP_LAYOUT
  workflows(first:n){ nodes{ name enabled } }                            # no create/update, delete only
  statusUpdates(first:n){ nodes{ status targetDate body } } } } }
```

> **★ Absence of view mutations re-measured (2026-06-21, gh 2.94 introspection)** — all 28 ProjectV2 mutations enumerated with `{__schema{mutationType{fields{name}}}}`: **0 view-related**. `createProjectV2View`·`updateProjectV2View` **both absent** → not only view creation but also **layout, date-field connection, group by, and filter settings are all impossible via the API — UI-only, confirmed**. The only automation path = build the golden template once in the UI, then clone with `copyProjectV2` (the date-field connection is cloned too). If the user adds a view in the UI, only its layout can be verified (query above).
>
> **When the Roadmap view looks empty (common trap)** — unset card dates are the cause. Roadmap duration bar = fill **both `Start Date` + `Target Date`** (`gh project item-edit --id <item> --field-id <fid> --project-id <pid> --date YYYY-MM-DD`), and connect the two fields in the UI 'Set date fields'. Target Date alone gives only a dot/short bar. Group by `Milestone` for a per-version roadmap.
Milestones are REST: `gh api repos/{owner}/{repo}/milestones` (repo scope — no cross-repo). Projects auto-syncs
Milestone as a native field (BP#10).
