#!/usr/bin/env bash
#
# install.sh — macOS installer for the PR Review app.
#
# Remote usage:
#   curl -fsSL <url>/install.sh | bash
#
# This is an UNSIGNED build. The script auto-applies
#   xattr -dr com.apple.quarantine
# to the installed bundle so Gatekeeper does not block the first launch.
#
# Manual fallback: if macOS still blocks the app, right-click "PR Review" →
# "Open" (and confirm), or run:
#   xattr -dr com.apple.quarantine "/Applications/PR Review.app"
#
set -euo pipefail

# Release base URL (env override; default is a placeholder the maintainer
# replaces at P1).
RELEASE_BASE="${PR_REVIEW_RELEASE_BASE:-https://github.com/USER/REPO/releases/latest/download}"

APP_NAME="PR Review.app"

# --- Architecture detection -------------------------------------------------
arch="$(uname -m)"
case "$arch" in
  arm64|aarch64)
    tarball="pr-review-arm64.tar.gz"
    ;;
  x86_64)
    tarball="pr-review-x64.tar.gz"
    ;;
  *)
    echo "Error: unsupported architecture '${arch}'." >&2
    echo "Supported architectures: arm64/aarch64 (Apple Silicon), x86_64 (Intel)." >&2
    exit 1
    ;;
esac

url="${RELEASE_BASE}/${tarball}"

# --- Temp workspace ---------------------------------------------------------
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# --- Download ---------------------------------------------------------------
echo "Downloading ${tarball} from ${RELEASE_BASE} ..."
curl -fL --retry 3 -o "${tmpdir}/${tarball}" "$url"

# --- Extract ----------------------------------------------------------------
echo "Extracting ${tarball} ..."
tar -xzf "${tmpdir}/${tarball}" -C "$tmpdir"

# --- Locate the .app bundle (extracts at depth 1) ---------------------------
app_src="$(find "$tmpdir" -maxdepth 1 -name "$APP_NAME" -print -quit)"
if [[ -z "$app_src" ]]; then
  echo "Error: ${APP_NAME} was not found inside the archive." >&2
  exit 1
fi

# --- Destination selection --------------------------------------------------
dest_dir="/Applications"
if [[ ! -w "/Applications" ]]; then
  dest_dir="${HOME}/.local/Applications"
  mkdir -p "$dest_dir"
fi
dest="${dest_dir}/${APP_NAME}"

# --- Idempotent replace -----------------------------------------------------
if [[ -e "$dest" ]]; then
  echo "Replacing existing install at ${dest}"
  rm -rf "$dest"
fi

# --- Move into place --------------------------------------------------------
mv "$app_src" "$dest"

# --- Gatekeeper bypass (unsigned build) -------------------------------------
xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

# --- Done -------------------------------------------------------------------
echo "Installed PR Review to: ${dest}"
echo "Launch with: open \"${dest}\""
echo "If macOS still blocks the first launch, right-click the app → Open,"
echo "or run: xattr -dr com.apple.quarantine \"${dest}\""
