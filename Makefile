ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OBG  := $(HOME)/.config/opencode/bin/oc-bg
PKGS := zlib libpng freetype expat fontconfig pixman fribidi harfbuzz cairo \
        libffi glib pango gdk-pixbuf atk gtk3 sigcpp glibmm cairomm pangomm \
        gtkmm libxml2 libxslt gsl dconv lcms2 boost libgc potrace lib2geom

.PHONY: deps deps-real pkg-% check-0 check-1 check-2 check-3 clean

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

clean:
	rm -rf build
