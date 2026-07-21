/**
 * ShortcutHelp — keyboard-shortcut reference overlay.
 *
 * Rendered via the existing Base UI Dialog wrapper (variant="settings" →
 * centered `.settings-overlay-card`). Opened with the `?` global shortcut wired
 * in App.tsx and closed via the ✕ button, Escape (Base UI default), or backdrop
 * click. Labels are Korean to match the rest of the UI.
 */
import Dialog from "./ui/Dialog";
import Icon from "./ui/Icon";

export interface ShortcutHelpProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

interface ShortcutEntry {
  /** One or more key caps to render as <kbd> elements. */
  keys: string[];
  /** Korean description of what the shortcut does. */
  label: string;
}

const SHORTCUTS: ShortcutEntry[] = [
  { keys: ["⌘", "K"], label: "명령 팔레트" },
  { keys: ["⌘", ","], label: "설정" },
  { keys: ["Esc"], label: "닫기" },
  { keys: ["?"], label: "이 도움말" },
];

export default function ShortcutHelp({ open, onOpenChange }: ShortcutHelpProps) {
  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      variant="settings"
      label="단축키 도움말"
    >
      <button
        type="button"
        className="settings-overlay-close"
        aria-label="닫기"
        onClick={() => onOpenChange(false)}
      >
        <Icon name="x" />
      </button>
      <div className="shortcut-help">
        <header className="shortcut-help-header">
          <h3>단축키</h3>
          <p className="shortcut-help-subtitle">
            키보드로 앱을 빠르게 조작하세요.
          </p>
        </header>
        <dl className="shortcut-help-list">
          {SHORTCUTS.map((entry) => (
            <div className="shortcut-help-row" key={entry.label}>
              <dt className="shortcut-help-keys">
                {entry.keys.map((k) => (
                  <kbd key={k}>{k}</kbd>
                ))}
              </dt>
              <dd className="shortcut-help-label">{entry.label}</dd>
            </div>
          ))}
        </dl>
      </div>
    </Dialog>
  );
}
