/**
 * Dialog — thin wrapper over Base UI Dialog.
 *
 * Wraps Base UI's accessible Dialog (focus trap + restore on close, Escape to
 * dismiss, backdrop-click to dismiss) and re-exposes the project's existing
 * class names so the CSS authored in Phase 2 Slice A still applies verbatim:
 *   - variant="slide-over" → `.slide-over` / `.slide-over-backdrop` /
 *                             `.slide-over-panel` (rendered as `<aside>` to match
 *                             the existing slide-over markup).
 *   - variant="settings"   → `.settings-overlay` / `.settings-overlay-backdrop`
 *                             / `.settings-overlay-card`.
 *
 * The wrapper class (`.slide-over` / `.settings-overlay`) provides the
 * `position: fixed; inset: 0; z-index: …` container — so the existing CSS
 * continues to drive layout without modification.
 *
 * Base UI is UNSTYLED. Controlled usage: `open` + `onOpenChange`. Children are
 * rendered inside the popup so Base UI's focus management covers them; callers
 * keep their existing close buttons (calling `onOpenChange(false)` on click).
 *
 * Phase 3: the slide-over panel uses motion/react for its spring entrance/exit
 * (transform x: '100%' → 0, spring stiffness 300 / damping 30) via the `render`
 * prop, while Base UI still owns focus management + portal lifecycle. The
 * AnimatePresence wrapper lets motion run its `exit` before the subtree is
 * removed. The settings variant stays unanimated (CSS-only) — motion here is
 * scoped to the slide-over only per the Phase 3 plan.
 */
import { type ReactNode } from "react";
import { motion, AnimatePresence } from "motion/react";
import { Dialog as BaseDialog } from "@base-ui-components/react/dialog";

export interface DialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  children: ReactNode;
  variant: "slide-over" | "settings";
  /** Accessible name for the dialog (rendered as aria-label). */
  label?: string;
}

export default function Dialog({
  open,
  onOpenChange,
  children,
  variant,
  label,
}: DialogProps) {
  const isSlideOver = variant === "slide-over";

  const wrapperClass = isSlideOver ? "slide-over" : "settings-overlay";
  const backdropClass = isSlideOver
    ? "slide-over-backdrop"
    : "settings-overlay-backdrop";
  const panelClass = isSlideOver ? "slide-over-panel" : "settings-overlay-card";

  return (
    <BaseDialog.Root
      open={open}
      onOpenChange={onOpenChange}
      disablePointerDismissal={false}
    >
      <AnimatePresence>
        {open && (
          <BaseDialog.Portal>
            <div className={wrapperClass}>
              <BaseDialog.Backdrop className={backdropClass} />
              {isSlideOver ? (
                // Base UI Popup renders a <div> by default; the slide-over CSS
                // expects an <aside class="slide-over-panel">. Swap the tag via
                // the `render` prop — using motion.aside here drives the spring
                // entrance/exit (transform only) while Base UI merges its own
                // props (open, focus management, aria) onto the same element.
                <BaseDialog.Popup
                  className={panelClass}
                  aria-label={label}
                  render={
                    <motion.aside
                      initial={{ x: "100%" }}
                      animate={{ x: 0 }}
                      exit={{ x: "100%" }}
                      transition={{ type: "spring", stiffness: 300, damping: 30 }}
                    />
                  }
                >
                  {children}
                </BaseDialog.Popup>
              ) : (
                <BaseDialog.Popup className={panelClass} aria-label={label}>
                  {children}
                </BaseDialog.Popup>
              )}
            </div>
          </BaseDialog.Portal>
        )}
      </AnimatePresence>
    </BaseDialog.Root>
  );
}
