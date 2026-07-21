/**
 * HelpInstall — install / code-signing help overlay.
 *
 * Rendered via the existing Base UI Dialog wrapper (variant="settings" →
 * centered `.settings-overlay-card`). Opened from the Settings page and closed
 * via the ✕ button, Escape (Base UI default), or backdrop click. Labels are
 * Korean to match the rest of the UI; a compact English line is included for
 * the unsigned-install bypass.
 *
 * The bypass one-liner is the single source of truth and must match the README
 * install section verbatim.
 */
import Dialog from "./ui/Dialog";
import Icon from "./ui/Icon";

export interface HelpInstallProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const BYPASS_COMMAND = `xattr -dr com.apple.quarantine "/Applications/PR Review.app"`;

export default function HelpInstall({ open, onOpenChange }: HelpInstallProps) {
  return (
    <Dialog
      open={open}
      onOpenChange={onOpenChange}
      variant="settings"
      label="설치 / 서명 안내"
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
          <h3>설치 / 서명 안내</h3>
          <p className="shortcut-help-subtitle">
            This app is unsigned. macOS may block the first launch.
          </p>
        </header>

        <p style={{ margin: "0 0 12px" }}>
          이 앱은 서명되지 않았습니다. macOS가 처음 실행을 차단할 수 있습니다.
        </p>

        <ol
          style={{
            margin: "0 0 12px",
            paddingLeft: "1.25em",
            display: "flex",
            flexDirection: "column",
            gap: "8px",
          }}
        >
          <li>
            앱을 우클릭 → Open(열기) 한 뒤 열기 확인.
            <span
              style={{
                display: "block",
                color: "var(--muted)",
                fontSize: "var(--fs-sm)",
              }}
            >
              Right-click the app → Open, then confirm.
            </span>
          </li>
          <li>
            그래도 차단되면 터미널에서:
            <span
              style={{
                display: "block",
                color: "var(--muted)",
                fontSize: "var(--fs-sm)",
              }}
            >
              If still blocked, run in Terminal:
            </span>
            <pre
              style={{
                margin: "6px 0 0",
                padding: "10px 12px",
                background: "var(--surface-2)",
                border: "1px solid var(--border)",
                borderRadius: "var(--r-input)",
                overflowX: "auto",
              }}
            >
              <code
                style={{
                  fontFamily: "var(--font-mono)",
                  fontSize: "var(--fs-sm)",
                  padding: 0,
                  background: "none",
                }}
              >
                {BYPASS_COMMAND}
              </code>
            </pre>
          </li>
        </ol>
      </div>
    </Dialog>
  );
}
