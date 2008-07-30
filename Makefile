LIBEVDIR = ${HOME}/local/libev

# where to install to. 
# will create ${prefix}/include and ${prefix}/lib
prefix = ${HOME}/local/libebb

CFLAGS = -g -Wall -fPIC -O3
LIBS = -L${LIBEVDIR}/lib -lev `pkg-config --libs gnutls`

#
# libebb.so
#

libebb.so: ebb.o ebb_request_parser.o rbtree.o
	gcc -shared -o $@ $^

ebb.o: ebb.c ebb.h
	gcc ${CFLAGS} -I${LIBEVDIR}/include `pkg-config --cflags gnutls` -c $< -o $@

rbtree.o: rbtree.c rbtree.h
	gcc ${CFLAGS} -c $< -o $@

ebb_request_parser.o: ebb_request_parser.c ebb_request_parser.h
	gcc ${CFLAGS} -c $< -o $@

ebb_request_parser.c: ebb_request_parser.rl
	ragel -s -G2 $< -o $@

#
# Test programs
#

test_request_parser: test_request_parser.c ebb_request_parser.o
	gcc ${CFLAGS} $^ -o $@ # -lefence  

test_rbtree: test_rbtree.c rbtree.o
	gcc ${CFLAGS} $^ -o $@ # -lefence 

test: test_request_parser test_rbtree
	./test_request_parser
	./test_rbtree

#
# Example programs
#

examples: examples/hello_world

examples/hello_world: examples/hello_world.c ebb.o ebb_request_parser.o rbtree.o 
	gcc ${CFLAGS} ${LIBS} -lefence $^ -o $@

#
# Other
#

tags: *.c *.h *.rl examples/*.c
	ctags $^

upload_website:
	scp -r doc/index.html doc/icon.png rydahl@tinyclouds.org:~/web/public/libebb

install: libebb.so
	install -d -m755 ${prefix}/lib
	install -d -m755 ${prefix}/include
	install -m644 libebb.so ${prefix}/lib 
	install -m644 ebb.h ebb_request_parser.h ${prefix}/include 

clean:
	-rm -f *.o
	-rm -f test_request_parser
	-rm -f test_rbtree
	-rm -f examples/hello_world
	-rm -f libebb.so
	
clobber: clean
	-rm -f ebb_request_parser.c
