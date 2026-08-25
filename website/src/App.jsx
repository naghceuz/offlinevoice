import { useEffect, useState } from "react";
import {
  AudioLines,
  AudioWaveform,
  Ban,
  ChevronRight,
  Cpu,
  Download,
  FileText,
  Keyboard,
  LayoutGrid,
  LockKeyhole,
  Mail,
  Menu,
  MessageCircle,
  Mic,
  MoreHorizontal,
  Notebook,
  Play,
  ShieldCheck,
  Zap,
  X,
} from "lucide-react";
import {
  SiCursor,
  SiGithub,
} from "@icons-pack/react-simple-icons";

const navItems = ["Why OfflineVoice", "Speed", "Privacy", "How it works", "FAQ"];
// Routes through the /api/download serverless function so each download is
// counted, then 302-redirects to the real .dmg under /downloads/.
const downloadHref = "/api/download";
const githubHref = "https://github.com/naghceuz/offlinevoice";

const proofItems = [
  { label: "Fastest local dictation", icon: Zap },
  { label: "100% on-device", icon: LockKeyhole },
  { label: "Free & open source", icon: SiGithub },
];

const steps = [
  {
    title: "Hold hotkey",
    detail: "Press and hold to start dictating anywhere.",
    meta: "Right Option",
    icon: Keyboard,
  },
  {
    title: "Speak naturally",
    detail: "Talk at your own pace. Everything is transcribed on your Mac.",
    meta: "Live waveform",
    icon: AudioWaveform,
  },
  {
    title: "Text appears instantly",
    detail: "Recognized text is pasted at your cursor the moment you release.",
    meta: "Auto paste",
    icon: FileText,
  },
];

const apps = [
  { label: "Mail", icon: Mail },
  { label: "Notes", icon: Notebook },
  { label: "Cursor", icon: SiCursor },
  { label: "Slack", icon: LayoutGrid },
  { label: "ChatGPT", icon: MessageCircle },
  { label: "And more", icon: MoreHorizontal },
];

const compareRows = [
  ["Speed", "Near-instant, on-device", "Round-trip to the cloud"],
  ["Processing", "On your Mac", "Cloud required"],
  ["Privacy", "Audio never leaves your Mac", "Upload first"],
  ["Offline use", "Works without a connection", "Connection dependent"],
  ["Pricing", "No subscription loop", "Monthly plan"],
];

const whyItems = [
  {
    title: "Fastest dictation",
    body: "Because everything runs on your Mac, there is no cloud round-trip. Text shows up near-instantly the moment you stop talking.",
    icon: Zap,
  },
  {
    title: "Works anywhere",
    body: "Dictate straight into the focused text field of any native Mac app — Mail, Notes, Cursor, Slack, ChatGPT, and more.",
    icon: MessageCircle,
  },
  {
    title: "100% on-device",
    body: "Speech recognition runs locally with Apple on-device speech or optional Whisper. No cloud, no account, no subscription.",
    icon: ShieldCheck,
  },
];

const speedItems = [
  ["0ms", "cloud round-trip — recognition runs on-device"],
  ["100%", "transcribed locally on your Mac"],
  ["1", "hotkey from speech to text in any app"],
];

const recognitionModes = [
  {
    title: "Speed",
    badge: "Default",
    body: "Apple's native on-device speech recognition. Near-instant, lightweight, and zero extra downloads.",
    icon: Zap,
  },
  {
    title: "Accuracy",
    badge: "Optional",
    body: "Whisper (large-v3 turbo) for sharper results on English and technical content. Downloads once on first use, then works offline.",
    icon: Cpu,
  },
];

function BrandMark({ compact = false }) {
  return (
    <div className="brand-mark" aria-label="OfflineVoice.ai">
      <AudioLines size={compact ? 24 : 30} strokeWidth={2.6} />
      {!compact && <span>OfflineVoice.ai</span>}
    </div>
  );
}

