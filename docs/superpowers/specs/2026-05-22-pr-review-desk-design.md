# PR Review Desk Design

## Goal

Build a personal macOS app that helps a developer review GitHub pull requests with Codex. The app should browse repositories and open PRs, generate an AI review draft, let the user edit and choose comments, and submit only the approved review back to GitHub.

## Scope

The MVP is personal and developer-focused. It does not need multi-user accounts, a backend server, GitHub OAuth, billing, or hosted automation.

The app uses:

- GitHub Personal Access Token for GitHub access, stored in macOS Keychain.
- Local Codex CLI login for AI review generation.
- GitHub REST API for repository browsing, PR browsing, diff retrieval, and review submission.
- SwiftPM so the project can build with the installed Command Line Tools.

## Core Flow

1. The user opens the macOS app.
2. The user enters a GitHub PAT if one is not already stored.
3. The app lists accessible repositories.
4. The user selects a repository.
5. The app lists open pull requests for that repository.
6. The user selects a pull request.
7. The app fetches PR metadata and changed files.
8. The user clicks Generate Review.
9. A local helper invokes `codex exec` in non-interactive mode with a structured JSON schema.
10. Codex returns a review draft with summary, risks, and inline comment candidates.
11. The app shows an editable review body and selectable inline comments.
12. The user selects `Comment`, `Approve`, or `Request changes`.
13. The app submits the review to GitHub.

## Architecture

The Swift package has three targets:

- `PRReviewDeskCore`: models, GitHub API client, diff position mapping, Keychain storage, Codex runner, and review orchestration.
- `PRReviewDeskApp`: SwiftUI macOS app that uses the core library.
- `PRReviewDeskCoreTests`: unit tests for core behavior.

The app keeps network and process execution behind protocols so core behavior can be tested without calling GitHub or Codex.

## GitHub Integration

The GitHub client uses REST endpoints:

- `GET /user/repos` to list accessible repositories.
- `GET /repos/{owner}/{repo}/pulls?state=open` to list open PRs.
- `GET /repos/{owner}/{repo}/pulls/{number}` to fetch PR metadata and head SHA.
- `GET /repos/{owner}/{repo}/pulls/{number}/files` to fetch changed files and patches.
- `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews` to submit a review.

Review submission uses:

- `event`: `COMMENT`, `APPROVE`, or `REQUEST_CHANGES`.
- `body`: edited review body.
- `comments`: selected inline comments with `path`, `position`, and `body`.

The GitHub docs specify that `position` is not the file line number; it is the number of lines down from the first diff hunk header in a file. The app therefore annotates patches with diff positions before sending them to Codex.

## Codex Integration

The Codex integration runs local `codex exec` with:

- `--skip-git-repo-check`
- `--sandbox read-only`
- `--ephemeral`
- `--output-schema <schema>`
- `--output-last-message <result-file>`

The prompt contains PR metadata and annotated patches. The output schema requires:

- `summary`: string
- `risks`: string array
- `inline_comments`: array of `{ path, position, body, severity }`

The app validates the JSON before showing it to the user. Invalid JSON, missing Codex login, missing `codex` binary, and process failures are shown as recoverable UI errors.

## UI

The MVP UI is a three-column SwiftUI layout:

- Left sidebar: repository list and refresh.
- Middle column: open PR list for the selected repository.
- Main pane: selected PR details, Generate Review action, editable review body, inline comment candidates, event picker, and Submit Review.

The app favors utilitarian density over a landing page. It is a work tool for repeated review sessions.

## Error Handling

The app reports:

- Missing GitHub token.
- Invalid or unauthorized GitHub token.
- Empty repository or PR lists.
- GitHub rate limit or validation errors.
- Missing Codex CLI.
- Codex process timeout or non-zero exit.
- Review submission failures from GitHub.

Secrets are never written to project files or logs.

## Testing

Unit tests cover:

- Diff position mapping from GitHub patch text.
- Codex output decoding and validation.
- Codex runner command construction and result parsing with a fake command runner.
- GitHub request construction and review payload encoding.

Manual verification covers:

- `swift test`
- `swift build`
- Codex CLI smoke test
- GitHub token smoke test against `/user`
- Running the app target

## Future Work

After MVP:

- Replace PAT with GitHub OAuth.
- Add local repository context for better review quality.
- Add background review generation for selected repositories.
- Add per-repository review policy prompts.
- Add GitHub App/server mode for team use.
