/**
 * Pure, dependency-free file-path glob matcher.
 *
 * Mirrors the escape-then-translate approach of {@link ../poller/filter.repoGlob},
 * extended with globstar support for repo-relative file paths (which, unlike
 * owner/repo names, contain slashes).
 *
 * Matcher contract (LOAD-BEARING):
 *   - Case-insensitive: both sides lowercased before matching.
 *   - Zero new deps (no picomatch/minimatch).
 *   - Regex-escaped, anchored (full match), linear. See the inline comments in
 *     {@link matchPath} for the exact per-metachar translation. A globstar
 *     followed by a slash compiles to an OPTIONAL zero-or-more-dirs group, so a
 *     leading-globstar pattern matches root-level files (the M1 fix). A bare
 *     globstar spans slashes. A single star and a question mark are
 *     segment-local (they never cross a slash).
 *   - Translation order is critical: escape, then globstar-with-slash, then
 *     globstar, then star, then question. The globstar-with-slash form MUST be
 *     translated before bare globstar so the optional-dir group is emitted
 *     instead of a greedy span plus a literal slash.
 */

/**
 * Match a single glob `pattern` against a file path.
 *
 * Both sides are lowercased first. Regex specials in the pattern are escaped
 * (so `.`, `+`, `(`, etc. match literally), then the escaped glob metachars
 * are translated; see the inline comments for the exact per-form output. The
 * result is anchored to the full string. Always returns a real boolean.
 */
export function matchPath(pattern: string, path: string): boolean {
  const p = pattern.toLowerCase();
  const f = path.toLowerCase();
  // Escape every regex special (. + * ? ^ $ ( ) [ ] { } | \), then translate
  // the escaped glob forms. After escaping, a glob star becomes backslash-star
  // and a glob question mark becomes backslash-question.
  const escaped = p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const translated = escaped
    // Globstar-with-slash FIRST: zero-or-more dirs, OPTIONAL. This is the M1
    // root-level fix — a pattern like star-star-slash-star.ts matches a
    // root-level file as well as a nested one.
    .replace(/\\\*\\\*\//g, "(?:.*/)?")
    // Remaining globstar: spans slashes (greedy).
    .replace(/\\\*\\\*/g, ".*")
    // Segment-local star: never crosses a slash.
    .replace(/\\\*/g, "[^/]*")
    // Segment-local question mark: matches exactly one non-slash char.
    .replace(/\\\?/g, "[^/]");
  return new RegExp("^" + translated + "$").test(f);
}

/**
 * True if ANY pattern matches the path (case-insensitive, via {@link matchPath}).
 * An empty `patterns` array matches nothing (an inert rule set).
 */
export function matchAnyPath(path: string, patterns: string[]): boolean {
  return patterns.length > 0 && patterns.some((p) => matchPath(p, path));
}
