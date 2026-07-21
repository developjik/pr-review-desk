/**
 * App — root component.
 *
 * Layout: a fixed left sidebar (Inbox / Logs) + scrollable main content. The
 * sidebar header is a DaemonStatusBadge (status dot + poll countdown +
 * in-flight review). Settings is no longer a sidebar tab: it opens as a
 * fullscreen overlay via ⌘, (or the footer link) and closes on Escape /
 * backdrop click. On first run (no persisted config) the Wizard renders as a
 * fullscreen overlay on top of the app shell.
 */
import { useCallback, useEffect, useState } from "react";
import Wizard from "./routes/Wizard";
import Settings from "./routes/Settings";
import Monitoring from "./routes/Monitoring";
import Logs from "./routes/Logs";
import Pending from "./routes/Pending";
import DaemonStatusBadge from "./components/DaemonStatusBadge";
import CommandPalette, { type Command } from "./components/CommandPalette";
import {
  DEFAULT_CONFIG,
  getConfig,
  isConfigComplete,
  normalizeConfig,
  pauseDaemon,
  pollNow,
  resumeDaemon,
  type UiConfig,
} from "./lib/tauri";
import { useDaemonStatus } from "./hooks/useDaemonStatus";
import { usePollClock } from "./hooks/usePollClock";
import { useReviewQueue } from "./hooks/useReviewQueue";
import { usePendingReviews } from "./hooks/usePendingReviews";
import { useKeyboardShortcut } from "./hooks/useKeyboardShortcut";
import "./styles/tokens.css";
import "./styles/base.css";
import "./styles/index.css";
import Dialog from "./components/ui/Dialog";
import ShortcutHelp from "./components/ShortcutHelp";
import HelpInstall from "./components/HelpInstall";
import Icon, { type IconName } from "./components/ui/Icon";
import { useToast } from "./components/ui/Toast";

type TabId = "inbox" | "logs" | "pending";

interface NavItem {
  id: TabId;
  icon: IconName;
  label: string;
  component: () => React.ReactNode;
}

