#ifndef ew_h
#define ew_h
#include <sys/types.h> 

typedef struct ew_element ew_element;
typedef struct ew_parser ew_parser;
typedef struct ew_request ew_request;
typedef void (*element_cb)(void *data, ew_element *);


struct ew_element {
  const char *base;
  size_t len; 
  ew_element *next;  
}; 


struct ew_parser {

/* PUBLIC */
  void *data;

  /* allocates and initializes a new element */
  ew_element* (*new_element)();

  /* appends to ew_element linked list 
   * returns new element
   */
  ew_element* (*expand_element)(ew_element*, const char *base, size_t len);

  void (*chunk_handler)(void *data, const char *at, size_t length);
  void (*http_field)(void *data, ew_element *field, ew_element *value);
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
  ew_element *eip_stack[3]; 

  ew_request *current_request;
};

#define EW_TRANSFER_ENCODING_IDENTITY 0
#define EW_TRANSFER_ENCODING_CHUNKED  1

struct ew_request {
  size_t content_length;
  int transfer_encoding;
  ew_request *next;
};

int ew_element_init
  ( ew_element *element
  );

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
