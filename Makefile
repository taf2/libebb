LIBEV = ${HOME}/local/libev
CFLAGS = -g -Wall -fPIC -I${LIBEV}/include `pkg-config --cflags gnutls`
LIBS = -L${LIBEV}/lib -lev `pkg-config --libs gnutls`
GCC_OPTS  = -fPIC -g -Wall 

#libebb.so.0.0.1: objects
#	gcc -shared -Wl,-soname,libebb.so.0 -o $@ ebb.o ebb_request_parser.o

objects: ebb.o ebb_request_parser.o rbtree.o

ebb.o: ebb.c ebb.h
	gcc ${CFLAGS} -c $< -o $@

rbtree.o: rbtree.c rbtree.h
	gcc ${CFLAGS} -c $< -o $@

ebb_request_parser.o: ebb_request_parser.c ebb_request_parser.h
	gcc ${CFLAGS} -c $< -o $@

ebb_request_parser.c: ebb_request_parser.rl
	ragel -s -G2 $< -o $@

test_request_parser: test_request_parser.c ebb_request_parser.o
	gcc ${CFLAGS} -lefence  $^ -o $@

test_rbtree: test_rbtree.c rbtree.o
	gcc ${CFLAGS} -lefence  $^ -o $@

examples: examples/hello_world

examples/hello_world: examples/hello_world.c ebb.o ebb_request_parser.o rbtree.o
	gcc ${CFLAGS} ${LIBS} -lefence $^ -o $@

.PHONY: clean test clobber

wc:
	wc -l ebb_request_parser.rl ebb_request_parser.h ebb.c ebb.h test_*.c

test: test_request_parser test_rbtree
	./test_request_parser
	./test_rbtree

upload_website:
	scp -r doc/index.html doc/icon.png rydahl@tinyclouds.org:~/web/public/libebb

clean:
	@-rm -f *.o
	@-rm -f test_request_parser
	@-rm -f test_rbtree
	@-rm -f examples/hello_world
	@-rm -f libebb.so.0.0.1
	
clobber: clean
	@-rm -f ebb_request_parser.c
