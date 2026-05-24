# GitHub OAuth Provider 결정

작성일: 2026-05-22
수정일: 2026-05-23

이슈: #36, #91

## 결정

Interactive GitHub authentication path는 GitHub OAuth App device flow 하나만 사용합니다. 단, credential model은 나중에 GitHub App user access token을 수용할 수 있도록 열어 둡니다.

이 앱은 여전히 개인용 local macOS tool입니다. OAuth-only authentication은 backend service, local callback server, app installation picker, organization rollout flow를 추가하지 않고 manual personal-token entry를 제거해야 합니다. OAuth App device flow는 이 형태에 맞습니다. 앱은 user code를 보여주고, browser에서 GitHub를 열고, GitHub가 요구하는 interval로 poll하고, 반환된 bearer token을 기존 versioned Keychain credential store에 저장합니다.

GitHub App user auth는 least privilege와 repository-scoped access 측면에서 장기적으로 더 좋은 model입니다. 하지만 앱에 그 operational control이 필요하기 전부터 installation scope와 expiring user-token 처리를 도입합니다. 개인/local 사용을 넘어가거나 repository별 installation governance가 필요해지면 GitHub App user auth를 다시 검토합니다.

## 비교한 선택지

### OAuth App Device Flow

장점:

- Local callback listener나 custom URL scheme이 필요 없습니다.
- Backend가 필요 없습니다.
- UX가 desktop app에 맞습니다. Code를 보여주고, `https://github.com/login/device`를 열고, authorize될 때까지 poll합니다.
- 현재 REST API 사용을 유지하면서 manual token entry를 first-party sign-in flow로 바꿀 수 있습니다.

단점:

- Private repository support에는 broad `repo` OAuth scope가 필요합니다.
- OAuth scope는 GitHub App repository permission보다 granular하지 않습니다.
- 앱은 granted scope를 validate하고 private-repo tradeoff를 명확히 설명해야 합니다.

### GitHub App User Auth

장점:

- Broad OAuth scope 대신 fine-grained repository permission을 사용합니다.
- Access가 user permission과 app permission 모두에 의해 제한되며, installation/repository selection으로도 제한될 수 있습니다.
- User-to-server token은 refresh token을 가진 short-lived token이 될 수 있습니다.
- Organization/team use와 future automation에 더 적합합니다.

단점:

- Private repository access에는 repository가 있는 위치에 app installation이 필요합니다.
- First-run UX가 단순 sign-in뿐 아니라 install/authorize/repository visibility state를 처리해야 합니다.
- Token refresh와 installation access error가 첫 OAuth implementation의 일부가 됩니다.
- Backend가 없는 personal local app에는 움직이는 부분이 더 많습니다.

## 필요한 Access

현재 app operation과 필요한 access:

| App operation | REST endpoint family | OAuth App scope | GitHub App permission |
| --- | --- | --- | --- |
| Signed-in user 검증 | `GET /user` | Authorization 외 추가 없음 | user token |
| Accessible repositories list | `GET /user/repos` | Private repo는 `repo`, public-only mode는 `public_repo` | Metadata read |
| PR list/inspect | `GET /repos/{owner}/{repo}/pulls`, `GET /repos/{owner}/{repo}/pulls/{pull_number}` | Private repo는 `repo`, public-only mode는 `public_repo` | Pull requests read |
| PR files read | `GET /repos/{owner}/{repo}/pulls/{pull_number}/files` | Private repo는 `repo`, public-only mode는 `public_repo` | Pull requests read |
| PR issue comments read | `GET /repos/{owner}/{repo}/issues/{issue_number}/comments` | Private repo는 `repo`, public-only mode는 `public_repo` | Pull requests read 또는 Issues read |
| PR review comments read | `GET /repos/{owner}/{repo}/pulls/{pull_number}/comments` | Private repo는 `repo`, public-only mode는 `public_repo` | Pull requests read |
| Check runs read | `GET /repos/{owner}/{repo}/commits/{ref}/check-runs` | Private repo는 `repo` | Checks read |
| PR review submit | `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews` | Private repo는 `repo`, public-only mode는 `public_repo` | Pull requests write |

첫 OAuth request 최소값:

- Private repository mode: `repo` 요청.
- 나중에 public-only mode가 추가되면: `public_repo`를 요청하고, 사용자가 authorization을 upgrade할 때까지 private repository selection을 block합니다.

미래 GitHub App permission 최소값:

- Metadata: read.
- Pull requests: write. PR listing, PR file read, review comment read, review submission을 포함합니다.
- Checks: read.
- Issues: target installation에서 PR issue comment가 Pull requests read로 accessible하지 않을 때만 read.

## macOS UX 제약

- Device flow code는 15분 뒤 만료되므로 sign-in sheet에는 명시적 retry path가 필요합니다.
- Polling은 반환된 `interval`을 지켜야 하며 `authorization_pending`, `slow_down`, `expired_token`, `access_denied`를 처리해야 합니다.
- 앱은 verification URL을 default browser에서 열어야 하며, 다른 browser/profile을 선호하는 사용자를 위해 copyable code도 제공해야 합니다.
- 앱은 fallback으로 manual personal-token entry를 노출하면 안 됩니다. Legacy saved personal credential이 발견되면 API access에 사용하지 않고 GitHub OAuth re-authorization을 요구해야 합니다.
- Token은 기존 versioned Keychain credential store에 유지합니다. Stored credential은 token kind, scopes, login, token type, created/updated timestamp, future expiration field를 기록해야 합니다.

## 후속 구현 Issue

생성된 구현 issue:

1. #50 OAuth App device-flow client 구현.
2. #51 GitHub OAuth sign-in UI 추가.
3. #52 OAuth scope와 repository access validate.
4. #53 OAuth token revocation과 replacement control 추가.
5. #91 GitHub authentication을 OAuth-only로 전환.

Deferred follow-up: OAuth App device-flow MVP가 안정화된 뒤 GitHub App user auth를 다시 검토합니다.

## 확인한 참고 자료

- GitHub OAuth App device flow: <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps>
- GitHub OAuth scopes: <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps>
- GitHub App user auth: <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-with-a-github-app-on-behalf-of-a-user>
- GitHub App user access token and device flow: <https://docs.github.com/en/enterprise-cloud@latest/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app>
- Repository listing permission: <https://docs.github.com/en/rest/repos/repos>
- Pull request file/review permission: <https://docs.github.com/en/rest/pulls/pulls> and <https://docs.github.com/en/rest/pulls/reviews>
- Check run permission: <https://docs.github.com/en/rest/checks/runs>
- Issue comment permission: <https://docs.github.com/en/rest/issues/comments>