function Waveform({ compact = false }) {
  const heights = compact
    ? [14, 23, 18, 34, 46, 28, 58, 38, 25, 64, 42, 30, 21, 36, 19, 28, 16, 12]
    : [12, 18, 24, 16, 34, 46, 30, 62, 44, 28, 72, 50, 36, 25, 44, 60, 38, 22, 30, 48, 58, 32, 22, 40, 28, 20, 34, 18, 26, 14, 18, 12];

  return (
    <div className={`waveform ${compact ? "waveform-compact" : ""}`} aria-hidden="true">
      {heights.map((height, index) => (
        <span key={index} style={{ "--i": index, "--h": `${height}px` }} />
      ))}
    </div>
  );
}

function ProductDemo() {
  return (
    <div className="product-stage" aria-label="OfflineVoice dictation demo">
      <div className="editor-window">
        <div className="window-top">
          <div className="traffic" aria-hidden="true">
            <span className="red" />
            <span className="amber" />
            <span className="green" />
          </div>
          <span>Project Update</span>
        </div>
        <div className="toolbar">
          <span>SF Pro</span>
          <span>Regular</span>
          <span>14</span>
          <b>B</b>
          <em>I</em>
          <span>U</span>
          <span>|||</span>
          <span>≡</span>
        </div>
        <div className="editor-content">
          <div className="copy-block before">
            <p className="block-label">You say</p>
            <div className="text-box">
              <p>
                Today I wanted to give a quick update on the project. We've been
                working on the new onboarding flow and it's almost ready.
              </p>
            </div>
          </div>
          <div className="copy-block after">
            <p className="block-label">Text appears <span>(on-device)</span></p>
            <div className="text-box">
              <p>
                Today I wanted to give a quick update on the project. We've been
                working on the new onboarding flow and it's almost ready. We still
                need to fix a few edge cases and some Chinese copy. Let's review it
                together.
              </p>
            </div>
          </div>
        </div>
        <div className="status-bar">
          <span>Dictated</span>
          <span>Focus&nbsp;&nbsp;⌘</span>
        </div>
      </div>

      <div className="listening-card">
        <div className="listening-title">
          <AudioLines size={20} />
          <span>OfflineVoice</span>
        </div>
        <Waveform compact />
        <div className="listen-state">
          <span />
          Listening...
        </div>
        <div className="shortcut">Release Right Option to paste</div>
      </div>

      <div className="privacy-cue">
        <LockKeyhole size={31} />
        <strong>All processing happens on your Mac</strong>
      </div>
    </div>
  );
}

function AppIcon({ app }) {
  const Icon = app.icon;
  const isBrand = [SiCursor].includes(Icon);

  return (
    <div className="app-item">
      <div className="app-icon">
        {isBrand ? <Icon size={28} color="currentColor" /> : <Icon size={30} strokeWidth={1.9} />}
      </div>
      <span>{app.label}</span>
    </div>
  );
}

function DownloadLink({ className, children, onClick }) {
  return (
    <a className={className} href={downloadHref} onClick={onClick}>
      {children}
    </a>
  );
}

