/* BridgeSocket: WebSocket-compatible facade over the in-module Broadway
 * daemon. Real WebSocket framing in both directions so the daemon's stock
 * parse_input and BroadwayOutput framing work unpatched. */
'use strict';

function concatBytes(a, b) {
    var out = new Uint8Array(a.length + b.length);
    out.set(a, 0); out.set(b, a.length);
    return out;
}

/* client -> server frame: binary, masked (browsers always mask) */
function buildClientFrame(payload) {
    var len = payload.length;
    var headLen = 2 + 4 + (len >= 126 ? 2 : 0) + (len >= 65536 ? 6 : 0);
    var frame = new Uint8Array(headLen + len);
    var o = 0, i, m;
    frame[o++] = 0x82; /* FIN | binary */
    if (len < 126) frame[o++] = 0x80 | len;
    else if (len < 65536) { frame[o++] = 0x80 | 126; frame[o++] = len >> 8; frame[o++] = len & 0xff; }
    else { frame[o++] = 0x80 | 127; for (i = 7; i >= 0; i--) { frame[o++] = Math.floor(len / Math.pow(256, i)) & 0xff; } }
    for (m = 0; m < 4; m++) frame[o++] = (Math.random() * 256) | 0;
    var mask = frame.subarray(o - 4, o);
    for (i = 0; i < len; i++) frame[o + i] = payload[i] ^ mask[i % 4];
    return frame;
}

/* server -> client: parse all complete frames out of (prevRest + chunk).
 * Returns { frames: [Uint8Array...], rest: Uint8Array }. */
function parseServerFrames(prevRest, chunk) {
    var rx = concatBytes(prevRest, chunk);
    var frames = [];
    while (rx.length >= 2) {
        var opcode = rx[0] & 0x0f;
        var len = rx[1] & 0x7f;
        var off = 2;
        var i;
        if (len === 126) {
            if (rx.length < 4) break;
            len = (rx[2] << 8) | rx[3]; off = 4;
        } else if (len === 127) {
            if (rx.length < 10) break;
            len = 0;
            for (i = 0; i < 8; i++) len = len * 256 + rx[2 + i];
            off = 10;
        }
        if (rx.length < off + len) break;
        var payload = rx.slice(off, off + len);
        rx = rx.slice(off + len);
        if (opcode === 2) frames.push(payload);
        /* opcode 8 (close), 9 (ping): daemon never sends; drop */
    }
    return { frames: frames, rest: rx };
}

function BridgeSocket() {
    var self = this;
    this.binaryType = 'arraybuffer';
    this.onopen = null; this.onclose = null; this.onmessage = null;
    this._opened = false;
    this._rx = new Uint8Array(0);
    var mod = window.__bridge_mod;
    mod._bridge_js_connect();
    setTimeout(function () {
        if (!self._opened && self.onopen) {
            self._opened = true;
            self.onopen();
        }
        pumpDaemon(); /* hello/resync may already be queued */
    }, 0);
    BridgeSocket.socket = this;
}
BridgeSocket.socket = null;

BridgeSocket.prototype.send = function (data) {
    var mod = window.__bridge_mod;
    var frame = buildClientFrame(new Uint8Array(data));
    var buf = mod._malloc(frame.length);
    mod.HEAPU8.set(frame, buf);
    mod._bridge_js_write(buf, frame.length);
    mod._free(buf);
};

/* Drain daemon -> JS bytes and deliver complete frames to onmessage. */
function pumpDaemon() {
    var mod = window.__bridge_mod;
    if (!mod || !BridgeSocket.socket) return;
    var sock = BridgeSocket.socket;
    if (!sock._opened && sock.onopen) {
        sock._opened = true;
        sock.onopen();
    }
    var len = mod._bridge_js_poll();
    if (len <= 0) return;
    var ptr = mod._bridge_js_poll_ptr();
    var chunk = mod.HEAPU8.slice(ptr, ptr + len); /* copies out of wasm heap */
    if (!sock.onmessage) { sock._rx = new Uint8Array(0); return; }
    var res = parseServerFrames(sock._rx, chunk);
    sock._rx = res.rest;
    for (var i = 0; i < res.frames.length; i++)
        sock.onmessage({ data: res.frames[i].buffer }); /* ArrayBuffer, like a real WS */
}

if (typeof module !== 'undefined' && typeof module.exports !== 'undefined')
    module.exports = { buildClientFrame: buildClientFrame,
                       parseServerFrames: parseServerFrames,
                       concatBytes: concatBytes };
