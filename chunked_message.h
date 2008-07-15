/* Copyright Ryan Dahl, 2008. All rights reserved. */

#ifndef chunk_parser_h
#define chunk_parser_h

#include <sys/types.h>

#if defined(_WIN32)
#include <stddef.h>
#endif

typedef void (*element_cb)(void *data, const char *at, size_t length);
typedef void (*field_cb)(void *data, const char *field, size_t flen, const char *value, size_t vlen);

typedef struct chunked_parser {
  int cs;
  size_t nread;
  const char * mark;

  unsigned eating:1;
  size_t chunk_size;
  size_t field_start;
  size_t field_len;

  void *data;

  field_cb http_field;
  element_cb chunk_handler;
  
} chunked_parser;

void chunked_parser_init
  ( chunked_parser *parser
  );

size_t chunked_parser_execute
  ( chunked_parser *parser
  , const char *data
  , size_t len
  );

int chunked_parser_has_error(chunked_parser *parser);
int chunked_parser_is_finished(chunked_parser *parser);


#endif
