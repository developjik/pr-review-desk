# PR Review v<VERSION>

> macOS 전용 · 서명되지 않은 앱입니다. 첫 실행 시 Gatekeeper 우회가 필요합니다.
>
> _macOS only · unsigned build. The first launch requires a Gatekeeper bypass._

## 다운로드 / Downloads

| 아키텍처 / Architecture | DMG | tar.gz |
| --- | --- | --- |
| Apple Silicon (aarch64) | `PR Review_<VERSION>_aarch64.dmg` | `pr-review-arm64.tar.gz` |
| Intel (x64) | `PR Review_<VERSION>_x64.dmg` | `pr-review-x64.tar.gz` |

## 설치 / Install

터미널 한 줄 설치 (권장):

```bash
curl -fsSL https://example.com/pr-review/install.sh | bash
```

DMG로 수동 설치 시, DMG를 열고 `PR Review.app`를 응용프로그램으로 드래그한 뒤 첫 실행에서 우클릭 → 열기(Open)로 진입하세요.
_Manual DMG install: open the DMG, drag `PR Review.app` to Applications, then right-click → Open on first launch._

## Gatekeeper 우회 / Bypass

```bash
xattr -dr com.apple.quarantine "/Applications/PR Review.app"
```

## 체크섬 / Checksums

<!-- P1: paste shasum -a 256 of each artifact here before publishing. -->
