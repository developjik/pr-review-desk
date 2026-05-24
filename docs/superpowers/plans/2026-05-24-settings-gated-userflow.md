# Settings-Gated User Flow 구현 계획

> **Agent 작업자 안내:** 이 계획을 task-by-task로 구현할 때는 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용합니다. Step은 checkbox(`- [ ]`) 형식으로 추적합니다.

**목표:** 필수 setup이 incomplete이면 사용자를 setup/settings로 route하고, GitHub, Codex, privacy readiness가 complete일 때만 PR review workspace를 보여준다.

**아키텍처:** Main window가 setup-required content를 보여줄지 review workspace를 보여줄지 결정하는 작은 core presentation policy를 추가한다. Setup을 변경하는 action은 Settings/setup surface에 두고, main review surface는 status와 Settings navigation만 노출한다.

**기술 스택:** Swift 6.1 SwiftPM package, SwiftUI macOS app, existing executable test harness, existing UI smoke renderer, Computer Use UI verification.

---

### Task 1: User Flow Policy Test 추가

**Files:**
- Create: `Sources/PRReviewDeskCore/SettingsGatePresentation.swift`
- Create: `Tests/PRReviewDeskCoreTests/SettingsGatePresentationTests.swift`
- Modify: `Tests/PRReviewDeskCoreTests/TestHarness.swift`

- [ ] **Step 1: 실패하는 test 작성**

Incomplete readiness가 setup으로 route되고, complete readiness가 review로 route되며, main-window setup action이 Settings 열기로 제한되는지 assert하는 test를 추가한다.

- [ ] **Step 2: RED 확인**

`swift run PRReviewDeskCoreTests`를 실행하고 `SettingsGatePresentation`이 없어 new test suite build가 fail하는지 확인한다.

- [ ] **Step 3: Presentation policy 구현**

Core에 `SettingsGateDestination`, `SettingsGateAction`, `SettingsGatePresentation.make(readinessChecklist:)`를 추가한다.

- [ ] **Step 4: GREEN 확인**

`swift run PRReviewDeskCoreTests`를 실행하고 policy test가 pass하는지 확인한다.

### Task 2: Main Window UI Gate

**Files:**
- Create: `Sources/PRReviewDeskApp/SetupRequiredView.swift`
- Modify: `Sources/PRReviewDeskApp/MainView.swift`
- Modify: `Sources/PRReviewDeskApp/PRReviewDeskApp.swift`
- Modify: `Sources/PRReviewDeskApp/ReviewInboxSidebarView.swift`
- Modify: `Sources/PRReviewDeskApp/ReviewCommandPanelView.swift`

- [ ] **Step 1: Setup-required view 추가**

Missing readiness item을 summarize하고 `SettingsLink`를 primary setup action으로 노출하는 setup-required main-window view를 만든다.

- [ ] **Step 2: `MainView` gate**

`SettingsGatePresentation.destination == .setupRequired`이면 `SetupRequiredView`를 보여주고, 아니면 기존 review split view를 보여준다.

- [ ] **Step 3: Launch 시 GitHub session restore**

Saved setup이 gate 전에 인식되도록 launch 시 GitHub session restore와 Codex readiness를 함께 실행한다.

- [ ] **Step 4: Main-window setup mutation 제거**

GitHub/Codex/privacy mutation control은 Settings/setup surface에만 둔다. Main window가 gated일 때 review command panel은 setup action을 노출하지 않는다.

### Task 3: Smoke Contract와 Copy 갱신

**Files:**
- Modify: `Sources/PRReviewDeskApp/UISmokeRenderRunner.swift`
- Modify: `scripts/ui-smoke.sh`
- Modify: `Sources/PRReviewDeskApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/PRReviewDeskApp/Resources/ko.lproj/Localizable.strings`
- Modify: `README.md`

- [ ] **Step 1: Setup-gate smoke surface 추가**

Setup-required main window의 deterministic smoke render를 추가하고 `Open Settings`를 포함하는지 assert한다.

- [ ] **Step 2: Localization 갱신**

Setup-required title, summary, Settings-only guidance의 English/Korean string을 추가한다.

- [ ] **Step 3: Docs 갱신**

Setup은 Settings에서 관리되고 readiness가 complete된 뒤 review workspace가 나타난다는 내용을 문서화한다.

### Task 4: Verify와 UI Test

**Files:**
- 검증 중 defect가 드러나지 않는 한 source file 변경은 예상하지 않는다.

- [ ] **Step 1: Focused test 실행**

`swift run PRReviewDeskCoreTests`를 실행한다.

- [ ] **Step 2: Full gate 실행**

`scripts/verify.sh`를 실행한다.

- [ ] **Step 3: App launch**

`./script/build_and_run.sh --verify` 또는 기존 app launch path를 실행한다.

- [ ] **Step 4: Computer Use 검증**

가능하면 Computer Use로 launched macOS app의 setup-incomplete와 setup-complete smoke state를 inspect해서 Settings-only setup routing과 review workspace visibility를 확인한다.
