# Inkscape WASM port — agent notes

## NEVER `read` image or PDF files (session-fatal)

The build model (zai-org/GLM-5.3 via daydream) is **text-only**. Reading an
image or PDF embeds a base64 `image_url` in the session history, after which
**every turn fails** with:

    provider.invalid-request: Model only supports text input;
    received unsupported content type 'image_url'.

The session becomes permanently unresumable — it can only be forked before the
offending message. This killed session `ses_ecce0a027ffeZGFd2SrW4XBKpo`
(2026-10-13) after it ran `read` on `/tmp/opencode/t2-debug.png`.

Enforced by `deny` rules in `opencode.json` (`read` on `*.png/jpg/gif/webp/bmp/pdf`).
If a read is denied, do NOT retry it or read the file another way.

### How to inspect rendered output instead

- Extend the Playwright debug script (`tests/t2/debug.mjs`) to dump textual
  facts: canvas count/size/position, per-region pixel counts, dominant colors,
  which element is at a point (`document.elementFromPoint`), event listener
  presence. The `CANVASES: [...]` dump already does this.
- PNG metadata without the image: `file foo.png` or parse the IHDR chunk with
  python/zlib in a shell command.
- If a human eyeball is truly needed, save the PNG under `/tmp/opencode/` and
  say so in the reply — don't read it yourself.
