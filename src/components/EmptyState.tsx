/**
 * EmptyState — generic placeholder for empty / loading / waiting panels.
 *
 * Renders a line icon, a short title, a longer message, and an optional CTA
 * button. Styled purely via the `.empty-state*` classes in
 * src/styles/components/empty-state.css so it inherits the dark theme
 * tokens (--muted / --accent / --surface).
 *
 * Phase 3: root uses a motion.div fade-up entrance (opacity + transform only,
 * ≤180 ms ease-out). Honors prefers-reduced-motion via the global neutralizer
 * in base.css plus motion's built-in reduced-motion handling.
 */
import { motion } from "motion/react";
import Icon, { type IconName } from "./ui/Icon";

interface EmptyStateProps {
  /** Line icon shown above the title. */
  icon: IconName;
  /** One-line heading. */
  title: string;
  /** Supporting paragraph shown beneath the title. */
  message: string;
  /** When provided alongside `onCta`, renders a call-to-action button. */
  ctaLabel?: string;
  /** Click handler for the CTA button. */
  onCta?: () => void;
}

function EmptyState({
  icon,
  title,
  message,
  ctaLabel,
  onCta,
}: EmptyStateProps) {
  const hasCta = Boolean(ctaLabel && onCta);
  return (
    <motion.div
      className="empty-state"
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.18, ease: "easeOut" }}
    >
      <span className="empty-state-icon" aria-hidden="true">
        <Icon name={icon} size="lg" />
      </span>
      <span className="empty-state-title">{title}</span>
      <span className="empty-state-message">{message}</span>
      {hasCta && (
        <button type="button" className="empty-state-cta" onClick={onCta}>
          {ctaLabel}
        </button>
      )}
    </motion.div>
  );
}

export default EmptyState;
