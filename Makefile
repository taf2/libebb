#based on the makefiles in rubinius 

# Respect the environment
ifeq ($(CC),)
  CC=gcc
endif

UNAME=$(shell uname)
CPU=$(shell uname -p)
MARCH=$(shell uname -m)
OSVER=$(shell uname -r)

WARNINGS = -Wall
DEBUG = -g -ggdb3

CFLAGS = -I. $(WARNINGS) $(DEBUG)



COMP=$(CC)
ifeq ($(UNAME),Darwin)
  LDOPT=-dynamiclib 
  SUFFIX=dylib
  SONAME=-current_version $(VERSION) -compatibility_version $(VERSION)
else
  LDOPT=-shared
  SUFFIX=so
  ifneq ($(UNAME),SunOS)
    SONAME=-Wl,-soname,libptr_array-$(VERSION).$(SUFFIX)
  endif
endif

BIN_RPATH=
LINKER=$(CC) $(LDOPT)
RANLIB = ranlib

ifndef VERBOSE
  COMP=@echo CC $@;$(CC)
  LINKER=@echo LINK $@;$(CC) $(LDOPT)
endif

VERSION=0.1

NAME=libebb
OUTPUT_LIB=$(NAME).$(VERSION).$(SUFFIX)
OUTPUT_A=$(NAME).a

ifeq ($(UNAME),Darwin)
  SINGLE_MODULE=-Wl,-single_module
  ifeq ($(OSVER),9.1.0)
    export MACOSX_DEPLOYMENT_TARGET=10.5
  else
    export MACOSX_DEPLOYMENT_TARGET=10.4
  endif
else
  SINGLE_MODULE=
endif

ifeq ($(UNAME),SunOS)
  CFLAGS+=-D__C99FEATURES__
endif

ifdef DEV
  OPTIMIZATIONS=
else
  INLINE_OPTS=
  OPTIMIZATIONS=-O2 -funroll-loops -finline-functions $(INLINE_OPTS)
endif

ifeq ($(CPU), powerpc)
  OPTIMIZATIONS+=-falign-loops=16
endif

CFLAGS += -fPIC $(CPPFLAGS)
DEPS = ebb.h ebb_request_parser.h rbtree.h
LIBS = -lev

GNUTLS_EXISTS = $(shell pkg-config --silence-errors --exists gnutls || echo "no")
ifneq (GNUTLS_EXISTS,no)
	CFLAGS += $(shell pkg-config --cflags gnutls) -DHAVE_GNUTLS=1
	LIBS += $(shell pkg-config --libs gnutls)
	USING_GNUTLS = "yes"
else
	USING_GNUTLS = "no"
endif

SOURCES=ebb.c ebb_request_parser.c rbtree.c
OBJS=$(SOURCES:.c=.o)

%.o: %.c
	$(COMP) $(CFLAGS) $(OPTIMIZATIONS) -c $< -o $@

%.o: %.S
	$(COMP) $(CFLAGS) $(OPTIMIZATIONS) -c $< -o $@

.%.d:  %.c  $(DEPS)
	@echo DEP $<
	@set -e; rm -f $@; \
	$(CC) -MM $(CPPFLAGS) $< > $@.$$$$; \
	sed 's,\($*\)\.o[ :]*,\1.o $@ : ,g' < $@.$$$$ > $@; \
	rm -f $@.$$$$

library: $(OUTPUT_LIB) $(OUTPUT_A)
	@echo "using GnuTLS... ${USING_GNUTLS}"

$(OUTPUT_LIB): $(DEPS) $(OBJS) 
	$(LINKER) -o $(OUTPUT_LIB) $(OBJS) $(SONAME) $(LIBS)

$(OUTPUT_A): $(DEPS) $(OBJS)
	$(AR) cru $(OUTPUT_A) $(OBJS)
	$(RANLIB) $(OUTPUT_A)

.PHONY: library

ebb_request_parser.c: ebb_request_parser.rl
	ragel -s -G2 $< -o $@

clean:
	rm -f *.o *.lo *.la *.so *.dylib *.a test_rbtree test_request_parser examples/hello_world

clobber: clean
	rm -f ebb_request_parser.c

.PHONY: clean clobber

test: test_request_parser test_rbtree
	./test_request_parser
	./test_rbtree

test_rbtree: test_rbtree.o $(OUTPUT_A)
	$(CC) -o $@ $< $(OUTPUT_A)

test_request_parser: test_request_parser.o $(OUTPUT_A)
	$(CC) -o $@ $< $(OUTPUT_A)

.PHONY: test

examples: examples/hello_world

examples/hello_world: examples/hello_world.o $(OUTPUT_A) 
	$(CC) -lev -o $@ $< $(OUTPUT_A)

.PHONY: examples

tags: *.c *.h *.rl examples/*.c
	ctags $^

install: $(OUTPUT_A)
	install -d -m755 ${prefix}/lib
	install -d -m755 ${prefix}/include
	install -m644 $(OUTPUT_A) ${prefix}/lib 
	install -m644 ebb.h ebb_request_parser.h ${prefix}/include 

upload_website:
	scp -r doc/index.html doc/icon.png rydahl@tinyclouds.org:~/web/public/libebb


ifneq ($(MAKECMDGOALS),clean)
-include $(SOURCES:%.c=.%.d)
endif
