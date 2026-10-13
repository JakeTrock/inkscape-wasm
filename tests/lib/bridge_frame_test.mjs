// Frame codec: buildClientFrame (masked, client->daemon) and
// parseServerFrames (unmasked, daemon->client) — as BroadwayOutput/parse_input
// expect them on the wire.
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../../bridge/bridge.js', import.meta.url), 'utf8');
const stripped = src.slice(0, src.indexOf("if (typeof module !== 'undefined'"));
const mod = await import('data:text/javascript,' +
  encodeURIComponent(stripped + '\nexport { buildClientFrame, parseServerFrames, concatBytes };'));

function fr(str) { return new TextEncoder().encode(str); }

function serverFrame(payload) { // what BroadwayOutput's websocket_write emits
    var len = payload.length;
    var head;
    if (len < 126) { head = [0x82, len]; }
    else if (len < 65536) { head = [0x82, 126, len >> 8, len & 0xff]; }
    else { head = [0x82, 127]; for (var i = 7; i >= 0; i--) head.push(Math.floor(len / Math.pow(256, i)) & 0xff); }
    return new Uint8Array(head.concat(Array.from(payload)));
}

// --- client frames: structure + payload recoverable via the embedded mask ---
let f = mod.buildClientFrame(fr('hello'));
console.assert(f[0] === 0x82 && (f[1] & 0x80) !== 0 && (f[1] & 0x7f) === 5,
  'client frame header');
let unmasked = '';
for (let i = 0; i < 5; i++) unmasked += String.fromCharCode(f[6 + i] ^ f[2 + (i % 4)]);
console.assert(unmasked === 'hello', 'client payload XOR mask roundtrip');

f = mod.buildClientFrame(new Uint8Array(200)); // ext16
console.assert(f[1] === (0x80 | 126) && ((f[2] << 8) | f[3]) === 200, 'client ext16');
f = mod.buildClientFrame(new Uint8Array(70000)); // ext64
console.assert(f[1] === (0x80 | 127), 'client ext64 opcode');
let big = 0; for (let i = 0; i < 8; i++) big = big * 256 + f[2 + i];
console.assert(big === 70000, 'client ext64 length');

// --- server frames: parseServerFrames delivers payloads, handles splits ---
let out = mod.parseServerFrames(new Uint8Array(0), serverFrame(fr('hello')));
console.assert(out.frames.length === 1 && new TextDecoder().decode(out.frames[0]) === 'hello',
  'server frame roundtrip');
console.assert(out.rest.length === 0, 'no rest');

let two = mod.concatBytes(serverFrame(fr('ab')), serverFrame(fr('cd')));
let p1 = mod.parseServerFrames(new Uint8Array(0), two.subarray(0, 3)); // header + 1 payload byte
console.assert(p1.frames.length === 0, 'partial not delivered');
let p2 = mod.parseServerFrames(p1.rest, two.subarray(3));
console.assert(p2.frames.length === 2 &&
  new TextDecoder().decode(p2.frames[0]) === 'ab' &&
  new TextDecoder().decode(p2.frames[1]) === 'cd', 'two frames, split delivery');

out = mod.parseServerFrames(new Uint8Array(0), serverFrame(new Uint8Array(200)));
console.assert(out.frames.length === 1 && out.frames[0].length === 200, 'server ext16');
out = mod.parseServerFrames(new Uint8Array(0), serverFrame(new Uint8Array(70000)));
console.assert(out.frames.length === 1 && out.frames[0].length === 70000, 'server ext64');

console.log('bridge frame codec ok');
