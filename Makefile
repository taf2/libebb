LIBEV = ${HOME}/local/libev
GCC_OPTS  = -fPIC -g -Wall 

libebb.so.0.0.1: objects
	gcc -shared -Wl,-soname,libebb.so.0 -o $@ server.o parser.o

objects: server.o parser.o 

server.o: server.c server.h
	gcc -fPIC -I${LIBEV}/include -c $< -o $@ -g -Wall

test_parser: test_parser.c parser.o
	gcc ${GCC_OPTS}  $< parser.o -o $@

%.o: %.c
	gcc ${GCC_OPTS} -c $< -o $@ 

parser.c: parser.rl
	ragel -s -G2 $< -o $@

.PHONY: clean test clobber

test: test_parser
	./test_parser

clean:
	-rm -f *.o
	-rm -f test_parser
	-rm -f libebb.so.0.0.1
	
clobber: clean
	-rm -f parser.c
