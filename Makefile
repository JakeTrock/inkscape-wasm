ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OBG  := $(HOME)/.config/opencode/bin/oc-bg
PKGS := zlib libpng freetype expat fontconfig pixman fribidi harfbuzz cairo \
        libffi glib pango gdk-pixbuf atk gtk3 sigcpp glibmm cairomm pangomm \
        atkmm gtkmm libxml2 libxslt gsl dconv lcms2 boost libgc potrace lib2geom

.PHONY: deps deps-real pkg-% check-0 check-1 check-2 check-3 check-4 check-5 \
        check-6 check-7 check-8 serve native-inkscape goldens-regen clean

deps:
	$(OBG) build/logs/deps -- $(MAKE) deps-real

deps-real:
	@for p in $(PKGS); do echo "== $$p =="; bash packages/$$p.sh || exit 1; done

pkg-%:
	bash packages/$*.sh

check-0: ; bash tests/t0/run.sh
check-1: ; bash tests/check-1.sh
check-2: ; bash tests/t2/run.sh
check-3: ; bash tests/t3/run.sh
check-4: ; bash tests/t4/run.sh
check-5: ; bash tests/t5/run.sh
check-6: ; bash tests/t6/run.sh
check-7: ; bash tests/t7/run.sh
check-8: ; bash tests/t8/run.sh

serve:
	python3 -c 'import http.server, functools; H = type("H", (http.server.SimpleHTTPRequestHandler,), {"end_headers": lambda s: (s.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"), http.server.SimpleHTTPRequestHandler.end_headers(s))}); http.server.ThreadingHTTPServer(("0.0.0.0", 8824), functools.partial(H, directory="build")).serve_forever()'

native-inkscape: ; bash packages/native-inkscape.sh
goldens-regen: ; bash tests/golden/gen.sh

clean:
	rm -rf build
