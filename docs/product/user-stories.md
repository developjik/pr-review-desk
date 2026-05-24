# 사용자 이야기

상태: 2026-05-24 구현과 일치하는 현재 상태 사용자 이야기.

## 최초 설정

| ID | 이야기 | 수용 기준 |
| --- | --- | --- |
| US-01 | 최초 reviewer로서 workspace 전에 setup requirement를 보고 싶다. 그래야 필요한 access 없이 review를 시작하지 않는다. | Incomplete readiness는 setup-required main-window content와 Settings entry point로 route됩니다. |
| US-02 | Reviewer로서 personal token을 만들지 않고 GitHub에 sign in하고 싶다. 그래야 setup이 더 쉽고 안전하다. | 앱은 OAuth device flow를 시작하고, GitHub를 열고, copyable device code를 노출하고, completion까지 poll하고, OAuth token을 저장합니다. |
| US-03 | Reviewer로서 sign-in 후 GitHub access를 validate하고 싶다. 그래야 repository scope가 사용 가능한지 알 수 있다. | 앱은 GitHub token validation을 호출하고, login과 scope를 표시하며, GitHub readiness를 그에 맞게 표시합니다. |
| US-04 | Reviewer로서 launch 시 저장된 GitHub sign-in이 복원되길 원한다. 그래야 setup을 반복하지 않고 이어갈 수 있다. | 앱은 Keychain에서 저장된 OAuth credential을 load하고 repository를 refresh합니다. |
| US-05 | Reviewer로서 지원하지 않는 legacy credential이 제거되길 원한다. 그래야 예상하지 못한 auth mode를 앱이 사용하지 않는다. | Non-OAuth saved credential은 삭제되고 앱은 다시 GitHub sign-in을 요청합니다. |
| US-06 | Reviewer로서 Codex readiness를 확인하고 싶다. 그래야 generation failure를 일찍 발견할 수 있다. | Codex CLI와 ChatGPT login readiness가 보이고, ready가 될 때까지 generation은 disabled됩니다. |
| US-07 | Reviewer로서 AI generation 전에 privacy acknowledgement가 명확하길 원한다. 그래야 어떤 context가 전송될 수 있는지 이해한다. | Privacy acknowledgement는 required checklist item이며 first-run/setup surface에 표시됩니다. |
| US-08 | Private repository reviewer로서 private context가 AI로 전송되기 전 repository별 consent prompt를 원한다. | Private repository generation과 draft queue work는 repository consent가 accepted 또는 cancelled될 때까지 pause됩니다. |

## Review Inbox와 Repository 범위

| ID | 이야기 | 수용 기준 |
| --- | --- | --- |
| US-09 | Reviewer로서 review inbox를 primary workspace로 원한다. 그래야 review work를 status별로 triage할 수 있다. | Sidebar는 Inbox Filters를 보여주며 Review Inbox를 먼저, 그 뒤 Draft Ready, Stale, Running, Needs Setup, Submitted를 보여줍니다. |
| US-10 | Reviewer로서 empty inbox filter를 click해도 선택 상태가 유지되길 원한다. 그래야 UI가 고장난 것처럼 느껴지지 않는다. | User-selected empty filter는 hidden PR selection을 clear하고, PR의 이전 section으로 돌아가지 않고 자신의 empty state를 보여줍니다. |
| US-11 | Reviewer로서 content update 후에도 selected PR 근처의 context를 유지하고 싶다. 그래야 status change가 context를 잃게 하지 않는다. | Row가 content change로 바뀌면 selection policy는 selected row의 current section으로 filter를 이동할 수 있습니다. |
| US-12 | Reviewer로서 sidebar repository filter를 원한다. 그래야 어떤 repo의 open PR을 볼지 선택할 수 있다. | Repository list는 load, expand/collapse, search, select가 가능합니다. |
| US-13 | Reviewer로서 repository search feedback을 원한다. 그래야 query가 모든 repository를 숨겼는지 알 수 있다. | No-match row는 trimmed query를 보여주고 Clear repository search를 제공합니다. |
| US-14 | Reviewer로서 visible scope에서 pull-request search를 원한다. 그래야 number, title, author로 PR을 빠르게 찾을 수 있다. | Search는 row를 update하고, active summary를 보여주며, Clear search를 제공합니다. |
| US-15 | Reviewer로서 의미 있는 empty state를 원한다. 그래야 row가 없을 때 다음 action을 알 수 있다. | Empty state는 selected filter, search state, repository state, token state, draft-queue availability에 따라 달라집니다. |

