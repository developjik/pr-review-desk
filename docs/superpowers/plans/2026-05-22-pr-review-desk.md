# PR Review Desk 구현 계획

> **Agent 작업자 안내:** 이 계획을 task-by-task로 구현할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용합니다. Step은 checkbox(`- [ ]`) 형식으로 추적합니다.

**목표:** GitHub repository와 PR을 탐색하고, Codex review draft를 생성하며, 사용자가 comment를 편집/선택한 뒤 GitHub PR review를 제출할 수 있는 개인용 macOS SwiftUI app을 만든다.

**아키텍처:** Test가 있는 `PRReviewDeskCore` library와 SwiftUI executable target을 가진 SwiftPM workspace를 만든다. GitHub, Keychain, Codex process execution은 focused type 뒤에 둬서 live credential 없이 behavior를 test할 수 있게 한다.

**기술 스택:** Swift 6.2, SwiftPM, SwiftUI, Foundation URLSession, Security.framework Keychain, local `codex exec`, GitHub REST API.

---

### Task 1: Package Skeleton과 Core Models

**Files:**
- Create: `Package.swift`
- Create: `Sources/PRReviewDeskCore/Models.swift`
- Create: `Tests/PRReviewDeskCoreTests/ModelsTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: 실패하는 model test 작성**

`Repository`, `PullRequest`, `ReviewEvent`, `ReviewDraft`, `InlineCommentDraft`가 존재하고 predictably encode/decode되어야 한다는 test를 작성한다.

- [ ] **Step 2: Model test를 실행하고 RED 확인**

Run: `swift test --filter ModelsTests`

Expected: package와 model이 아직 없어서 build가 fail한다.

- [ ] **Step 3: Package skeleton과 model 구현 추가**

앱과 이후 service에서 사용할 SwiftPM package와 model type을 만든다.

- [ ] **Step 4: Model test를 실행하고 GREEN 확인**

Run: `swift test --filter ModelsTests`

Expected: model test가 pass한다.

### Task 2: Diff Position Mapping

**Files:**
- Create: `Sources/PRReviewDeskCore/DiffPositionMapper.swift`
- Create: `Tests/PRReviewDeskCoreTests/DiffPositionMapperTests.swift`

- [ ] **Step 1: 실패하는 diff mapper test 작성**

Single-hunk와 multi-hunk patch를 cover한다. `@@` 다음 첫 non-header line이 position 1이고 같은 file의 later hunk에서도 position이 계속 이어지는지 검증한다.

- [ ] **Step 2: Mapper test를 실행하고 RED 확인**

Run: `swift test --filter DiffPositionMapperTests`

Expected: `DiffPositionMapper`가 없어서 build가 fail한다.

- [ ] **Step 3: Mapper 구현**

Annotated patch text를 반환하고 new-line number를 GitHub diff position에 mapping하는 mapper를 추가한다.

- [ ] **Step 4: Mapper test를 실행하고 GREEN 확인**

Run: `swift test --filter DiffPositionMapperTests`

Expected: mapper test가 pass한다.

### Task 3: GitHub Client

**Files:**
- Create: `Sources/PRReviewDeskCore/GitHubClient.swift`
- Create: `Tests/PRReviewDeskCoreTests/GitHubClientTests.swift`

- [ ] **Step 1: 실패하는 GitHub client test 작성**

Custom `URLProtocol`로 request를 capture한다. Auth header, repository/PR decoding, changed file decoding, review submission payload를 검증한다.

- [ ] **Step 2: Client test를 실행하고 RED 확인**

Run: `swift test --filter GitHubClientTests`

Expected: `GitHubClient`가 없어서 build가 fail한다.

- [ ] **Step 3: Client 구현**

Repository list, open PR list, PR detail fetch, changed file fetch, review submit method가 있는 URLSession-backed client를 추가한다.

- [ ] **Step 4: Client test를 실행하고 GREEN 확인**

Run: `swift test --filter GitHubClientTests`

Expected: client test가 pass한다.

### Task 4: Codex Review Agent

**Files:**
- Create: `Sources/PRReviewDeskCore/CodexReviewAgent.swift`
- Create: `Tests/PRReviewDeskCoreTests/CodexReviewAgentTests.swift`

- [ ] **Step 1: 실패하는 Codex agent test 작성**

Fake command runner를 사용한다. Command argument가 `codex exec`, schema output, read-only sandbox를 포함하는지, valid JSON이 `ReviewDraft`가 되는지 검증한다.

- [ ] **Step 2: Agent test를 실행하고 RED 확인**

Run: `swift test --filter CodexReviewAgentTests`

Expected: `CodexReviewAgent`가 없어서 build가 fail한다.

- [ ] **Step 3: Codex agent 구현**

Prompt construction, JSON schema writing, process execution, output decoding을 추가한다.

- [ ] **Step 4: Agent test를 실행하고 GREEN 확인**

Run: `swift test --filter CodexReviewAgentTests`

Expected: agent test가 pass한다.

### Task 5: Keychain Token Store

**Files:**
- Create: `Sources/PRReviewDeskCore/KeychainTokenStore.swift`
- Create: `Tests/PRReviewDeskCoreTests/KeychainTokenStoreTests.swift`

- [ ] **Step 1: 실패하는 Keychain interface test 작성**

Memory-backed `TokenStore` implementation과 앱에서 공유할 protocol을 test한다. Unit test에서 실제 user secret을 쓰지 않는다.

- [ ] **Step 2: Token store test를 실행하고 RED 확인**

Run: `swift test --filter KeychainTokenStoreTests`

Expected: `TokenStore`가 없어서 build가 fail한다.

- [ ] **Step 3: Token store 구현**

Security.framework를 사용해 `TokenStore`, `InMemoryTokenStore`, `KeychainTokenStore`를 추가한다.

- [ ] **Step 4: Token store test를 실행하고 GREEN 확인**

Run: `swift test --filter KeychainTokenStoreTests`

Expected: token store test가 pass한다.

### Task 6: SwiftUI App

**Files:**
- Create: `Sources/PRReviewDeskApp/PRReviewDeskApp.swift`
- Create: `Sources/PRReviewDeskApp/AppModel.swift`
- Create: `Sources/PRReviewDeskApp/MainView.swift`

- [ ] **Step 1: Core gap이 보이면 app state test 추가**

App logic은 얇게 유지한다. SwiftUI view에 들어갈 behavior는 먼저 core test로 만든다.

- [ ] **Step 2: SwiftUI app shell 구현**

Repository sidebar, PR list, review pane, token entry, generate review action, editable draft, event picker, submit action을 만든다.

- [ ] **Step 3: App build**

Run: `swift build`

Expected: build가 succeed한다.

### Task 7: End-To-End 검증

**Files:**
- 새 파일 예상 없음.

- [ ] **Step 1: Unit test 실행**

Run: `swift test`

Expected: 모든 test가 pass한다.

- [ ] **Step 2: Build 실행**

Run: `swift build`

Expected: build가 succeed한다.

- [ ] **Step 3: Codex CLI 확인**

Project secret을 사용하지 않고 작은 `codex exec` JSON smoke test를 실행한다.

- [ ] **Step 4: GitHub token 확인**

Token을 출력하지 않고 제공된 token으로 GitHub `/user`를 호출한다.

- [ ] **Step 5: App target을 짧게 실행**

Run: `timeout 5 swift run PRReviewDeskApp`

Expected: executable이 시작된다. GUI run이 예상대로 block되면 timeout 후 종료하고 successful launch로 간주한다.

- [ ] **Step 6: Live-test 제한 보고**

안전한 open PR이 없으면 실제 review를 제출하지 않는다. Repository/PR discovery를 보고하고 임의 PR에 posting하기 전에 멈춘다.
