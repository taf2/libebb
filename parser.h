#ifndef ebb_parser_h
#define ebb_parser_h
#include <sys/types.h> 

typedef struct ebb_element ebb_element;
typedef struct ebb_parser ebb_parser;
typedef struct ebb_request ebb_request;
typedef void (*element_cb)(void *data, ebb_element *);

#define EBB_IDENTITY 0
#define EBB_CHUNKED  1

struct ebb_request {
  size_t content_length;
  int transfer_encoding;
  ebb_request *next;
  unsigned complete:1;

  void (*free) (ebb_request*);
};

struct ebb_element {
  const char *base;
  size_t len; 
  ebb_element *next;  

  void (*free) (ebb_element*);
}; 

struct ebb_parser {

/* PUBLIC */
  void *data;

  /* allocates a new element */
  ebb_element* (*new_element)();

  ebb_request* (*new_request)(void*);
  void (*request_complete)(void*);

  void (*chunk_handler)(void *data, const char *at, size_t length);
  void (*http_field)(void *data, ebb_element *field, ebb_element *value);
  element_cb request_method;
  element_cb request_uri;
  element_cb fragment;
  element_cb request_path;
  element_cb query_string;
  element_cb http_version;

/* PRIVATE */
  int cs;
  size_t nread;

  size_t chunk_size;
  unsigned eating:1;

  /* element in progress stack 
   * grammar doesn't have more than 3 nested elements
   */
  ebb_element *eip_stack[3]; 
  ebb_element *header_field_element;
  ebb_request *current_request;
  ebb_request *first_request;
};

int ebb_element_init
  ( ebb_element *element
  );

void ebb_parser_init
  ( ebb_parser *parser
  );

void ebb_request_init
  ( ebb_request *
  );

size_t chunked_parser_execute
  ( ebb_parser *parser
  , const char *data
  , size_t len
  );

int ebb_parser_has_error
  ( ebb_parser *parser
  );

int ebb_parser_is_finished
  ( ebb_parser *parser
  );

#endif
