# nim-qtcamera — local development build.
# Dependencies are cloned (not submoduled) into .deps/ at the same commits that
# status-desktop vendors, so consumers that vendor this repo never pull a
# second copy of seaqt.

SEAQT_REV   := 7d40abd7b493036b4ede5b111fc4260237504796
NIMQML_REV  := fa084a8d9bcf00c9ed4c2adf857793fcc059357f
RESULTS_REV := 06deae1c81fd27b6c94bbc7cd0e619b6905d49da
PRLTOPC_REV := 03a8a91707db7d9257d8617453fefb58fe848904

DEPS  := .deps
NIM   ?= nim
QMAKE ?= qmake
# Nim does not recompile {.compile.}'d C++ (qtcamera/private/shim.cpp) when it
# changes: after editing it run `make test EXTRA_NIMFLAGS=-f`.
NIMFLAGS ?= --hints:off $(EXTRA_NIMFLAGS)

define clone_pinned
	@test -d $(DEPS)/$(1) || git clone --quiet $(2) $(DEPS)/$(1)
	@git -C $(DEPS)/$(1) cat-file -e $(3)^{commit} 2>/dev/null || git -C $(DEPS)/$(1) fetch --quiet origin
	@git -C $(DEPS)/$(1) checkout --quiet $(3)
endef

all: test

deps:
	$(call clone_pinned,nim-seaqt,https://github.com/seaqt/nim-seaqt.git,$(SEAQT_REV))
	$(call clone_pinned,nimqml-seaqt,https://github.com/seaqt/nimqml-seaqt.git,$(NIMQML_REV))
	$(call clone_pinned,nim-results,https://github.com/arnetheduck/nim-results.git,$(RESULTS_REV))
	$(call clone_pinned,prl-to-pc,https://github.com/status-im/prl-to-pc.git,$(PRLTOPC_REV))

# Exports PKG_CONFIG_PATH (and, in generated mode, the pkg-config wrapper on
# PATH) so seaqt's compile-time gorge("pkg-config ...") finds Qt.
-include $(DEPS)/prl-to-pc/qt-pkgconfig.mk

ifeq ($(shell uname -s),Darwin)
 QT_LIBDIR := $(shell $(QMAKE) -query QT_INSTALL_LIBS 2>/dev/null)
 NIMFLAGS += --passL:"-F$(QT_LIBDIR)" --passL:"-Wl,-rpath,$(QT_LIBDIR)"
 # Unbundled macOS binaries need an embedded Info.plist with
 # NSCameraUsageDescription, otherwise Qt refuses camera access.
 NIMFLAGS += --passL:"-Wl,-sectcreate,__TEXT,__info_plist,$(CURDIR)/resources/Info.plist"
endif

TESTS := $(sort $(filter-out tests/testutils.nim,$(wildcard tests/t*.nim)))

test: | qt-pkgconfig
	@for t in $(TESTS); do echo "== $$t"; $(NIM) c -r $(NIMFLAGS) $$t || exit 1; done

spike: | qt-pkgconfig
	QTCAMERA_TEST_WITH_CAMERA=1 $(NIM) c -r $(NIMFLAGS) tests/manual/tspike_camera.nim

camera-test: | qt-pkgconfig
	QTCAMERA_TEST_WITH_CAMERA=1 $(NIM) c -r $(NIMFLAGS) tests/tsession.nim

example: | qt-pkgconfig
	$(NIM) c -r $(NIMFLAGS) examples/camera_preview/main.nim

.PHONY: all deps test spike camera-test example
