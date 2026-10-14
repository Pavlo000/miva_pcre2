FILENAME       := miva_pcre2

VM             ?= /Users/pasha/mivavm
MVC            ?= /Users/pasha/mvc
MVC_BIN        := $(MVC)/bin/mvc

INCDIR         := include
SRCDIR         := src
OUTDIR         := bin
TESTDIR        := test
TESTFILE       := $(TESTDIR)/test.mv

SRC            := $(SRCDIR)/$(FILENAME).c
HDR            := $(SRCDIR)/$(FILENAME).h

PCRE2_SRC      := $(INCDIR)/pcre2

# Host VM is macOS x86_64 (Rosetta). Production stores are usually Linux.
# Outputs land in bin/<platform>/ so each ABI can be shipped separately.
LOCAL_PLATFORM := darwin-x86_64
PLATFORMS      := darwin-x86_64 darwin-arm64 linux-x86_64 linux-arm64 win64

LOCAL_TARGET   := $(OUTDIR)/$(LOCAL_PLATFORM)/$(FILENAME).so
LINUX_IMAGE    := gcc:13-bookworm
WIN_IMAGE      := dockcross/windows-static-x64

COMMON_CFLAGS  := -fPIC -O2 -Wall -I$(INCDIR) -DPCRE2_STATIC

# Per-arch static PCRE2 builds (cmake --build include/pcre2/build-darwin-*)
PCRE2_BUILD_DARWIN_X86_64 := $(PCRE2_SRC)/build-darwin-x86_64
PCRE2_BUILD_DARWIN_ARM64  := $(PCRE2_SRC)/build-darwin-arm64
PCRE2_BUILD_LINUX_X86_64  := $(PCRE2_SRC)/build-linux-x86_64
PCRE2_BUILD_LINUX_ARM64   := $(PCRE2_SRC)/build-linux-arm64
PCRE2_LIB_DARWIN_X86_64   := $(PCRE2_BUILD_DARWIN_X86_64)/libpcre2-8.a
PCRE2_LIB_DARWIN_ARM64    := $(PCRE2_BUILD_DARWIN_ARM64)/libpcre2-8.a
PCRE2_LIB_LINUX_X86_64    := $(PCRE2_BUILD_LINUX_X86_64)/libpcre2-8.a
PCRE2_LIB_LINUX_ARM64     := $(PCRE2_BUILD_LINUX_ARM64)/libpcre2-8.a
PCRE2_INC_DARWIN_X86_64   := $(PCRE2_BUILD_DARWIN_X86_64)/interface
PCRE2_INC_DARWIN_ARM64    := $(PCRE2_BUILD_DARWIN_ARM64)/interface
PCRE2_INC_LINUX_X86_64    := $(PCRE2_BUILD_LINUX_X86_64)/interface
PCRE2_INC_LINUX_ARM64     := $(PCRE2_BUILD_LINUX_ARM64)/interface

.PHONY: all local darwin darwin-x86_64 darwin-arm64 linux linux-x86_64 linux-arm64 win64 \
        pcre2-darwin-x86_64 pcre2-darwin-arm64 pcre2-linux-x86_64 pcre2-linux-arm64 \
        install test clean help

all: darwin-x86_64 darwin-arm64 linux-x86_64 linux-arm64 win64

help:
	@echo "Targets:"
	@echo "  make / make all   build every platform under $(OUTDIR)/"
	@echo "  make local        build $(LOCAL_PLATFORM) only (matches this mivavm)"
	@echo "  make install      install local .so into VM + mvc builtins"
	@echo "  make test         install + run $(TESTFILE)"
	@echo "  make pcre2-darwin-x86_64 | pcre2-darwin-arm64"
	@echo "  make darwin-x86_64 | darwin-arm64 | linux-x86_64 | linux-arm64 | win64"
	@echo "  make clean"

local: $(LOCAL_TARGET)

# ---------------------------------------------------------------------------
# PCRE2 static libs (required before linking the plugin)
# ---------------------------------------------------------------------------

pcre2-darwin-x86_64: $(PCRE2_LIB_DARWIN_X86_64)
pcre2-darwin-arm64:  $(PCRE2_LIB_DARWIN_ARM64)

