# Zero-dependency static landing page served on {a,b}.zxc.sx, pointing
# visitors at the /cache/ reverse proxy in front of cache.nixos.org.
{ pkgs }:
pkgs.writeTextDir "index.html" ''
  <!doctype html>
  <html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>zxc.sx</title>
    <style>
      :root {
        color-scheme: light dark;
        --bg: #0e0f12;
        --fg: #e8e8ea;
        --muted: #9a9aa2;
        --card: #17181c;
        --border: #2a2b31;
        --accent: #7dd3fc;
      }
      @media (prefers-color-scheme: light) {
        :root {
          --bg: #f6f6f8;
          --fg: #17181c;
          --muted: #5b5c63;
          --card: #ffffff;
          --border: #e2e2e6;
          --accent: #0369a1;
        }
      }
      * { box-sizing: border-box; }
      html, body {
        margin: 0;
        padding: 0;
        background: var(--bg);
        color: var(--fg);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      }
      body {
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
      }
      main {
        max-width: 640px;
        width: 100%;
      }
      h1 {
        font-size: 1.6rem;
        margin: 0 0 0.25rem;
      }
      p.lead {
        color: var(--muted);
        margin: 0 0 1.75rem;
      }
      .card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 14px;
        padding: 1.5rem;
        margin-bottom: 1.25rem;
      }
      .card h2 {
        font-size: 1rem;
        margin: 0 0 0.75rem;
        color: var(--muted);
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      pre {
        background: var(--bg);
        border: 1px solid var(--border);
        border-radius: 10px;
        padding: 1rem;
        overflow-x: auto;
        font-size: 0.85rem;
        line-height: 1.5;
        margin: 0;
      }
      code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
      ul { margin: 0; padding-left: 1.2rem; color: var(--fg); }
      li { margin-bottom: 0.4rem; }
      li:last-child { margin-bottom: 0; }
      a { color: var(--accent); text-decoration: none; }
      a:hover { text-decoration: underline; }
      footer {
        color: var(--muted);
        font-size: 0.8rem;
        text-align: center;
        margin-top: 1.5rem;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>zxc.sx</h1>
      <p class="lead">This server mirrors a Nix binary cache reverse proxy at <code>/cache/</code>.</p>

      <div class="card">
        <h2>Available mirrors</h2>
        <ul>
          <li><a href="https://cache.nixos.kz/">https://cache.nixos.kz/</a></li>
          <li><a href="https://a.zxc.sx/cache">https://a.zxc.sx/cache</a></li>
          <li><a href="https://b.zxc.sx/cache">https://b.zxc.sx/cache</a></li>
        </ul>
      </div>

      <div class="card">
        <h2>Add it to your NixOS config</h2>
        <pre><code>nix.settings.substituters = [
    "https://cache.nixos.kz"
    "https://a.zxc.sx/cache"
    "https://b.zxc.sx/cache"
    "https://cache.nixos.org"
  ];</code></pre>
      </div>

      <footer>Plain passthrough proxy to cache.nixos.org &mdash; no extra trust required.</footer>
    </main>
  </body>
  </html>
''
