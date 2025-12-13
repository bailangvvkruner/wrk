# Static compilation support
STATIC ?= 0

CFLAGS  += -std=c99 -Wall -O2 -D_REENTRANT

TARGET  := $(shell uname -s | tr '[A-Z]' '[a-z]' 2>/dev/null || echo unknown)

# Set up libraries based on static or dynamic linking
ifeq ($(STATIC),1)
	BASE_LIBS := -lpthread -lm
	LDFLAGS += -static
	# For static linking, we need to link against the actual .a files
	# Check both lib and lib64 directories for OpenSSL libraries
	# When WITH_OPENSSL is set, use system OpenSSL libraries
	STATIC_LIBS := $(ODIR)/lib/libluajit-5.1.a
ifneq ($(WITH_OPENSSL),)
	# Use system OpenSSL static libraries
	STATIC_LIBS += $(WITH_OPENSSL)/lib/libssl.a $(WITH_OPENSSL)/lib/libcrypto.a
else
	# Use built OpenSSL static libraries
	STATIC_LIBS += \
		$(if $(wildcard $(ODIR)/lib/libssl.a),$(ODIR)/lib/libssl.a,$(ODIR)/lib64/libssl.a) \
		$(if $(wildcard $(ODIR)/lib/libcrypto.a),$(ODIR)/lib/libcrypto.a,$(ODIR)/lib64/libcrypto.a)
endif
else
	BASE_LIBS := -lm -lssl -lcrypto -lpthread
	ifeq ($(TARGET),linux)
		BASE_LIBS += -ldl
	endif
	STATIC_LIBS :=
endif

# Target-specific adjustments
ifeq ($(TARGET), sunos)
	CFLAGS += -D_PTHREADS -D_POSIX_C_SOURCE=200112L
	BASE_LIBS += -lsocket
else ifeq ($(TARGET), darwin)
	export MACOSX_DEPLOYMENT_TARGET = $(shell sw_vers -productVersion)
else ifeq ($(TARGET), linux)
	CFLAGS  += -D_POSIX_C_SOURCE=200112L -D_BSD_SOURCE -D_DEFAULT_SOURCE
	LDFLAGS += -Wl,-E
else ifeq ($(TARGET), freebsd)
	CFLAGS  += -D_DECLARE_C99_LDBL_MATH
	LDFLAGS += -Wl,-E
endif

SRC  := wrk.c net.c ssl.c aprintf.c stats.c script.c units.c \
		ae.c zmalloc.c http_parser.c
BIN  := wrk
VER  ?= $(shell git describe --tags --always --dirty)

ODIR := obj
OBJ  := $(patsubst %.c,$(ODIR)/%.o,$(SRC)) $(ODIR)/bytecode.o $(ODIR)/version.o

DEPS    :=
CFLAGS  += -I$(ODIR)/include
# Add both lib and lib64 directories for library search
LDFLAGS += -L$(ODIR)/lib -L$(ODIR)/lib64

ifneq ($(WITH_LUAJIT),)
	CFLAGS  += -I$(WITH_LUAJIT)/include
	LDFLAGS += -L$(WITH_LUAJIT)/lib
else
	CFLAGS  += -I$(ODIR)/include/luajit-2.1
	DEPS    += $(ODIR)/lib/libluajit-5.1.a
endif

ifneq ($(WITH_OPENSSL),)
	CFLAGS  += -I$(WITH_OPENSSL)/include
	LDFLAGS += -L$(WITH_OPENSSL)/lib
else
	# OpenSSL may install to lib or lib64, check both
	DEPS += $(ODIR)/lib/libssl.a $(ODIR)/lib/libcrypto.a
endif

all: $(BIN)

clean:
	$(RM) -rf $(BIN) obj/*

$(BIN): $(OBJ)
	@echo LINK $(BIN)
ifeq ($(STATIC),1)
	@echo "STATIC_LIBS: $(STATIC_LIBS)"
	@echo "LDFLAGS: $(LDFLAGS)"
	@$(CC) $(LDFLAGS) -o $@ $^ $(STATIC_LIBS) $(BASE_LIBS)
else
	@$(CC) $(LDFLAGS) -o $@ $^ -lluajit-5.1 $(BASE_LIBS)
endif

$(OBJ): config.h Makefile $(DEPS) | $(ODIR)

$(ODIR):
	@mkdir -p $@

$(ODIR)/bytecode.c: src/wrk.lua $(DEPS)
	@echo LUAJIT $<
	@$(SHELL) -c 'PATH="obj/bin:$(PATH)" luajit -b "$(CURDIR)/$<" "$(CURDIR)/$@"'

$(ODIR)/version.o:
	@echo 'const char *VERSION="$(VER)";' | $(CC) -xc -c -o $@ -

$(ODIR)/%.o : %.c
	@echo CC $<
	@$(CC) $(CFLAGS) -c -o $@ $<

# Dependencies - Using git clone instead of zip/tar.gz files

LUAJIT_REPO := https://github.com/LuaJIT/LuaJIT.git
LUAJIT_TAG  := v2.1.0-beta3
LUAJIT_DIR  := $(ODIR)/LuaJIT-$(LUAJIT_TAG)

OPENSSL_REPO := https://github.com/openssl/openssl.git
OPENSSL_TAG  := openssl-3.2.2
OPENSSL_DIR  := $(ODIR)/openssl-$(OPENSSL_TAG)

OPENSSL_OPTS = no-shared no-psk no-srp no-dtls no-idea --prefix=$(abspath $(ODIR)) --libdir=lib

$(LUAJIT_DIR): | $(ODIR)
	@echo "Cloning LuaJIT $(LUAJIT_TAG) from GitHub..."
	@git clone --depth 1 --branch $(LUAJIT_TAG) $(LUAJIT_REPO) $@

$(OPENSSL_DIR): | $(ODIR)
	@echo "Cloning OpenSSL $(OPENSSL_TAG) from GitHub..."
	@git clone --depth 1 --branch $(OPENSSL_TAG) $(OPENSSL_REPO) $@

$(ODIR)/lib/libluajit-5.1.a: $(LUAJIT_DIR)
	@echo Building LuaJIT...
	@$(MAKE) -C $< PREFIX=$(abspath $(ODIR)) BUILDMODE=static install
	@cd $(ODIR)/bin && ln -s luajit-2.1.0-beta3 luajit

$(ODIR)/lib/libssl.a $(ODIR)/lib/libcrypto.a: $(OPENSSL_DIR)
	@echo Building OpenSSL...
	@$(SHELL) -c "cd $< && ./config $(OPENSSL_OPTS)"
	@$(MAKE) -C $< depend
	@$(MAKE) -C $<
	@$(MAKE) -C $< install_sw
	@touch $(ODIR)/lib/libssl.a
	@touch $(ODIR)/lib/libcrypto.a

# ------------

.PHONY: all clean
.PHONY: $(ODIR)/version.o

.SUFFIXES:
.SUFFIXES: .c .o .lua

vpath %.c   src
vpath %.h   src
vpath %.lua scripts
