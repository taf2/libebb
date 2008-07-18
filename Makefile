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

test_server: test_server.c server.o request_parser.o
	gcc ${GCC_OPTS} -lefence -L${LIBEV}/lib -lev -I${LIBEV}/include $^ -o $@


.PHONY: doc clean test clobber

wc:
	wc -l request_parser.rl request_parser.h server.c server.h test_*.c

doc: 
	doxygen 

test: test_request_parser
	./test_request_parser

clean:
	@-rm -f *.o
	@-rm -f test_request_parser test_server
	@-rm -f libebb.so.0.0.1
	
clobber: clean
	@-rm -f request_parser.c
