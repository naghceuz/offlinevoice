import React from "react";
import { renderToString } from "react-dom/server";
import { Analytics } from "@vercel/analytics/react";
import { App } from "./App.jsx";

// Renders the same tree as main.jsx so client-side hydration matches.
export function render() {
  return renderToString(
    <React.StrictMode>
      <App />
      <Analytics />
    </React.StrictMode>,
  );
}
