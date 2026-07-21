/**
 * Tabs — thin wrapper over Base UI Tabs.
 *
 * Wires Base UI's Tabs behavior (arrow-key navigation, roving tabindex,
 * aria-selected, Home/End) to the project's existing `.tab-bar` / `.tab-item` /
 * `.tab-count` CSS authored in Phase 2 Slice A. Base UI is UNSTYLED — this
 * wrapper only adds behavior, all visual treatment stays in
 * `src/styles/components/tabs.css`.
 *
 * Controlled usage: `value` + `onValueChange`. The active class is applied via
 * a state-driven className callback (Base UI exposes `active` on each Tab's
 * state).
 */
import { type ReactNode } from "react";
import { Tabs as BaseTabs } from "@base-ui-components/react/tabs";

export interface TabsProps {
  value: string;
  onValueChange: (value: string) => void;
  children: ReactNode;
  /** className applied to the tab list wrapper (.tab-bar). */
  className?: string;
}

/**
 * A single tab button. Renders `<button class="tab-item">…</button>` with
 * Base UI's arrow-key + roving-tabindex behavior. The `active` class is added
 * when the tab is selected so the existing CSS continues to apply.
 */
export interface TabProps {
  value: string;
  children: ReactNode;
  className?: string;
}

export function Tab({ value, children, className }: TabProps) {
  return (
    <BaseTabs.Tab
      value={value}
      className={(state) =>
        ["tab-item", state.active ? "active" : "", className ?? ""]
          .filter(Boolean)
          .join(" ")
      }
    >
      {children}
    </BaseTabs.Tab>
  );
}

export interface TabListProps {
  children: ReactNode;
  className?: string;
}

export function TabList({ children, className }: TabListProps) {
  return (
    <BaseTabs.List
      className={["tab-bar", className].filter(Boolean).join(" ")}
    >
      {children}
    </BaseTabs.List>
  );
}

export default function Tabs({
  value,
  onValueChange,
  children,
  className,
}: TabsProps) {
  return (
    <BaseTabs.Root
      value={value}
      onValueChange={(next) => onValueChange(String(next))}
      className={className}
    >
      {children}
    </BaseTabs.Root>
  );
}