function Modal({ onClose }) {
  useEffect(() => {
    const handler = (event) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div className="modal" role="dialog" aria-modal="true" aria-label="How OfflineVoice works" onClick={(event) => event.stopPropagation()}>
        <button className="icon-button modal-close" type="button" onClick={onClose} aria-label="Close demo">
          <X size={18} />
        </button>
        <div className="modal-kicker">Local pipeline</div>
        <h2>Hold key → on-device ASR → paste.</h2>
        <p>
          The flow keeps the product promise simple: hold the hotkey, talk
          naturally, let your Mac transcribe on-device, and paste the text into
          the focused app. No cloud, no account, no upload.
        </p>
        <div className="modal-pipeline">
          <span>Mic</span>
          <ChevronRight size={18} />
          <span>On-device ASR</span>
          <ChevronRight size={18} />
          <span>Pasteboard</span>
        </div>
      </div>
    </div>
  );
}

export function App() {
  const [menuOpen, setMenuOpen] = useState(false);
  const [modalOpen, setModalOpen] = useState(false);

  return (
    <>
      <main className="site-shell">
        <header className="site-header">
          <a className="brand-link" href="#top" aria-label="OfflineVoice.ai home">
            <BrandMark />
          </a>
          <nav className="desktop-nav" aria-label="Primary navigation">
            {navItems.map((item) => (
              <a key={item} href={`#${item.toLowerCase().replaceAll(" ", "-")}`}>
                {item}
              </a>
            ))}
          </nav>
          <a className="github-link" href={githubHref} target="_blank" rel="noreferrer" aria-label="OfflineVoice on GitHub — open source">
            <SiGithub size={18} color="currentColor" />
            <span>GitHub</span>
          </a>
          <DownloadLink className="download-small">
            Download for Mac
          </DownloadLink>
          <button className="icon-button menu-button" type="button" onClick={() => setMenuOpen((value) => !value)} aria-label="Toggle menu" aria-expanded={menuOpen}>
            {menuOpen ? <X size={21} /> : <Menu size={21} />}
          </button>
        </header>

        {menuOpen && (
          <nav className="mobile-nav" aria-label="Mobile navigation">
            {navItems.map((item) => (
              <a key={item} href={`#${item.toLowerCase().replaceAll(" ", "-")}`} onClick={() => setMenuOpen(false)}>
                {item}
              </a>
            ))}
            <a className="mobile-github" href={githubHref} target="_blank" rel="noreferrer" onClick={() => setMenuOpen(false)}>
              <SiGithub size={18} color="currentColor" />
              View source on GitHub
            </a>
            <DownloadLink className="mobile-download" onClick={() => setMenuOpen(false)}>
              Download for Mac
            </DownloadLink>
          </nav>
        )}

        <section id="top" className="hero-section">
          <div className="hero-copy">
            <a className="hero-badge" href={githubHref} target="_blank" rel="noreferrer">
              <SiGithub size={15} color="currentColor" />
              <strong>Open source</strong>
              <span className="hero-badge-sep" aria-hidden="true" />
              GPL-3.0 · runs 100% on your Mac
              <ChevronRight size={15} strokeWidth={2.6} />
            </a>
            <h1>
              The fastest local
              <span>voice dictation for Mac.</span>
            </h1>
            <p className="hero-lede">
              Hold one hotkey and talk. Because OfflineVoice runs entirely on
              your Mac, there's no cloud round-trip — so it's faster, and more
              private, than tools that send your voice away. And it's{" "}
              <a className="lede-link" href={githubHref} target="_blank" rel="noreferrer">
                fully open source
              </a>
              .
            </p>
            <div className="hero-actions">
              <DownloadLink className="primary-cta">
                <span className="cta-icon" aria-hidden="true">
                  <Download size={19} strokeWidth={2.8} />
                </span>
                <span>Download for Mac</span>
              </DownloadLink>
              <button className="secondary-cta" type="button" onClick={() => setModalOpen(true)}>
                <Play size={20} fill="currentColor" />
                See how it works
              </button>
            </div>
            <div className="proof-row">
              {proofItems.map((item) => {
                const Icon = item.icon;
                return (
                  <span key={item.label}>
                    <Icon size={19} />
                    {item.label}
                  </span>
                );
              })}
            </div>
            <p className="local-line">
              <ShieldCheck size={17} />
              100% on-device and open source. No cloud, no account, no subscription.
            </p>
          </div>

          <div className="hero-visual">
            <ProductDemo />
          </div>

          <div className="signal-line" aria-hidden="true">
            <Waveform compact />
          </div>
        </section>

        <section id="how-it-works" className="steps-band">
          {steps.map((step, index) => {
            const Icon = step.icon;
            return (
              <article key={step.title} className="step-card">
                <div className="step-index">{index + 1}</div>
                <div>
                  <h2>{step.title}</h2>
                  <div className="step-meta">
                    <Icon size={index === 1 ? 54 : 31} />
                    <span>{step.meta}</span>
                  </div>
                  <p>{step.detail}</p>
                </div>
              </article>
            );
          })}
        </section>

        <section id="features" className="apps-section">
          <div className="apps-intro">
            <h2>Works anywhere</h2>
            <p>Dictate into any text field on your Mac. The same fast, on-device flow everywhere you type.</p>
          </div>
          <div className="apps-grid">
            {apps.map((app) => (
              <AppIcon key={app.label} app={app} />
            ))}
          </div>
        </section>

        <section id="why-offlinevoice" className="why-section">
          <div className="section-kicker">Why OfflineVoice</div>
          <h2>Local-first dictation that's fast because it never leaves your Mac.</h2>
          <div className="why-grid">
            {whyItems.map((item) => {
              const Icon = item.icon;
              return (
                <article key={item.title}>
                  <Icon size={28} />
                  <h3>{item.title}</h3>
                  <p>{item.body}</p>
                </article>
              );
            })}
          </div>
        </section>

        <section id="privacy" className="privacy-section">
          <div className="section-kicker">Privacy &amp; Local AI</div>
          <h2>100% local: your voice never becomes our data.</h2>
          <div className="privacy-grid">
            <article>
              <Mic size={28} />
              <h3>Capture locally</h3>
              <p>Audio is captured only while you hold the hotkey, and stays on your Mac.</p>
            </article>
            <article>
              <AudioWaveform size={28} />
              <h3>Transcribe on-device</h3>
              <p>Recognition runs locally — Apple on-device speech, or optional Whisper.</p>
            </article>
            <article>
              <Cpu size={28} />
              <h3>Nothing uploaded</h3>
              <p>No audio sent, no text synced, no data used for training. Ever.</p>
            </article>
          </div>
        </section>

        <section id="speed" className="speed-section">
          <div>
            <div className="section-kicker">Speed</div>
            <h2>Dictate at thought speed. On-device means no waiting.</h2>
            <p>
              Press, speak, release, done. There's no upload, no server queue, and
              no network latency — text lands at your cursor the moment you stop
              talking. Built for repeated daily writing, not one-off recordings.
            </p>
          </div>
          <div className="speed-grid">
            {speedItems.map(([value, label]) => (
              <div key={value} className="speed-metric">
                <strong>{value}</strong>
                <span>{label}</span>
              </div>
            ))}
          </div>
        </section>

        <section id="recognition-modes" className="why-section">
          <div className="section-kicker">Privacy &amp; Local AI</div>
          <h2>Two on-device modes. Pick speed or accuracy.</h2>
          <div className="why-grid">
            {recognitionModes.map((mode) => {
              const Icon = mode.icon;
              return (
                <article key={mode.title}>
                  <Icon size={28} />
                  <h3>{mode.title} <span className="mode-badge">{mode.badge}</span></h3>
                  <p>{mode.body}</p>
                </article>
              );
            })}
          </div>
        </section>

        <section id="no-internet" className="offline-section">
          <div className="offline-lock">
            <LockKeyhole size={42} />
          </div>
          <div>
            <div className="section-kicker">No internet required</div>
            <h2>No internet required. Built to keep working when the network does not.</h2>
            <p>
              Dictation runs on your machine. Speed mode works out of the box; the
              optional Whisper model downloads once, then runs offline too. Fewer
              privacy tradeoffs, and fewer broken writing sessions.
            </p>
          </div>
        </section>

        <section id="pricing" className="compare-section">
          <div>
            <div className="section-kicker">Pricing</div>
            <h2>No cloud tax for your own words.</h2>
            <p>
              OfflineVoice is designed for a one-time Mac app purchase rather than another
              recurring voice subscription.
            </p>
          </div>
          <div className="compare-table" role="table" aria-label="OfflineVoice comparison">
            <div className="compare-head" role="row">
              <span />
              <strong>OfflineVoice</strong>
              <strong>Cloud dictation</strong>
            </div>
            {compareRows.map(([label, offline, cloud]) => (
              <div className="compare-row" role="row" key={label}>
                <span>{label}</span>
                <strong>{offline}</strong>
                <em>{cloud}</em>
              </div>
            ))}
          </div>
        </section>

        <section className="final-cta">
          <h2>Try the fastest local dictation on your Mac.</h2>
          <p>Download, open the menu-bar app, grant permissions, and hold Right Option to dictate into any text field. Signed and notarized — just double-click to open.</p>
          <DownloadLink className="primary-cta">
            <span className="cta-icon" aria-hidden="true">
              <Download size={19} strokeWidth={2.8} />
            </span>
            <span>Download for Mac</span>
          </DownloadLink>
        </section>

        <section id="faq" className="faq-section">
          <div className="faq-copy">
            <div className="section-kicker">FAQ</div>
            <h2>Built for the way Mac power users actually write.</h2>
          </div>
          <div className="faq-list">
            <details open>
              <summary>Does it work outside the browser?</summary>
              <p>Yes. It pastes into the focused text field across native Mac apps — anywhere you can type.</p>
            </details>
            <details>
              <summary>What's the difference between Speed and Accuracy?</summary>
              <p>Speed (the default) uses Apple's native on-device recognition — near-instant and zero extra downloads. Accuracy uses Whisper (large-v3 turbo) for sharper results on English and technical content; it downloads once, then runs offline.</p>
            </details>
            <details>
              <summary>Does it need the internet?</summary>
              <p>No. Recognition runs on your Mac. Speed mode works immediately; the optional Whisper model downloads once and then runs fully offline.</p>
            </details>
            <details>
              <summary>Is the download safe to open?</summary>
              <p>
                Yes. OfflineVoice is signed with a Developer ID and notarized by
                Apple, so you can just double-click the download to open it — no
                Gatekeeper warnings.
              </p>
            </details>
          </div>
        </section>

        <section id="privacy-policy" className="policy-section">
          <div className="section-kicker">Privacy Policy</div>
          <h2>The short version: nothing leaves your Mac.</h2>
          <p className="policy-updated">Last updated June 16, 2026</p>
          <div className="policy-body">
            <h3>What we collect</h3>
            <p>
              Nothing. OfflineVoice has no account, no sign-in, no analytics, and no
              telemetry. We do not operate a server that receives your data, and the app
              does not phone home.
            </p>
            <h3>Your audio and text</h3>
            <p>
              Microphone audio is captured only while you hold the dictation hotkey, is
              transcribed on your Mac, and is discarded after the text is produced. The
              recognized text is placed on your clipboard and pasted into the app you
              choose. Audio and text are never uploaded to us or any third party.
            </p>
            <h3>Local AI models</h3>
            <p>
              Transcription runs on-device. Speed mode uses Apple's built-in
              on-device speech recognition. Accuracy mode uses Whisper (large-v3
              turbo); the first time you use it the model is downloaded from its
              public host and then cached locally for offline use. None of this
              sends your speech or text off the device.
            </p>
            <h3>Permissions</h3>
            <p>
              OfflineVoice asks for Microphone access (to capture your voice) and
              Accessibility access (to detect the global hotkey and paste into the focused
              app). These are used solely for dictation and for nothing else.
            </p>
            <h3>Configuration files</h3>
            <p>
              Your settings are stored in a plain file at
              <code> ~/.config/offlinevoice/config.json</code> on your Mac. You can read,
              edit, or delete it at any time.
            </p>
            <h3>Contact</h3>
            <p>
              Questions about privacy? Reach out via <a href="https://www.offlinevoice.ai">offlinevoice.ai</a>.
            </p>
          </div>
        </section>

        <footer className="site-footer">
          <BrandMark compact />
          <span>OfflineVoice.ai</span>
          <p>v0.4.0 · The fastest local voice dictation for Mac. Free &amp; open source (GPL-3.0).</p>
          <p className="footer-links">
            <a href="#privacy-policy">Privacy Policy</a>
            <a href={githubHref} target="_blank" rel="noreferrer">
              <SiGithub size={15} color="currentColor" /> Source on GitHub
            </a>
          </p>
        </footer>
      </main>

      {modalOpen && <Modal onClose={() => setModalOpen(false)} />}
    </>
  );
}