$(PCRE2_LIB_DARWIN_X86_64):
	@mkdir -p $(PCRE2_BUILD_DARWIN_X86_64)
	@cmake -S $(PCRE2_SRC) -B $(PCRE2_BUILD_DARWIN_X86_64) \
		-DCMAKE_OSX_ARCHITECTURES=x86_64 \
		-DBUILD_SHARED_LIBS=OFF \
		-DPCRE2_STATIC_PIC=ON \
		-DPCRE2_BUILD_TESTS=OFF \
		-DPCRE2_BUILD_PCRE2GREP=OFF
	@cmake --build $(PCRE2_BUILD_DARWIN_X86_64) -j

$(PCRE2_LIB_DARWIN_ARM64):
	@mkdir -p $(PCRE2_BUILD_DARWIN_ARM64)
	@cmake -S $(PCRE2_SRC) -B $(PCRE2_BUILD_DARWIN_ARM64) \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DBUILD_SHARED_LIBS=OFF \
		-DPCRE2_STATIC_PIC=ON \
		-DPCRE2_BUILD_TESTS=OFF \
		-DPCRE2_BUILD_PCRE2GREP=OFF
	@cmake --build $(PCRE2_BUILD_DARWIN_ARM64) -j

pcre2-linux-x86_64: $(PCRE2_LIB_LINUX_X86_64)
pcre2-linux-arm64:  $(PCRE2_LIB_LINUX_ARM64)

$(PCRE2_LIB_LINUX_X86_64):
	@docker run --rm --platform linux/amd64 \
		-v "$(CURDIR):/src" -w /src $(LINUX_IMAGE) \
		bash -c 'set -euo pipefail; \
			apt-get update -qq && apt-get install -y -qq cmake >/dev/null; \
			cmake -S $(PCRE2_SRC) -B $(PCRE2_BUILD_LINUX_X86_64) \
				-DBUILD_SHARED_LIBS=OFF -DPCRE2_STATIC_PIC=ON \
				-DPCRE2_BUILD_TESTS=OFF -DPCRE2_BUILD_PCRE2GREP=OFF; \
			cmake --build $(PCRE2_BUILD_LINUX_X86_64) -j"$$(nproc)"'

$(PCRE2_LIB_LINUX_ARM64):
	@docker run --rm --platform linux/arm64 \
		-v "$(CURDIR):/src" -w /src $(LINUX_IMAGE) \
		bash -c 'set -euo pipefail; \
			apt-get update -qq && apt-get install -y -qq cmake >/dev/null; \
			cmake -S $(PCRE2_SRC) -B $(PCRE2_BUILD_LINUX_ARM64) \
				-DBUILD_SHARED_LIBS=OFF -DPCRE2_STATIC_PIC=ON \
				-DPCRE2_BUILD_TESTS=OFF -DPCRE2_BUILD_PCRE2GREP=OFF; \
			cmake --build $(PCRE2_BUILD_LINUX_ARM64) -j"$$(nproc)"'

# ---------------------------------------------------------------------------
# macOS — Mach-O bundle (same filetype as stock Miva builtins)
# ---------------------------------------------------------------------------

darwin: darwin-x86_64 darwin-arm64

darwin-x86_64: $(OUTDIR)/darwin-x86_64/$(FILENAME).so
darwin-arm64:  $(OUTDIR)/darwin-arm64/$(FILENAME).so

$(OUTDIR)/darwin-x86_64/$(FILENAME).so: $(SRC) $(HDR) $(PCRE2_LIB_DARWIN_X86_64) | $(OUTDIR)/darwin-x86_64
	@clang $(COMMON_CFLAGS) -I$(PCRE2_INC_DARWIN_X86_64) -arch x86_64 -bundle -undefined dynamic_lookup \
		-o $@ $(SRC) $(PCRE2_LIB_DARWIN_X86_64)

$(OUTDIR)/darwin-arm64/$(FILENAME).so: $(SRC) $(HDR) $(PCRE2_LIB_DARWIN_ARM64) | $(OUTDIR)/darwin-arm64
	@clang $(COMMON_CFLAGS) -I$(PCRE2_INC_DARWIN_ARM64) -arch arm64 -bundle -undefined dynamic_lookup \
		-o $@ $(SRC) $(PCRE2_LIB_DARWIN_ARM64)

