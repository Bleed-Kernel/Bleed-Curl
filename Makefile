CURL_VER       = 8.11.1
CURL_URL       = https://github.com/curl/curl/releases/download/curl-8_11_1/curl-$(CURL_VER).tar.gz
CURL_SHA256    = a889ac9dbba3644271bd9d1302b5c22a088893719b72be3487bc3d401e5c4e80
MBEDTLS_VER    = 3.6.2
MBEDTLS_URL    = https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$(MBEDTLS_VER)/mbedtls-$(MBEDTLS_VER).tar.bz2
MBEDTLS_SHA256 = 8b54fb9bcf4d5a7078028e0520acddefb7900b3e66fec7f7175bb5b7d85ccdca
CACERT_URL     = https://raw.githubusercontent.com/certifi/python-certifi/2024.12.14/certifi/cacert.pem
CACERT_SHA256  = 807897254f383a27f45e44f49656f378abab2141ede43a4ad3c2420a597dd23f

CURL_SRC    = external/curl-$(CURL_VER)
MBEDTLS_SRC = external/mbedtls-$(MBEDTLS_VER)
CACERT      = external/cacert.pem

BLIBC_DIR  ?= $(if $(wildcard ../blibc/include/bleed),../blibc,external/blibc)
BLIBC_REPO  = https://github.com/Bleed-Kernel/blibc.git
KERNEL_DIR ?= ../Bleed-Kernel

CC          = x86_64-elf-gcc
AR          = x86_64-elf-ar
SHA256      = $(shell command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo "shasum -a 256")

BUILD       = build
SYSROOT     = $(BLIBC_DIR)/sysroot

CFLAGS = \
	-ffreestanding \
	-fno-stack-protector \
	-fno-stack-check \
	-nostdlib \
	-no-pie \
	-m64 \
	-O2 \
	-w \
	-nostdinc \
	-D__bleed__=1 \
	-I$(SYSROOT)/include \
	-I$(SYSROOT)/include/bleed

MBEDTLS_DEFS = -Ibleed -I$(MBEDTLS_SRC)/include -DMBEDTLS_USER_CONFIG_FILE='"mbedtls_bleed.h"'
LIB_DEFS     = $(MBEDTLS_DEFS) -I$(CURL_SRC)/include -I$(CURL_SRC)/lib -DHAVE_CONFIG_H -DBUILDING_LIBCURL -DCURL_STATICLIB
TOOL_DEFS    = $(MBEDTLS_DEFS) -I$(CURL_SRC)/include -I$(CURL_SRC)/lib -I$(CURL_SRC)/src -DHAVE_CONFIG_H -DCURL_STATICLIB

LDFLAGS = \
	-static \
	-nostdlib \
	-no-pie \
	-m64

MBEDTLS_C = $(wildcard $(MBEDTLS_SRC)/library/*.c)
LIB_C     = $(wildcard $(CURL_SRC)/lib/*.c $(CURL_SRC)/lib/vauth/*.c $(CURL_SRC)/lib/vtls/*.c $(CURL_SRC)/lib/vquic/*.c $(CURL_SRC)/lib/vssh/*.c)
TOOL_C    = $(wildcard $(CURL_SRC)/src/*.c)
CURLX_C   = $(addprefix $(CURL_SRC)/src/,$(shell sed -n '/^CURLX_CFILES/,/^$$/p' $(CURL_SRC)/src/Makefile.inc | grep -o '\.\./lib/[a-z0-9_/]*\.c'))

MBEDTLS_O = $(patsubst $(MBEDTLS_SRC)/library/%.c,$(BUILD)/mbedtls/%.o,$(MBEDTLS_C))
LIB_O     = $(patsubst $(CURL_SRC)/lib/%.c,$(BUILD)/lib/%.o,$(LIB_C))
TOOL_O    = $(patsubst $(CURL_SRC)/src/%.c,$(BUILD)/src/%.o,$(TOOL_C))
CURLX_O   = $(patsubst $(CURL_SRC)/src/../lib/%.c,$(BUILD)/curlx/%.o,$(CURLX_C))

.PHONY: all source blibc initrd install clean distclean

all: source | blibc
	@$(MAKE) --no-print-directory bin/curl

source: $(CURL_SRC)/.unpacked $(MBEDTLS_SRC)/.unpacked $(CACERT)

external/%.tar.gz external/%.tar.bz2:
	@mkdir -p external
	curl -fsSL -o $@.tmp $(if $(findstring mbedtls,$@),$(MBEDTLS_URL),$(CURL_URL))
	echo "$(if $(findstring mbedtls,$@),$(MBEDTLS_SHA256),$(CURL_SHA256))  $@.tmp" | $(SHA256) -c - >/dev/null
	mv $@.tmp $@

$(CURL_SRC)/.unpacked: external/curl-$(CURL_VER).tar.gz
	tar -xzf $< -C external
	@touch $@

$(MBEDTLS_SRC)/.unpacked: external/mbedtls-$(MBEDTLS_VER).tar.bz2
	tar -xjf $< -C external
	@touch $@

$(CACERT):
	@mkdir -p external
	curl -fsSL -o $@.tmp $(CACERT_URL)
	echo "$(CACERT_SHA256)  $@.tmp" | $(SHA256) -c - >/dev/null
	mv $@.tmp $@

blibc:
	@if [ ! -d "$(BLIBC_DIR)" ]; then git clone $(BLIBC_REPO) $(BLIBC_DIR); fi
	@$(MAKE) -C $(BLIBC_DIR) --no-print-directory

$(BUILD)/mbedtls/%.o: $(MBEDTLS_SRC)/library/%.c bleed/mbedtls_bleed.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(MBEDTLS_DEFS) -I$(MBEDTLS_SRC)/library -c $< -o $@

$(BUILD)/lib/%.o: $(CURL_SRC)/lib/%.c bleed/curl_config.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(LIB_DEFS) -c $< -o $@

$(BUILD)/src/%.o: $(CURL_SRC)/src/%.c bleed/curl_config.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(TOOL_DEFS) -c $< -o $@

$(BUILD)/curlx/%.o: $(CURL_SRC)/lib/%.c bleed/curl_config.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(TOOL_DEFS) -c $< -o $@

$(BUILD)/bleed_platform.o: bleed/bleed_platform.c
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/libmbedtls.a: $(MBEDTLS_O) $(BUILD)/bleed_platform.o
	rm -f $@
	$(AR) rcs $@ $^

$(BUILD)/libcurl.a: $(LIB_O)
	rm -f $@
	$(AR) rcs $@ $^

bin/curl: $(TOOL_O) $(CURLX_O) $(BUILD)/libcurl.a $(BUILD)/libmbedtls.a $(SYSROOT)/lib/blibc.a
	@mkdir -p bin
	$(CC) $(LDFLAGS) -o $@ $(SYSROOT)/lib/start.o $(TOOL_O) $(CURLX_O) $(BUILD)/libcurl.a $(BUILD)/libmbedtls.a $(SYSROOT)/lib/blibc.a -lgcc

initrd: $(CACERT)
	@test -n "$(INITRD)" || { echo "make initrd INITRD=<the kernels initrd folder>"; exit 1; }
	mkdir -p $(INITRD)/etc/ssl
	COPYFILE_DISABLE=1 cp $(CACERT) $(INITRD)/etc/ssl/cacert.pem

install: all
	COPYFILE_DISABLE=1 cp bin/curl $(KERNEL_DIR)/initrd/bin/curl
	$(MAKE) initrd INITRD=$(abspath $(KERNEL_DIR)/initrd)

clean:
	rm -rf $(BUILD) bin

distclean: clean
	rm -rf external
