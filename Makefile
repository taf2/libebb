LIBEV = ${HOME}/local/libev
GCC_OPTS  = -fPIC -g -Wall 

#libebb.so.0.0.1: objects
#	gcc -shared -Wl,-soname,libebb.so.0 -o $@ ebb.o request_parser.o

objects: ebb.o request_parser.o 

ebb.o: ebb.c ebb.h
	gcc -fPIC -I${LIBEV}/include -c $< -o $@ -g -Wall

request_parser.o: request_parser.c request_parser.h
	gcc ${GCC_OPTS} -c $< -o $@ 

request_parser.c: request_parser.rl
	ragel -s -G2 $< -o $@

test_request_parser: test_request_parser.c request_parser.o
	gcc ${GCC_OPTS}  $< request_parser.o -o $@

test_server: test_server.c ebb.o request_parser.o
	gcc ${GCC_OPTS} -L${LIBEV}/lib -lev -I${LIBEV}/include $< ebb.o request_parser.o -o $@


.PHONY: clean test clobber

test: test_request_parser
	./test_request_parser

clean:
	-rm -f *.o
	-rm -f test_request_parser test_server
	-rm -f libebb.so.0.0.1
	
clobber: clean
	-rm -f request_parser.c
