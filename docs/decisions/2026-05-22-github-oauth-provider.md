# GitHub OAuth Provider Decision

Date: 2026-05-22
Updated: 2026-05-23

Issue: #36, #91

## Decision

Use a GitHub OAuth App device flow as the only interactive GitHub authentication path, while keeping the credential model open for GitHub App user access tokens later.

This app is still a personal, local macOS tool. OAuth-only authentication should remove manual personal-token entry without adding a backend service, local callback server, app installation picker, or organization rollout flow. OAuth App device flow fits that shape: the app shows a user code, opens GitHub in the browser, polls GitHub at the required interval, and stores the returned bearer token in the existing versioned Keychain credential store.

GitHub App user auth is the better long-term model for least privilege and repository-scoped access, but it introduces installation scope and expiring user-token handling before the app needs those operational controls. Revisit GitHub App user auth when this moves beyond personal/local use or needs per-repository installation governance.

## Options Compared

### OAuth App Device Flow

Pros:

- No local callback listener or custom URL scheme is required.
- No backend is required.
- The UX matches a desktop app: show a code, open `https://github.com/login/device`, and poll until authorized.
- It can replace manual token entry with a first-party sign-in flow while preserving current REST API usage.

Cons:

- Private repository support needs the broad `repo` OAuth scope.
- OAuth scopes are less granular than GitHub App repository permissions.
- The app must validate granted scopes and explain the private-repo tradeoff clearly.

### GitHub App User Auth

Pros:

- Uses fine-grained repository permissions instead of broad OAuth scopes.
- Access is limited by both the user and the app's permissions, and can also be limited by installation/repository selection.
- User-to-server tokens can be short-lived with refresh tokens.
- Better fit for organization/team use and future automation.

Cons:

- Private repository access requires the app to be installed where the repositories live.
- First-run UX must handle install/authorize/repository visibility states, not just sign-in.
- Token refresh and installation access errors become part of the first OAuth implementation.
- More moving parts for a personal local app with no backend.

## Required Access

Current app operations and required access:

| App operation | REST endpoint family | OAuth App scope | GitHub App permission |
| --- | --- | --- | --- |
| Validate signed-in user | `GET /user` | none beyond authorization | user token |
| List accessible repositories | `GET /user/repos` | `repo` for private repos, `public_repo` for public-only mode | Metadata read |
| List and inspect PRs | `GET /repos/{owner}/{repo}/pulls`, `GET /repos/{owner}/{repo}/pulls/{pull_number}` | `repo` for private repos, `public_repo` for public-only mode | Pull requests read |
| Read PR files | `GET /repos/{owner}/{repo}/pulls/{pull_number}/files` | `repo` for private repos, `public_repo` for public-only mode | Pull requests read |
| Read PR issue comments | `GET /repos/{owner}/{repo}/issues/{issue_number}/comments` | `repo` for private repos, `public_repo` for public-only mode | Pull requests read, or Issues read |
| Read PR review comments | `GET /repos/{owner}/{repo}/pulls/{pull_number}/comments` | `repo` for private repos, `public_repo` for public-only mode | Pull requests read |
| Read check runs | `GET /repos/{owner}/{repo}/commits/{ref}/check-runs` | `repo` for private repos | Checks read |
| Submit PR review | `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews` | `repo` for private repos, `public_repo` for public-only mode | Pull requests write |

Minimum first OAuth request:

- Private repository mode: request `repo`.
- Public-only mode, if added later: request `public_repo`, and block private repository selection until the user upgrades authorization.

Minimum future GitHub App permissions:

- Metadata: read.
- Pull requests: write. This covers PR listing, PR file reads, review comment reads, and review submission.
- Checks: read.
- Issues: read only if PR issue comments are not accessible through Pull requests read for a target installation.

## macOS UX Constraints

- Device flow codes expire after 15 minutes, so the sign-in sheet needs an explicit retry path.
- Polling must respect the returned `interval` and handle `authorization_pending`, `slow_down`, `expired_token`, and `access_denied`.
- The app should open the verification URL in the default browser and also provide a copyable code for users who prefer another browser/profile.
- The app should not expose manual personal-token entry as a fallback. If a legacy saved personal credential is found, it should not be used for API access; the app should require GitHub OAuth re-authorization.
- Tokens stay in the existing versioned Keychain credential store. The stored credential should record token kind, scopes, login, token type, creation/update timestamps, and future expiration fields.

## Follow-Up Implementation Issues

Created implementation issues:

1. #50 Implement OAuth App device-flow client.
2. #51 Add GitHub OAuth sign-in UI.
3. #52 Validate OAuth scopes and repository access.
4. #53 Add OAuth token revocation and replacement controls.
5. #91 Convert GitHub authentication to OAuth-only.

Deferred follow-up: revisit GitHub App user auth after the OAuth App device-flow MVP is stable.

## References Checked

- GitHub OAuth App device flow: <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps>
- GitHub OAuth scopes: <https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps>
- GitHub App user auth: <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-with-a-github-app-on-behalf-of-a-user>
- GitHub App user access tokens and device flow: <https://docs.github.com/en/enterprise-cloud@latest/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app>
- Repository listing permissions: <https://docs.github.com/en/rest/repos/repos>
- Pull request file and review permissions: <https://docs.github.com/en/rest/pulls/pulls> and <https://docs.github.com/en/rest/pulls/reviews>
- Check run permissions: <https://docs.github.com/en/rest/checks/runs>
- Issue comment permissions: <https://docs.github.com/en/rest/issues/comments>
