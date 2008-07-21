LIBEV = ${HOME}/local/libev
GCC_OPTS  = -fPIC -g -Wall 

#libebb.so.0.0.1: objects
#	gcc -shared -Wl,-soname,libebb.so.0 -o $@ ebb.o ebb_request_parser.o

objects: ebb.o ebb_request_parser.o 

ebb.o: ebb.c ebb.h
	gcc -fPIC -I${LIBEV}/include -c $< -o $@ -g -Wall

ebb_request_parser.o: ebb_request_parser.c ebb_request_parser.h
	gcc ${GCC_OPTS} -c $< -o $@ 

ebb_request_parser.c: ebb_request_parser.rl
	ragel -s -G2 $< -o $@

test_request_parser: test_request_parser.c ebb_request_parser.o
	gcc ${GCC_OPTS} -lefence  $^ -o $@

examples: examples/hello_world

examples/hello_world: examples/hello_world.c ebb.o ebb_request_parser.o
	gcc ${GCC_OPTS} -lefence -I. -L${LIBEV}/lib -lev -I${LIBEV}/include $^ -o $@

.PHONY: clean test clobber

wc:
	wc -l ebb_request_parser.rl ebb_request_parser.h ebb.c ebb.h test_*.c

test: test_request_parser
	./test_request_parser

upload_website:
	scp -r doc/index.html doc/icon.png rydahl@tinyclouds.org:~/web/public/libebb


clean:
	@-rm -f *.o
	@-rm -f test_request_parser
	@-rm -f examples/hello_world
	@-rm -f libebb.so.0.0.1
	
clobber: clean
	@-rm -f ebb_request_parser.c
