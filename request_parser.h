#ifndef ebb_request_parser_h
#define ebb_request_parser_h

#include <sys/types.h> 

typedef struct ebb_request ebb_request;
typedef struct ebb_request_parser  ebb_request_parser;
typedef void (*ebb_header_cb)(ebb_request*, const char *at, size_t length, int header_index);
typedef void (*ebb_element_cb)(ebb_request*, const char *at, size_t length);

#define EBB_RAGEL_STACK_SIZE 10
#define EBB_MAX_MULTIPART_BOUNDARY_LEN 20

struct ebb_request {
  size_t content_length;             /* ro - 0 if unknown */
  enum { EBB_IDENTITY
       , EBB_CHUNKED
       } transfer_encoding;          /* ro */
  size_t body_read;                  /* ro */
  int eating_body;                   /* ro */
  int expect_continue;               /* ro */
  unsigned int version_major;        /* ro */
  unsigned int version_minor;        /* ro */
  int number_of_headers;             /* ro */
  struct ebb_connection *connection; /* ro */
  char multipart_boundary[EBB_MAX_MULTIPART_BOUNDARY_LEN]; /* ro */
  unsigned int multipart_boundary_len; /* ro */

  /* Public */
  void *data;
  void (*free)(ebb_request*);
};

struct ebb_request_parser {
  int cs;                           /* private */
  int stack[EBB_RAGEL_STACK_SIZE];  /* private */
  int top;                          /* private */
  size_t chunk_size;                /* private */
  unsigned eating:1;                /* private */
  struct ebb_connection *connection;/* private */
  ebb_request *current_request;     /* ro */
  const char *header_field_mark; 
  const char *header_value_mark; 
  const char *query_string_mark; 
  const char *request_path_mark; 
  const char *request_uri_mark; 
  const char *request_method_mark; 
  const char *fragment_mark; 

  /* Public */

  ebb_request* (*new_request)(void*);
  ebb_element_cb body_handler;

  void (*request_complete)(ebb_request *);
  ebb_header_cb header_field;
  ebb_header_cb header_value;
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

void ebb_request_init
  ( ebb_request *
  );

#define ebb_request_has_body(request) \
  (request->transfer_encoding == EBB_CHUNKED || request->content_length > 0 )

#endif
