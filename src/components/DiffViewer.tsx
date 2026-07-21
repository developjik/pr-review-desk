/**
 * DiffViewer — renders a unified-diff hunk for a pending finding, with the
 * finding's new-side line highlighted.
 *
 * Pure presentation over the shared diff helpers:
 *   - parseHunkRows(hunk)   → classified rows (ctx / add / del / meta)
 *   - locateDiffLine(hunk, targetLine) → the row index to highlight
 *
 * Graceful fallbacks (AC1.7):
 *   - undefined/empty hunk → a compact "Diff unavailable" block
 *   - null targetLine (degraded / file-level finding) → hunk renders, no highlight
 */
import { locateDiffLine, parseHunkRows } from "@pr-review/shared";

interface DiffViewerProps {
  hunk: string | undefined;
  targetLine: number | null;
}

export default function DiffViewer({ hunk, targetLine }: DiffViewerProps) {
  if (!hunk || hunk.length === 0) {
    return (
      <div className="diff-viewer diff-viewer-empty placeholder">
        Diff unavailable — no stored diff hunk for this file.
      </div>
    );
  }

  const rows = parseHunkRows(hunk);
  const highlightIndex = locateDiffLine(hunk, targetLine);

  return (
    <div className="diff-viewer">
      <div className="diff-rows">
        {rows.map((row, i) => (
          <div
            key={i}
            className={[
              "diff-row",
              `diff-${row.type}`,
              i === highlightIndex ? "diff-highlight" : "",
            ]
              .filter(Boolean)
              .join(" ")}
          >
            <span className="diff-line-num">{row.newLine ?? ""}</span>
            {row.text}
          </div>
        ))}
      </div>
    </div>
  );
}
