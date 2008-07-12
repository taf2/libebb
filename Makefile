SOURCES := $(wildcard *.c)

test: chunk_test
	./chunk_test

chunk_test: chunked_message.c chunked_message.h
	gcc -DUNITTEST $< -o $@

%.c: %.rl
	ragel -s -G2 $< -o $@


clean:
	rm chunk_test

clobber: clean
	rm chunked_message.c
