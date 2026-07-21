/**
 * AlertDialog — thin wrapper over Base UI AlertDialog.
 *
 * Wraps Base UI's accessible dialog (focus trap, roving tabindex, Escape to
 * close, backdrop click to dismiss) and re-exposes the project's existing
 * class names (.alert-dialog / .alert-dialog-backdrop / .alert-dialog-panel /
 * .alert-dialog-title / .alert-dialog-description / .alert-dialog-actions) so
 * the accompanying CSS in src/styles/components/alert-dialog.css controls all
 * the visual treatment. Base UI is UNSTYLED — this wrapper only wires
 * behavior to the existing CSS classes.
 *
 * Usage is controlled (open + onOpenChange). The destructive trigger is
 * rendered via the `children` prop so callers can keep their existing
 * Reject / Clear buttons as the visual entry point — clicking it opens the
 * dialog instead of immediately firing the destructive action. The actual
 * destructive call is made via `onConfirm` when the confirm button is pressed.
 *
 * IMPORTANT: when passing `children` as a trigger, the element must NOT carry
 * an `onClick` that fires the destructive action — that handler should move to
 * `onConfirm`. Base UI merges event handlers, so a leftover onClick would fire
 * immediately on click in addition to opening the dialog.
 */
import { useState, type ReactNode } from "react";
import { AlertDialog as BaseAlertDialog } from "@base-ui-components/react/alert-dialog";

export interface AlertDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description: string;
  confirmLabel: string;
  cancelLabel: string;
  onConfirm: () => void | Promise<void>;
  /** The trigger element (typically the existing destructive button). */
  children?: ReactNode;
}

export default function AlertDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel,
  cancelLabel,
  onConfirm,
  children,
}: AlertDialogProps) {
  const [loading, setLoading] = useState(false);

  const handleConfirm = async () => {
    setLoading(true);
    try {
      await onConfirm?.();
      onOpenChange(false); // close on success
    } catch (e) {
      // Keep the dialog open so the user can retry; the caller surfaces the
      // failure via useToast().error(...). Logged to avoid a swallowed rejection.
      console.error("[AlertDialog] onConfirm rejected:", e);
      setLoading(false);
    }
  };

  return (
    <BaseAlertDialog.Root open={open} onOpenChange={onOpenChange}>
      {children != null && (
        <BaseAlertDialog.Trigger
          render={children as React.ReactElement<Record<string, unknown>>}
        />
      )}
      <BaseAlertDialog.Portal>
        <BaseAlertDialog.Backdrop className="alert-dialog-backdrop" />
        <BaseAlertDialog.Popup className="alert-dialog-panel">
          <BaseAlertDialog.Title className="alert-dialog-title">
            {title}
          </BaseAlertDialog.Title>
          <BaseAlertDialog.Description className="alert-dialog-description">
            {description}
          </BaseAlertDialog.Description>
          <div className="alert-dialog-actions">
            <BaseAlertDialog.Close
              className="btn btn-secondary"
              onClick={() => onOpenChange(false)}
            >
              {cancelLabel}
            </BaseAlertDialog.Close>
            <button
              type="button"
              className="btn alert-dialog-confirm"
              onClick={handleConfirm}
              data-loading={loading}
              disabled={loading}
              aria-busy={loading}
            >
              {confirmLabel}
            </button>
          </div>
        </BaseAlertDialog.Popup>
      </BaseAlertDialog.Portal>
    </BaseAlertDialog.Root>
  );
}
