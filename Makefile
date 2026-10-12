ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OBG  := $(HOME)/.config/opencode/bin/oc-bg
PKGS := zlib libpng freetype expat fontconfig pixman fribidi harfbuzz cairo \
        libffi glib pango gdk-pixbuf atk gtk3 sigcpp glibmm cairomm pangomm \
        gtkmm libxml2 libxslt gsl dconv boost libgc potrace lib2geom
# if potrace is cut (Task 19 optional rule), remove it from this list

.PHONY: deps deps-real pkg-% check-0 check-1 clean

deps:
	$(OBG) build/logs/deps -- $(MAKE) deps-real

deps-real:
	@for p in $(PKGS); do echo "== $$p =="; bash packages/$$p.sh || exit 1; done

pkg-%:
	bash packages/$*.sh

check-0: ; bash tests/t0/run.sh
check-1: ; bash tests/check-1.sh

clean:
	rm -rf build
