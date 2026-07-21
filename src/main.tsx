import React from "react";
import ReactDOM from "react-dom/client";
import { MotionConfig } from "motion/react";
import { ToastProvider } from "./components/ui/Toast";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <MotionConfig reducedMotion="user">
      <ToastProvider>
        <App />
      </ToastProvider>
    </MotionConfig>
  </React.StrictMode>,
);
