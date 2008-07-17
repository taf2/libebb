#ifndef ebb_request_parser_h
#define ebb_request_parser_h

#include <sys/types.h> 

typedef struct ebb_request_info ebb_request_info;
typedef struct ebb_element ebb_element;
typedef struct ebb_request_parser  ebb_request_parser;
typedef void (*ebb_element_cb)(ebb_request_info*, ebb_element *, void *data);

#define EBB_IDENTITY 0
#define EBB_CHUNKED  1

#define EBB_RAGEL_STACK_SIZE 10

struct ebb_request_info {
  size_t content_length;        /* ro - 0 if unknown */
  int transfer_encoding;        /* ro - EBB_IDENTITY or EBB_CHUNKED */
  size_t body_read;             /* ro */
  int eating_body;              /* ro */
  int expect_continue;          /* ro */
  unsigned int version_major;   /* ro */
  unsigned int version_minor;   /* ro */

  /* Public */
  void *data;
  void (*free)(ebb_request_info*);
};

struct ebb_element {
  const char *base;   /* ro */
  size_t len;         /* ro */
  ebb_element *next;  /* ro */

  /* Public */
  void (*free)(ebb_element*);
}; 

struct ebb_request_parser {
  int cs;                           /* private */
  int stack[EBB_RAGEL_STACK_SIZE];  /* private */
  int top;                          /* private */
  size_t chunk_size;                /* private */
  unsigned eating:1;                /* private */

  /* element in progress stack. 
   * grammar doesn't have more than 3 nested elements
   */
  ebb_element *eip_stack[3]; 

  ebb_element *header_field_element;  /* ro */
  ebb_request_info *current_request;  /* ro */

  /* Public */

  ebb_element* (*new_element)(void *);
  ebb_request_info* (*new_request_info)(void*);

  void (*request_complete)(ebb_request_info *, void*);
  void (*body_handler)(ebb_request_info *, const char *at, size_t length, void*);
  void (*header_handler)(ebb_request_info *, ebb_element *field, ebb_element *value, void *data);

  ebb_element_cb request_method;
  ebb_element_cb request_uri;
  ebb_element_cb fragment;
  ebb_element_cb request_path;
  ebb_element_cb query_string;

  void *data;
};

void ebb_request_parser_init
  ( ebb_request_parser *parser
  );

size_t ebb_request_parser_execute
  ( ebb_request_parser *parser
  , const char *data
  , size_t len
  );

int ebb_request_parser_has_error
  ( ebb_request_parser *parser
  );

int ebb_request_parser_is_finished
  ( ebb_request_parser *parser
  );

void ebb_request_info_init
  ( ebb_request_info *
  );

void ebb_element_init
  ( ebb_element *element
  );

ebb_element* ebb_element_last
  ( ebb_element *element
  );

size_t ebb_element_len
  ( ebb_element *element
  );

void ebb_element_strcpy
  ( ebb_element *element
  , char *dest
  );

void ebb_element_printf
  ( ebb_element *element
  , const char *format
  );

#endif
