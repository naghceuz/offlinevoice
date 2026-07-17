import React from "react";
import { createRoot, hydrateRoot } from "react-dom/client";
import { Analytics } from "@vercel/analytics/react";
import { App } from "./App.jsx";
import "./styles.css";

const container = document.getElementById("root");
const tree = (
  <React.StrictMode>
    <App />
    <Analytics />
  </React.StrictMode>
);

// Production HTML is prerendered (scripts/prerender.mjs); dev serves an empty shell.
if (container.hasChildNodes()) {
  hydrateRoot(container, tree);
} else {
  createRoot(container).render(tree);
}
