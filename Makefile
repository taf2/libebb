SOURCES := $(wildcard *.c)

test: test_parser
	./test_parser

objects: parser.o

test_parser: test_parser.c parser.o
	gcc -g parser.o $< -o $@

%.o: %.o
	gcc -gc $< -o $@

%.c: %.rl
	ragel -s -G2 $< -o $@

clean:
	rm *.o
	rm test_parser

clobber: clean
	rm parser.c
