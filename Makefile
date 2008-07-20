LIBEV = ${HOME}/local/libev
GCC_OPTS  = -fPIC -g -Wall 

#libebb.so.0.0.1: objects
#	gcc -shared -Wl,-soname,libebb.so.0 -o $@ server.o request_parser.o

objects: server.o request_parser.o 

server.o: server.c server.h
	gcc -fPIC -I${LIBEV}/include -c $< -o $@ -g -Wall

request_parser.o: request_parser.c request_parser.h
	gcc ${GCC_OPTS} -c $< -o $@ 

request_parser.c: request_parser.rl
	ragel -s -G2 $< -o $@

test_request_parser: test_request_parser.c request_parser.o
	gcc ${GCC_OPTS} -lefence  $^ -o $@

examples: examples/hello_world

examples/hello_world: examples/hello_world.c server.o request_parser.o
	gcc ${GCC_OPTS} -lefence -I. -L${LIBEV}/lib -lev -I${LIBEV}/include $^ -o $@

.PHONY: clean test clobber

wc:
	wc -l request_parser.rl request_parser.h server.c server.h test_*.c

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
	@-rm -f request_parser.c
