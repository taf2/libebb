#ifndef ew_h
#define ew_h
#include <sys/types.h> 

typedef void (*element_cb)(void *data, const char *at, size_t length);
typedef void (*field_cb)(void *data, const char *field, size_t flen, const char *value, size_t vlen);

typedef struct ew_element ew_element;
typedef struct ew_parser ew_parser;

struct ew_element {
  const char *base;
  size_t len; 
  ew_element *next;  
}; 

int ew_element_init
  ( ew_element *element
  );


struct ew_parser { 

/* PUBLIC */
  void *data;

  /* allocates and initializes a new element */
  ew_element* (*new_element)();

  /* appends to ew_element linked list */
  void (*expand_element)(ew_element*, const char *base, size_t len);

  element_cb chunk_handler;

/* PRIVATE */
  int cs;
  size_t nread;

  size_t chunk_size;
  unsigned eating:1;

  /* element in progress stack 
   * grammar doesn't have more than 3 nested elements
   */
  ew_element *eip_stack[3]; 

  size_t mark;
  size_t field_start;
  size_t field_len;
  size_t query_start;
};

void ew_parser_init
  ( ew_parser *parser
  );

size_t chunked_parser_execute
  ( ew_parser *parser
  , const char *data
  , size_t len
  );

int ew_parser_has_error
  ( ew_parser *parser
  );

int ew_parser_is_finished
  ( ew_parser *parser
  );

#endif