## Pull Request Load와 Review

| ID | 이야기 | 수용 기준 |
| --- | --- | --- |
| US-16 | Reviewer로서 open PR을 선택하고 review 전에 current changed files를 load하고 싶다. | Row 선택 시 PR details, files, preflight head SHA, selected file, 가능한 saved draft가 load됩니다. |
| US-17 | Reviewer로서 AI output을 신뢰하기 전에 changed-file coverage를 보고 싶다. | Detail pane은 full 또는 partial Codex coverage와 omitted file count를 보여줍니다. |
| US-18 | Reviewer로서 reviewable patch가 없는 file은 visible하지만 Codex로 보내지 않길 원한다. | Omitted file은 omitted reason을 보여주고 coverage warning에 count됩니다. |
| US-19 | Reviewer로서 unified와 split diff view를 원한다. 그래야 선호하는 방식으로 change를 검토할 수 있다. | Selected file detail은 segmented diff mode picker를 노출합니다. |
| US-20 | Reviewer로서 formatting-sensitive code를 review할 때 whitespace marker를 켤 수 있길 원한다. | Selected file detail은 whitespace toggle을 노출합니다. |
| US-21 | Reviewer로서 file을 viewed로 표시하거나 collapse하고 싶다. 그래야 review progress를 관리할 수 있다. | File row와 selected file control은 viewed/unviewed 및 collapse/expand를 지원합니다. |
| US-22 | Keyboard-heavy reviewer로서 action, file navigation, hunk navigation, inline comment navigation command를 원한다. | Toolbar/menu/command panel은 refresh, generate, submit, open PR, inspector, next/previous file, next/previous hunk, next/previous inline comment를 지원합니다. |

## Draft 생성과 편집

| ID | 이야기 | 수용 기준 |
| --- | --- | --- |
| US-23 | Reviewer로서 selected PR의 AI review draft를 게시 없이 생성하고 싶다. | Generate는 setup과 access가 ready일 때만 실행되고 local draft body와 inline comment candidate를 만듭니다. |
| US-24 | Reviewer로서 generation이 오래 걸리거나 마음이 바뀌면 cancel하고 싶다. | Current generation은 cancellable이고 실행 중 cancel command를 노출합니다. |
| US-25 | Reviewer로서 selected PR을 draft creation에 queue하고 싶다. 그래야 review work를 준비할 수 있다. | Add Draft는 selected PR을 enqueue하고 background draft creation을 시작합니다. |
| US-26 | Reviewer로서 repository의 모든 open PR을 queue하고 싶다. 그래야 여러 draft를 준비할 수 있다. | Add drafts는 selected repository의 모든 visible open PR을 추가하고 queue를 시작합니다. |
| US-27 | Reviewer로서 draft queue item을 retry 또는 remove하고 싶다. 그래야 failure와 stale draft에서 회복할 수 있다. | Failed/stale item은 retry 가능하고, generating이 아닌 item은 remove 가능하며, remove 시 matching saved draft가 삭제됩니다. |
| US-28 | Reviewer로서 PR을 다시 열 때 saved draft가 복원되길 원한다. 그래야 edit가 사라지지 않는다. | Draft body, selected event, inline comments, saved date, private flag가 local draft store에서 load됩니다. |
| US-29 | Reviewer로서 submit 전에 review body와 inline comment를 편집하고 싶다. | Inspector text editor는 draft body와 comment body에 bind되고 edit를 local에 persist합니다. |
| US-30 | Reviewer로서 어떤 inline comment가 게시될지 선택하고 싶다. | Inline comment에는 selection toggle이 있고 selected comment만 preview/submission에 포함됩니다. |
| US-31 | Reviewer로서 generated inline comment를 diff에서 reveal하고 싶다. 그래야 anchor를 검증할 수 있다. | Inline comment는 diff 또는 inspector에서 해당 file과 diff position을 focus할 수 있습니다. |
| US-32 | Reviewer로서 아무것도 게시하지 않고 local draft를 discard하고 싶다. | Inspector는 local draft를 제거하고 draft state를 clear하는 destructive confirmation을 제공합니다. |

