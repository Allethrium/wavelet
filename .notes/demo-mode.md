# Wavelet UI Demo Mode

## The `DEMO_MODE` flag

Each `html-demoN/` directory is a full, self-contained copy of the production
`html/` directory — same `index.html`/`index.js`/`styles.css`, plus its own
copies of `get_keys.php`, `set_control.php`, and `sse_client.php`.

At the top of each of those three PHP files is one line:

```php
define('DEMO_MODE', true);
```

While that line is present:

- `get_keys.php` returns the static contents of `demo_mock_data.json` instead
  of querying etcd.
- `set_control.php` reports success for every button/dropdown/toggle action
  but never writes to etcd — nothing on the real system is touched.
- `sse_client.php` sends only periodic heartbeats, never connects to Redis,
  and never streams live changes (the UI already reflects clicks locally, so
  no live push is needed for a demo).

**To switch a copy from demo to real, live data:** delete (or comment out)
the `define('DEMO_MODE', true);` line in all three files and restart the web
server. No other code changes are needed — everything below that line is the
same, real logic that's in production `html/`.

## Copying/symlinking a demo directory into place

**On your own machine (Scott):** `html/` is a symlink pointing at whichever
`html-demoN/` you're currently reviewing. To switch which design is live:

```
ln -sfn html-demoN html
```

This is instant and atomic — no files are duplicated, and reverting to
production just means re-pointing the symlink at the real `html/` source.

**On the client's dev server:** the client does a plain directory copy
(not a symlink) of whichever `html-demoN/` they want to preview over their
existing `html/`. They will see the mock data immediately. When they're
ready to see it running against their real, live system (the server with
actual hardware attached), they remove the `DEMO_MODE` line from the three
PHP files and restart the server.

## Mock data files

**`demo_mock_data.json`** (one per `html-demoN/` directory) — a static JSON
file matching the exact shape `get_keys.php` normally builds from etcd:
`groups`, `hosts` (each with nested `inputs`), and `globals` (system-wide
toggles and available codecs). It currently describes two example groups
("Main Stage", "Lobby Display") each with one host and one input, so the UI
has enough realistic-looking data to render its full layout — group cards,
host tiles, source dropdowns, health-status coloring, etc. — without any
backend running. This file can be freely hand-edited (labels, colors,
number of groups/hosts) to change what the mockup shows; no code changes
are needed to adjust it.