function App() {
  const [config, setConfig] = useState<UiConfig | null>(null);
  const [configLoaded, setConfigLoaded] = useState(false);
  const [wizardDone, setWizardDone] = useState(false);
  const [activeTab, setActiveTab] = useState<TabId>("inbox");
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [helpOpen, setHelpOpen] = useState(false);
  const [installHelpOpen, setInstallHelpOpen] = useState(false);
  const daemon = useDaemonStatus();
  const { nextPollInSec } = usePollClock(
    config?.pollIntervalMin ?? DEFAULT_CONFIG.pollIntervalMin,
  );
  const { inProgressPrId, prLookup } = useReviewQueue();
  const { pending: pendingReviews } = usePendingReviews();
  const toast = useToast();

  // ⌘, toggles Settings overlay; Escape closes it.
  const toggleSettings = useCallback(() => setSettingsOpen((v) => !v), []);
  const closeSettings = useCallback(() => setSettingsOpen(false), []);
  useKeyboardShortcut(",", { meta: true }, toggleSettings);
  useKeyboardShortcut("Escape", {}, closeSettings);
  // ⌘K toggles the command palette.
  const togglePalette = useCallback(() => setPaletteOpen((v) => !v), []);
  const closePalette = useCallback(() => setPaletteOpen(false), []);
  useKeyboardShortcut("k", { meta: true }, togglePalette);
  // ? opens the shortcut help overlay.
  useKeyboardShortcut("?", { shift: true }, () => setHelpOpen(true));

  // Load persisted config to determine first-run.
  useEffect(() => {
    getConfig()
      .then((raw) => {
        const cfg = normalizeConfig(raw);
        setConfig(cfg);
        if (isConfigComplete(cfg)) {
          setWizardDone(true);
        }
      })
      .catch(() => setConfig(null))
      .finally(() => setConfigLoaded(true));
  }, []);

  // ---- Loading state --------------------------------------------------------
  if (!configLoaded) {
    return (
      <main className="app">
        <div className="splash">
          <div className="spinner" />
          <p className="placeholder">Loading…</p>
        </div>
      </main>
    );
  }

  // ---- First run: Wizard fullscreen overlay ---------------------------------
  if (!wizardDone) {
    return (
      <div className="wizard-overlay">
        <Wizard
          initialConfig={config ?? normalizeConfig(null)}
          onComplete={() => setWizardDone(true)}
        />
      </div>
    );
  }

  // ---- Waiting for daemon ready (after config exists) -----------------------
  if (!daemon.online) {
    return (
      <main className="app">
        <div className="splash">
          <div className="spinner" />
          <p className="placeholder">Starting daemon…</p>
          <p className="placeholder">State: {daemon.state}</p>
        </div>
      </main>
    );
  }

  // ---- Sidebar shell --------------------------------------------------------
  const showPendingTab =
    config?.reviewMode === "pending" || pendingReviews.length > 0;
  const allNav: NavItem[] = [
    {
      id: "inbox",
      icon: "inbox",
      label: "Inbox",
      component: () => <Monitoring />,
    },
    { id: "logs", icon: "file-text", label: "Logs", component: () => <Logs /> },
    {
      id: "pending",
      icon: "hourglass",
      label: "Pending",
      component: () => <Pending />,
    },
  ];
  const NAV: readonly NavItem[] = allNav.filter(
    (item) => item.id !== "pending" || showPendingTab,
  );
  // Command palette actions (Pause/Resume are contextual on daemon state).
  const commands: Command[] = [
    {
      id: "poll-now",
      label: "Poll Now",
      icon: "refresh-cw",
      hint: "즉시 폴링",
      run: async () => {
        try {
          await pollNow();
          toast.info("폴링을 시작했어요.");
        } catch (e) {
          toast.error("폴링 시작에 실패했어요.", String(e));
        }
      },
    },
    {
      id: "open-settings",
      label: "Open Settings",
      icon: "settings",
      hint: "⌘,",
      run: () => setSettingsOpen(true),
    },
    {
      id: "go-inbox",
      label: "Go to Inbox",
      icon: "inbox",
      run: () => setActiveTab("inbox"),
    },
    {
      id: "go-logs",
      label: "Go to Logs",
      icon: "file-text",
      run: () => setActiveTab("logs"),
    },
    daemon.state === "paused"
      ? {
          id: "resume-daemon",
          label: "Resume Daemon",
          icon: "play",
          run: async () => {
            try {
              await resumeDaemon();
              toast.success("데몬을 다시 시작했어요.");
            } catch (e) {
              toast.error("데몬 재시작에 실패했어요.", String(e));
            }
          },
        }
      : {
          id: "pause-daemon",
          label: "Pause Daemon",
          icon: "pause",
          run: async () => {
            try {
              await pauseDaemon();
              toast.success("데몬을 일시정지했어요.");
            } catch (e) {
              toast.error("데몬 일시정지에 실패했어요.", String(e));
            }
          },
        },
  ];

  const ActiveComponent =
    NAV.find((item) => item.id === activeTab)?.component ?? NAV[0]?.component;

  return (
    <main className="app">
      <aside className="sidebar">
        <DaemonStatusBadge
          state={daemon.state}
          online={daemon.online}
          nextPollInSec={nextPollInSec}
          inProgressPrId={inProgressPrId}
          prLookup={prLookup}
        />
        <nav className="sidebar-nav">
          {NAV.map((item) => (
            <button
              key={item.id}
              type="button"
              className={`sidebar-item ${item.id === activeTab ? "active" : ""}`}
              onClick={() => setActiveTab(item.id)}
            >
              <span className="sidebar-icon"><Icon name={item.icon} /></span>
              <span className="sidebar-label">{item.label}</span>
            </button>
          ))}
        </nav>
        <div className="sidebar-footer">
          <button
            type="button"
            className="sidebar-item settings-link"
            onClick={() => setSettingsOpen(true)}
          >
            <span className="sidebar-icon"><Icon name="settings" /></span>
            <span className="sidebar-label">Settings</span>
            <span className="shortcut-hint">⌘,</span>
          </button>
        </div>
      </aside>
      <div className="main-content">{ActiveComponent?.()}</div>

      <Dialog
        open={settingsOpen}
        onOpenChange={(open) => {
          if (!open) closeSettings();
        }}
        variant="settings"
        label="Settings"
      >
        <button
          type="button"
          className="settings-overlay-close"
          aria-label="닫기"
          onClick={closeSettings}
        >
          <Icon name="x" />
        </button>
        <Settings onOpenInstallHelp={() => setInstallHelpOpen(true)} />
      </Dialog>
      <CommandPalette
        open={paletteOpen}
        commands={commands}
        onClose={closePalette}
      />
      <ShortcutHelp open={helpOpen} onOpenChange={setHelpOpen} />
      <HelpInstall open={installHelpOpen} onOpenChange={setInstallHelpOpen} />
    </main>
  );
}

export default App;
