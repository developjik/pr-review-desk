/**
 * CommandPalette — ⌘K command search overlay.
 *
 * Renders a centered modal with a search input and a filtered command list.
 * Keyboard model:
 *   • ↑/↓     navigate the list
 *   • Enter   run the active command and close
 *   • Escape  close without running
 *   • Tab     trapped within the dialog (cycles input ↔ items)
 *
 * The parent owns the command list and the `open` state; this component is
 * purely presentational. The list is filtered client-side by label substring.
 *
 * State reset on open uses the render-phase "adjust state when a prop changes"
 * pattern (React docs) rather than an effect, to avoid cascading renders. The
 * only effect performs a DOM side effect (focusing the input).
 */
import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent,
} from "react";
import Icon, { type IconName } from "./ui/Icon";

export interface Command {
  id: string;
  label: string;
  /** Optional line icon shown before the label. */
  icon?: IconName;
  /** Optional right-aligned hint (e.g. a shortcut). */
  hint?: string;
  run: () => void;
}

interface CommandPaletteProps {
  open: boolean;
  commands: Command[];
  onClose: () => void;
}

/** CSS selector for focus-trap cycling. */
const FOCUSABLE =
  'a[href],button:not([disabled]),input:not([disabled]),textarea,select,[tabindex]:not([tabindex="-1"])';

export default function CommandPalette({
  open,
  commands,
  onClose,
}: CommandPaletteProps) {
  const [prevOpen, setPrevOpen] = useState(open);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  // Element that had focus when the palette opened; restored on close so the
  // WCAG 2.4.3 focus-restore contract holds (focus does not fall to body).
  const previousFocusRef = useRef<HTMLElement | null>(null);

  // Reset the query + selection whenever the palette (re)opens. Done during
  // render (guarded by the open transition) rather than in an effect.
  if (open !== prevOpen) {
    setPrevOpen(open);
    setQuery("");
    setActive(0);
  }

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return commands;
    return commands.filter((c) => c.label.toLowerCase().includes(q));
  }, [query, commands]);

  // Focus the input when the palette opens; restore focus to the previously
  // focused element when it closes (WCAG 2.4.3 — focus does not fall to body).
  // Guard: only restore if focus is still on the palette (or body) at close —
  // if a selected command already moved focus elsewhere (e.g. opened a
  // dialog), leave focus where it is.
  useEffect(() => {
    if (!open) {
      const prev = previousFocusRef.current;
      const current = document.activeElement;
      const stillOnPalette =
        !current ||
        current === document.body ||
        (dialogRef.current && dialogRef.current.contains(current));
      if (prev && stillOnPalette) {
        prev.focus();
      }
      previousFocusRef.current = null;
      return;
    }
    previousFocusRef.current = document.activeElement as HTMLElement | null;
    const id = requestAnimationFrame(() => inputRef.current?.focus());
    return () => cancelAnimationFrame(id);
  }, [open]);

  // Clamp the active index at read-time so a shrinking filtered list can never
  // point past the last item.
  const safeActive =
    filtered.length === 0 ? 0 : Math.min(active, filtered.length - 1);

  if (!open) return null;

  const run = (cmd?: Command) => {
    if (!cmd) return;
    // Restore focus to the original trigger BEFORE running the command. If the
    // command opens a Base UI Dialog, that dialog captures focus from the
    // trigger (not from the palette) and later restores to it on close — so
    // focus never falls to document.body. Clear the ref so the close-effect
    // does not double-restore.
    previousFocusRef.current?.focus();
    previousFocusRef.current = null;
    cmd.run();
    onClose();
  };

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    switch (e.key) {
      case "Escape":
        e.preventDefault();
        onClose();
        break;
      case "ArrowDown":
        e.preventDefault();
        setActive(filtered.length ? (safeActive + 1) % filtered.length : 0);
        break;
      case "ArrowUp":
        e.preventDefault();
        setActive(
          filtered.length
            ? (safeActive - 1 + filtered.length) % filtered.length
            : 0,
        );
        break;
      case "Enter":
        e.preventDefault();
        run(filtered[safeActive]);
        break;
      case "Tab": {
        // Focus trap — cycle through focusable descendants only.
        e.preventDefault();
        const items = dialogRef.current
          ? Array.from(
              dialogRef.current.querySelectorAll<HTMLElement>(FOCUSABLE),
            )
          : [];
        if (items.length === 0) return;
        const current = document.activeElement as HTMLElement | null;
        const idx = current ? items.indexOf(current) : -1;
        const next = e.shiftKey
          ? (idx - 1 + items.length) % items.length
          : (idx + 1) % items.length;
        items[next]?.focus();
        break;
      }
      default:
        break;
    }
  };

  return (
    <div className="command-palette">
      <div className="palette-backdrop" onClick={onClose} aria-hidden="true" />
      <div
        ref={dialogRef}
        className="palette-dialog"
        role="dialog"
        aria-modal="true"
        aria-label="Command palette"
        onKeyDown={onKeyDown}
      >
        <input
          ref={inputRef}
          className="palette-input"
          type="text"
          placeholder="명령을 검색하세요…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          autoComplete="off"
          spellCheck={false}
        />
        <div className="palette-list">
          {filtered.length === 0 ? (
            <div className="palette-empty">일치하는 명령이 없어요.</div>
          ) : (
            filtered.map((cmd, i) => (
              <button
                key={cmd.id}
                type="button"
                className={`palette-item ${i === safeActive ? "selected" : ""}`}
                onMouseEnter={() => setActive(i)}
                onClick={() => run(cmd)}
              >
                <span className="palette-item-icon" aria-hidden="true">
                  <Icon name={cmd.icon ?? "search"} />
                </span>
                <span className="palette-item-label">{cmd.label}</span>
                {cmd.hint && (
                  <span className="palette-item-hint">{cmd.hint}</span>
                )}
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
