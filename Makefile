SOURCES := $(wildcard *.c)

test: chunk_test parser_test
	./chunk_test
	./parser_test

chunk_test: chunked_message.c chunked_message.h
	gcc -g -DUNITTEST $< -o $@

parser_test: parser.c parser.h
	gcc -g -DUNITTEST $< -o $@

%.c: %.rl
	ragel -s -G2 $< -o $@

clean:
	rm chunk_test
	rm parser_test

clobber: clean
	rm chunked_message.c
	rm parser.c
