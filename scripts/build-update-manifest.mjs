#!/usr/bin/env node
// build-update-manifest.mjs — assemble the tauri-plugin-updater `latest.json`
// release manifest from the 4 downloaded per-platform updater artifacts.
//
// Run by the release CI `release` job AFTER all `build` matrix jobs upload their
// signed updater bundles (.app.tar.gz / .AppImage.tar.gz / *-setup.nsis.zip +
// their .sig). Produces latest.json on stdout.
//
// Usage:
//   node scripts/build-update-manifest.mjs \
//     --artifacts out \
//     --tag v0.2.0 \
//     --repo OWNER/REPO \
//     --version 0.2.0 \
//     --notes RELEASE_NOTES.md
//
// `out/` is expected to contain one subdirectory per platform, each holding the
// signed updater bundle + its .sig file (produced by `tauri build` when
// TAURI_SIGNING_PRIVATE_KEY is set). Unknown/missing platforms are skipped with
// a stderr warning; the manifest omits them rather than failing, so a partial
// release (e.g. only mac signed) still yields a valid (if incomplete) manifest.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 2) {
    const k = argv[i]?.replace(/^--/, "");
    args[k] = argv[i + 1];
  }
  return args;
}

// Per-platform updater-bundle matcher + manifest key.
// Tauri produces: mac -> *.app.tar.gz, linux -> *.AppImage.tar.gz,
// win -> *-setup.nsis.zip. Each has a sibling <bundle>.sig with the signature.
const PLATFORMS = [
  { dir: "pr-review-arm64", key: "darwin-aarch64", bundleGlob: /\.app\.tar\.gz$/i },
  { dir: "pr-review-x64", key: "darwin-x86_64", bundleGlob: /\.app\.tar\.gz$/i },
  { dir: "pr-review-linux", key: "linux-x86_64", bundleGlob: /\.AppImage\.tar\.gz$/i },
  { dir: "pr-review-win", key: "windows-x86_64", bundleGlob: /-setup\.nsis\.zip$/i },
];

function listFiles(dir) {
  try {
    return readdirSync(dir).filter((f) => {
      const st = statSync(join(dir, f));
      return st.isFile();
    });
  } catch {
    return [];
  }
}

const { artifacts, tag, repo, version, notes } = parseArgs(process.argv);

if (!artifacts || !tag || !repo || !version) {
  console.error(
    "usage: build-update-manifest.mjs --artifacts <dir> --tag <vX> --repo <owner/repo> --version <x.y.z> [--notes <file>]",
  );
  process.exit(2);
}

const baseUrl = `https://github.com/${repo}/releases/download/${encodeURIComponent(tag)}`;
const notesText = notes ? readFileSync(notes, "utf8").trim() : "";

const platforms = {};
for (const p of PLATFORMS) {
  const dir = join(artifacts, p.dir);
  const files = listFiles(dir);
  const bundle = files.find((f) => p.bundleGlob.test(f) && !f.endsWith(".sig"));
  const sig = bundle ? files.find((f) => f === `${bundle}.sig`) : undefined;
  if (!bundle || !sig) {
    console.error(`build-update-manifest: skipping ${p.key} — missing bundle/sig in ${dir}`);
    continue;
  }
  const signature = readFileSync(join(dir, sig), "utf8").trim();
  platforms[p.key] = { signature, url: `${baseUrl}/${bundle}` };
}

const manifest = {
  version,
  notes: notesText,
  pub_date: new Date().toISOString(),
  platforms,
};

process.stdout.write(JSON.stringify(manifest, null, 2) + "\n");
console.error(`build-update-manifest: emitted latest.json with ${Object.keys(platforms).length} platform(s)`);
