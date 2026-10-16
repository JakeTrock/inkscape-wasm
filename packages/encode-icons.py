#!/usr/bin/env python3
"""Pre-encode SVG icons in build/inkscape-fs to .symbolic.png and .png for WASM."""
import ctypes
import os
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor

SYM_SUFFIXES = ("-symbolic.svg", "-symbolic-ltr.svg", "-symbolic-rtl.svg")

_lib = None
def _init_pixbuf():
    global _lib
    _lib = ctypes.CDLL("libgdk_pixbuf-2.0.so.0")
    _lib.gdk_pixbuf_new_from_file_at_scale.argtypes = [
        ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p)
    ]
    _lib.gdk_pixbuf_new_from_file_at_scale.restype = ctypes.c_void_p
    _lib.gdk_pixbuf_save.argtypes = [
        ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p
    ]
    _lib.gdk_pixbuf_save.restype = ctypes.c_int
    _lib.g_object_unref.argtypes = [ctypes.c_void_p]

def _rasterize_png(args):
    svg, out_png, size = args
    err = ctypes.c_void_p()
    pb = _lib.gdk_pixbuf_new_from_file_at_scale(svg.encode(), size, size, 1, ctypes.byref(err))
    if not pb:
        return False
    ok = _lib.gdk_pixbuf_save(pb, out_png.encode(), b"png", ctypes.byref(err), None)
    _lib.g_object_unref(pb)
    return bool(ok)

def _encode_symbolic(svg):
    d = os.path.dirname(svg)
    stem = os.path.basename(svg)[:-4]
    out = os.path.join(d, stem + ".symbolic.png")
    r = subprocess.run(
        ["/usr/bin/gtk-encode-symbolic-svg", svg, "16x16", "-o", d],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if r.returncode == 0 and os.path.exists(out):
        return (svg, True)
    return (svg, False)

def main():
    fs = sys.argv[1]
    roots = [
        os.path.join(fs, "inkscape/share/inkscape/icons"),
        os.path.join(fs, "inkscape/share/icons"),
    ]
    sym_svgs, reg_svgs = [], []
    for root in roots:
        for dirpath, _, filenames in os.walk(root):
            if "/cursors" in dirpath:
                continue
            for fn in filenames:
                if fn == "icon-theme.cache":
                    os.unlink(os.path.join(dirpath, fn))
                elif fn.endswith(".svg"):
                    p = os.path.join(dirpath, fn)
                    if fn.endswith(SYM_SUFFIXES):
                        sym_svgs.append(p)
                    else:
                        reg_svgs.append((p, p[:-4] + ".png", 24))

    with ThreadPoolExecutor(max_workers=64) as ex:
        sym_res = list(ex.map(_encode_symbolic, sym_svgs))
    # Fallback to direct rasterization if gtk-encode-symbolic-svg rejected an SVG
    fallback = [(s, s[:-4] + ".symbolic.png", 16) for s, ok in sym_res if not ok]

    with ProcessPoolExecutor(max_workers=32, initializer=_init_pixbuf) as ex:
        reg_ok = sum(ex.map(_rasterize_png, reg_svgs + fallback))

    sym_ok = sum(1 for _, ok in sym_res if ok)
    print(f"encode-icons: {sym_ok}/{len(sym_svgs)} symbolic (.symbolic.png), "
          f"{reg_ok}/{len(reg_svgs) + len(fallback)} regular/fallback (.png)")

if __name__ == "__main__":
    main()