## Submission과 Recovery

| ID | 이야기 | 수용 기준 |
| --- | --- | --- |
| US-33 | Reviewer로서 Comment, Approve, Request Changes를 선택하고 싶다. 그래야 GitHub review event가 의도와 맞는다. | Inspector는 GitHub event value 기반 review event picker를 노출합니다. |
| US-34 | Reviewer로서 submit preview를 원한다. 그래야 정확히 무엇이 게시될지 확인할 수 있다. | Preview는 review body, selected inline comments, selected event, safety state, last checked timestamp를 보여줍니다. |
| US-35 | Reviewer로서 posting 전에 앱이 PR을 다시 check하길 원한다. 그래야 stale draft를 잡을 수 있다. | Submit preview는 confirmation 전에 PR details와 files를 refresh합니다. |
| US-36 | Reviewer로서 invalid comment가 recovery option과 함께 식별되길 원한다. | Preview와 inspector는 invalid selected comment를 보여주고 reveal, deselect, check again, regenerate를 제공합니다. |
| US-37 | Reviewer로서 stale draft가 block되길 원한다. 그래야 잘못된 commit에 comment를 게시하지 않는다. | Submission은 reviewed head SHA가 current head SHA와 일치해야 합니다. |
| US-38 | Reviewer로서 모든 GitHub posting이 final confirmation 후에만 일어나길 원한다. | Preview submit button을 click하고 safety validation이 통과할 때까지 아무것도 submitted되지 않습니다. |
| US-39 | Reviewer로서 clear suggestion이 있는 recoverable error를 원한다. 그래야 setup, access, process failure를 고칠 수 있다. | Error는 operation, summary, details, recovery suggestion, secret-like text redaction을 포함합니다. |

## Preference와 Maintenance

| ID | 이야기 | 수용 기준 |
| --- | --- | --- |
| US-40 | Reviewer로서 language와 appearance setting을 원한다. 그래야 환경에 맞게 앱을 사용할 수 있다. | Settings는 System/Light/Dark 및 System/English/Korean control을 제공합니다. |
| US-41 | Reviewer로서 이 Mac에서 sign out할 수 있게 local GitHub credential을 삭제하고 싶다. | Settings는 stored credential을 삭제하고 GitHub state를 clear할 수 있습니다. |
| US-42 | Reviewer로서 remembered private-repository consent를 clear하고 싶다. 그래야 privacy choice를 reset할 수 있다. | Settings는 remembered private repository consent entry를 모두 clear합니다. |
| US-43 | Maintainer로서 deterministic verification gate를 원한다. 그래야 live service 없이 UI와 core behavior를 check할 수 있다. | `scripts/verify.sh`는 probe, localization check, app build, smoke render, core harness를 실행합니다. |
| US-44 | Maintainer로서 stable smoke identifier와 render surface를 원한다. 그래야 UI regression을 볼 수 있다. | UI smoke는 setup gate, first-run setup, repository sidebar, inbox, diff workspace, inspector, submit preview, command panel, Settings readiness surface를 cover합니다. |
