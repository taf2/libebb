AUTOMAKE_OPTIONS = foreign no-dependencies

VERSION_INFO = 3:0

EXTRA_DIST = README \
						 ebb.h ebb.c \
						 ebb_request_parser.h ebb_request_parser.c ebb_request_parser.rl \
						 rbtree.h rbtree.c 

SUBDIRS = examples

include_HEADERS = ebb.h ebb_request_parser.h rbtree.h

lib_LTLIBRARIES = libebb.la

libebb_la_SOURCES = ebb.c ebb_request_parser.c rbtree.c
libebb_la_LDFLAGS = -version-info $(VERSION_INFO)

if HAVE_RAGEL
ebb_request_parser.c: ebb_request_parser.rl
	$(RAGEL) -s -G2 $< -o $@
endif

