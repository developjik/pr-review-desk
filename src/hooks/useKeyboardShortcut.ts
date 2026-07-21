/**
 * useKeyboardShortcut — register a global `keydown` shortcut.
 *
 * `key` is matched against `KeyboardEvent.key` (e.g. "k", ","). On macOS the
 * `meta` flag maps to the Cmd key (event.metaKey); on other platforms use
 * `ctrl`. Only fires the handler when every specified modifier matches exactly,
 * then calls `preventDefault()` to suppress the browser default. The listener
 * is added on mount and removed on cleanup.
 */
import { useEffect } from "react";

export interface KeyboardModifiers {
  meta?: boolean;
  ctrl?: boolean;
  shift?: boolean;
  alt?: boolean;
}

export function useKeyboardShortcut(
  key: string,
  modifiers: KeyboardModifiers,
  handler: () => void,
): void {
  const { meta, ctrl, shift, alt } = modifiers;

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key !== key) return;
      if (!!meta !== e.metaKey) return;
      if (!!ctrl !== e.ctrlKey) return;
      if (!!shift !== e.shiftKey) return;
      if (!!alt !== e.altKey) return;
      e.preventDefault();
      handler();
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [key, meta, ctrl, shift, alt, handler]);
}
