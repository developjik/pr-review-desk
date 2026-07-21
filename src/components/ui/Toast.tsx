/**
 * Toast — ephemeral notification system (P5).
 *
 * ToastProvider owns the toast queue and a SINGLE `daemon://error`
 * subscription (the first and only consumer of that event today). It renders
 * a body-end portal live-region (`role="status" aria-live="polite"`) so
 * toasts stay announced even under Base UI overlays.
 *
 * `useToast()` exposes five stable methods: success / warning / error / info /
 * dismiss. The queue is capped at 5 (oldest dropped on overflow); error
 * toasts are sticky (dismiss-on-click only), the rest auto-dismiss after
 * 4000ms. The context value is memoized so consumers don't re-render on every
 * push.
 *
 * Enter animation uses motion/react (opacity + transform only, ≤ --dur-base).
 * Exit is a plain unmount for v1 (no exit animation). Honors reduced-motion
 * via <MotionConfig reducedMotion="user"> in main.tsx plus the defensive CSS
 * neutralizer in toast.css.
 */
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { motion } from "motion/react";
import { onDaemonError } from "../../lib/tauri";
import {
  pushToast,
  dismissToast,
  initialToastQueueState,
  type ToastQueueState,
} from "../../lib/toastQueue";

// ---------------------------------------------------------------------------
// types
// ---------------------------------------------------------------------------

export type ToastVariant = "success" | "warning" | "error" | "info";

export interface ToastItem {
  id: number;
  variant: ToastVariant;
  title: string;
  desc?: string;
  createdAt: number;
}

export interface ToastApi {
  success: (title: string, desc?: string) => number;
  warning: (title: string, desc?: string) => number;
  error: (title: string, desc?: string) => number;
  info: (title: string, desc?: string) => number;
  dismiss: (id: number) => void;
}

export interface ToastProps {
  item: ToastItem;
  onDismiss: (id: number) => void;
}

// ---------------------------------------------------------------------------
// constants
// ---------------------------------------------------------------------------

/** Max toasts on screen at once; oldest is dropped on overflow. */
const MAX_TOASTS = 5;
/** Auto-dismiss delay (ms) for non-error variants. Errors are sticky. */
const AUTO_DISMISS_MS = 4000;

// ---------------------------------------------------------------------------
// context
// ---------------------------------------------------------------------------

const ToastContext = createContext<ToastApi | null>(null);

/**
 * Access the toast queue. Must be called inside a `<ToastProvider>`, otherwise
 * it throws a clear dev error.
 */
export function useToast(): ToastApi {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    throw new Error("useToast must be used within ToastProvider");
  }
  return ctx;
}

// ---------------------------------------------------------------------------
// Toast item
// ---------------------------------------------------------------------------

function Toast({ item, onDismiss }: ToastProps) {
  return (
    <motion.div
      className={`toast toast--${item.variant}`}
      initial={{ opacity: 0, x: 8 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.2, ease: "easeOut" }}
      onClick={() => onDismiss(item.id)}
    >
      <div className="toast-content">
        <div className="toast-title">{item.title}</div>
        {item.desc ? <div className="toast-desc">{item.desc}</div> : null}
      </div>
      <button
        type="button"
        className="toast-close"
        aria-label="알림 닫기"
        onClick={() => onDismiss(item.id)}
      >
        ×
      </button>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// provider
// ---------------------------------------------------------------------------

export function ToastProvider({ children }: { children: ReactNode }) {
  // Pure-reducer-backed queue. `nextIdRef` is the synchronous id counter the
  // caller owns; the id is passed INTO the pure reducer (pushToast) so batched
  // pushes never collide on a stale state.nextId read. The reducer still owns
  // state correctness (advances nextId to id+1); the ref is only for the
  // synchronous read/return/timer-key path.
  const [queue, setQueue] = useState<ToastQueueState>(initialToastQueueState);
  const nextIdRef = useRef(initialToastQueueState.nextId);
  // F8: autodismiss timers keyed by toast id, so dismiss + unmount can clean
  // them up. Error toasts never get an entry (sticky).
  const timers = useRef<Map<number, ReturnType<typeof setTimeout>>>(new Map());

  const dismiss = useCallback((id: number) => {
    setQueue((q) => dismissToast(q, id));
    const timer = timers.current.get(id);
    if (timer !== undefined) {
      clearTimeout(timer);
      timers.current.delete(id);
    }
  }, []);

  const push = useCallback(
    (variant: ToastVariant, title: string, desc?: string) => {
      // Synchronous id generation: read + advance the ref in one step so two
      // pushes in the same tick get distinct ids (no stale-state race). The id
      // is passed INTO the pure reducer (pushToast) — the reducer no longer
      // derives it from state.nextId.
      const id = nextIdRef.current;
      nextIdRef.current = id + 1;
      const now = Date.now();
      setQueue((q) => pushToast(q, id, variant, title, desc, MAX_TOASTS, now));
      // Errors are sticky (dismiss-on-click only); everything else auto-dismisses.
      if (variant !== "error") {
        const timer = setTimeout(() => dismiss(id), AUTO_DISMISS_MS);
        timers.current.set(id, timer);
      }
      return id;
    },
    [dismiss],
  );

  const api = useMemo<ToastApi>(
    () => ({
      success: (title, desc) => push("success", title, desc),
      warning: (title, desc) => push("warning", title, desc),
      error: (title, desc) => push("error", title, desc),
      info: (title, desc) => push("info", title, desc),
      dismiss,
    }),
    [push, dismiss],
  );

  // F8: clear every outstanding autodismiss timer when the provider unmounts.
  useEffect(() => {
    const active = timers.current;
    return () => {
      for (const timer of active.values()) clearTimeout(timer);
      active.clear();
    };
  }, []);

  // Single app-wide daemon://error subscription. Pushes a sticky error toast
  // on every event. `push` is stable (useCallback), so this subscribes exactly
  // once; the disposed-flag handles the async unlisten if the provider unmounts
  // before the listener resolves (also covers StrictMode dev double-invoke).
  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | null = null;

    onDaemonError((_code, err) => {
      if (disposed) return;
      push("error", "데몬 오류", err);
    }).then((fn) => {
      if (disposed) {
        fn();
      } else {
        unlisten = fn;
      }
    });

    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [push]);

  return (
    <ToastContext.Provider value={api}>
      {children}
      {createPortal(
        <div className="toast-stack" role="status" aria-live="polite">
          {queue.toasts.map((t) => (
            <Toast key={t.id} item={t} onDismiss={dismiss} />
          ))}
        </div>,
        document.body,
      )}
    </ToastContext.Provider>
  );
}

export default Toast;
