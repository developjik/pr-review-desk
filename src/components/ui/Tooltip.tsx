/**
 * Tooltip — thin wrapper over Base UI Tooltip.
 *
 * P4 SCAFFOLD: This wrapper + tooltip.css are scaffolded for Phase 4 surface
 * polish (tooltips on icon-only buttons, severity badges, etc.) but have ZERO
 * consumers as of P2. tooltip.css is imported by index.css and shipped in the
 * CSS bundle (452B); Tooltip.tsx is tree-shaken from JS until consumed. This
 * is intentional — the plan calls for Base UI Tooltip as a P2 deliverable, and
 * the wrapper is ready for P4 integration without further setup.
 *
 * Base UI gives accessible tooltip behavior (delay, dismiss on Escape, hover
 * + focus triggers, positioning via floating-ui) without any styling. This
 * wrapper exposes a `.tooltip` class on the popup so callers can theme it
 * purely via CSS (tokens only — see `src/styles/components/tooltip.css`).
 * `open` + `onOpenChange` is also supported.
 */
import { type ReactNode } from "react";
import { Tooltip as BaseTooltip } from "@base-ui-components/react/tooltip";

export interface TooltipProps {
  /** The hover/focus trigger element. */
  children: ReactNode;
  /** The tooltip content. */
  label: ReactNode;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  /** Disabled tooltips render nothing and skip the trigger wiring. */
  disabled?: boolean;
}

export default function Tooltip({
  children,
  label,
  open,
  onOpenChange,
  disabled,
}: TooltipProps) {
  if (disabled) return <>{children}</>;

  return (
    <BaseTooltip.Root open={open} onOpenChange={onOpenChange}>
      <BaseTooltip.Trigger
        render={children as React.ReactElement<Record<string, unknown>>}
      />
      <BaseTooltip.Portal>
        <BaseTooltip.Positioner sideOffset={6}>
          <BaseTooltip.Popup className="tooltip">{label}</BaseTooltip.Popup>
        </BaseTooltip.Positioner>
      </BaseTooltip.Portal>
    </BaseTooltip.Root>
  );
}
