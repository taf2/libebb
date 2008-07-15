CC=gcc

test: test_parser

objects: parser.o test_parser.o

test_parser: test_parser.o parser.o
	gcc parser.o -g test_parser.o -o $@

%.o: %.c
	gcc -c $< -o $@ -g -Wall

%.c: %.rl
	ragel -s -G2 $< -o $@

clean:
	rm *.o
	rm test_parser

clobber: clean
	rm parser.c