# ---------------------------------------------------------------------------
# Linux — ELF .so via Docker, statically linked with PCRE2 (drop-in ready)
# ---------------------------------------------------------------------------

linux: linux-x86_64 linux-arm64

linux-x86_64: $(OUTDIR)/linux-x86_64/$(FILENAME).so
linux-arm64:  $(OUTDIR)/linux-arm64/$(FILENAME).so

$(OUTDIR)/linux-x86_64/$(FILENAME).so: $(SRC) $(HDR) $(PCRE2_LIB_LINUX_X86_64) | $(OUTDIR)/linux-x86_64
	@docker run --rm --platform linux/amd64 \
		-v "$(CURDIR):/src" -w /src $(LINUX_IMAGE) \
		gcc $(COMMON_CFLAGS) -I$(PCRE2_INC_LINUX_X86_64) -shared -o $@ $(SRC) $(PCRE2_LIB_LINUX_X86_64)

$(OUTDIR)/linux-arm64/$(FILENAME).so: $(SRC) $(HDR) $(PCRE2_LIB_LINUX_ARM64) | $(OUTDIR)/linux-arm64
	@docker run --rm --platform linux/arm64 \
		-v "$(CURDIR):/src" -w /src $(LINUX_IMAGE) \
		gcc $(COMMON_CFLAGS) -I$(PCRE2_INC_LINUX_ARM64) -shared -o $@ $(SRC) $(PCRE2_LIB_LINUX_ARM64)

# ---------------------------------------------------------------------------
# Windows — DLL via dockcross (pulled on first use)
# ---------------------------------------------------------------------------

win64: $(OUTDIR)/win64/$(FILENAME).dll

$(OUTDIR)/win64/$(FILENAME).dll: $(SRC) $(HDR) | $(OUTDIR)/win64
	@docker run --rm \
		-v "$(CURDIR):/work" -w /work $(WIN_IMAGE) \
		bash -c '$$CC $(COMMON_CFLAGS) -shared -o $@ $(SRC)'

# ---------------------------------------------------------------------------

$(OUTDIR)/%:
	@mkdir -p $@

# Runtime: VM loads every .so in DIR_BUILTIN
# Compile-time: mvc -B can see the same builtins when resolving names
install: $(LOCAL_TARGET)
	@cp $(LOCAL_TARGET) $(VM)/lib/builtins/$(FILENAME).so
	@cp $(LOCAL_TARGET) $(MVC)/builtins/$(FILENAME).so

# Compile test script into the web root, then invoke mivavm as CGI.
# Body only: strip CGI headers (everything up to the first blank line).
test: install
	@$(MVC_BIN) -B $(MVC)/builtins -o $(VM)/mivaroot/$(FILENAME).mvc $(TESTFILE)
	@out=$$(REQUEST_METHOD=GET \
	SCRIPT_NAME=/cgi-bin/mivavm-v5.52 \
	PATH_INFO=/$(FILENAME).mvc \
	SCRIPT_FILENAME=$(VM)/mivaroot/$(FILENAME).mvc \
	DOCUMENT_ROOT=$(VM)/mivaroot \
	SERVER_SOFTWARE=make/test \
	SERVER_NAME=localhost \
	SERVER_PROTOCOL=HTTP/1.0 \
	GATEWAY_INTERFACE=CGI/1.1 \
	REMOTE_ADDR=127.0.0.1 \
	MvCONFIG_LIBRARY=$(VM)/lib/config/env.so \
	MvCONFIG_DIR_MIVA=$(VM)/mivaroot \
	MvCONFIG_DIR_DATA=$(VM)/mivadata \
	MvCONFIG_DIR_BUILTIN=$(VM)/lib/builtins \
	$(VM)/cgi-bin/mivavm-v5.52 2>&1); \
	body=$$(printf '%s' "$$out" | awk 'found { print } /^\r?$$/ { found = 1 }'); \
	if [ -z "$$body" ]; then \
		echo "make test: empty response (plugin may have failed to load). Raw output:"; \
		printf '%s\n' "$$out"; \
		exit 1; \
	fi; \
	printf '%s\n' "$$body"

clean:
	@rm -rf $(OUTDIR)
	@rm -f $(VM)/lib/builtins/$(FILENAME).so $(MVC)/builtins/$(FILENAME).so
	@rm -f $(VM)/mivaroot/$(FILENAME).mvc
