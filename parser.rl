
#include "parser.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>

#ifndef TRUE
# define TRUE 1
# define FALSE 0
#endif
#ifndef MIN
# define MIN(a,b) (a < b ? a : b)
#endif
#define REMAINING (pe - p)
#define CURRENT (parser->current_request)
#define CONTENT_LENGTH (parser->current_request->content_length)

#define eip_empty(parser) (parser->eip_stack[0] == NULL)

static void eip_push
  ( ebb_parser *parser
  , ebb_element *element
  )
{
  int i = 0;
  /* NO BOUNDS CHECKING - LIVING ON THE EDGE! */
  for(i = 0; parser->eip_stack[i] != NULL; i++) {;}
  //printf("push! (stack size before: %d)\n", i);
  parser->eip_stack[i] = element;
}

static ebb_element* eip_pop
  ( ebb_parser *parser
  )
{
  int i;
  ebb_element *top = NULL;
  assert( ! eip_empty(parser) ); 
  /* NO BOUNDS CHECKING - LIVING ON THE EDGE! */
  for(i = 0; parser->eip_stack[i] != NULL; i++) {;}
  //printf("pop! (stack size before: %d)\n", i);
  top = parser->eip_stack[i-1];
  parser->eip_stack[i-1] = NULL;
  return top;
}


%%{
  machine ebb_parser;

  action mark {
    //printf("mark!\n");
    eip = parser->new_element();
    eip->base = p;
    eip_push(parser, eip);
  }

  action mmark {
    //printf("mmark!\n");
    eip = parser->new_element();
    eip->base = p;
    eip_push(parser, eip);
  }

  action write_field { 
    //printf("write_field!\n");
    assert(parser->header_field_element == NULL);  
    eip = eip_pop(parser);
    last = ebb_element_last(eip);
    last->len = p - last->base;
    parser->header_field_element = eip;
    assert(eip_empty(parser) && "eip_stack must be empty after header field");
  }

  action write_value {
    //printf("write_value!\n");
    assert(parser->header_field_element != NULL);  

    eip = eip_pop(parser);
    last = ebb_element_last(eip);
    last->len = p - eip->base;  

    if(parser->header_handler)
      parser->header_handler( parser->data
                            , parser->header_field_element
                            , eip
                            );
    if(parser->header_field_element->free)
      parser->header_field_element->free(parser->header_field_element);
    if(eip->free)
      eip->free(eip);
    eip = parser->header_field_element = NULL;
  }

  action request_uri { 
    //printf("request uri\n");
    eip = eip_pop(parser);
    last = ebb_element_last(eip);
    last->len = p - eip->base;  
    if(parser->request_uri)
      parser->request_uri(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action fragment { 
    //printf("fragment\n");
    eip = eip_pop(parser);
    last = ebb_element_last(eip);
    last->len = p - eip->base;  
    if(parser->fragment)
      parser->fragment(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action query_string { 
    //printf("query  string\n");
    eip = eip_pop(parser);
    last = ebb_element_last(eip);
    last->len = p - eip->base;  
    if(parser->query_string)
      parser->query_string(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action request_path {
    //printf("request path\n");
    eip = eip_pop(parser);
    last = ebb_element_last(eip);
    last->len = p - eip->base;  
    if(parser->request_path)
      parser->request_path(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action content_length {
    printf("content_length!\n");
    CURRENT->content_length *= 10;
    CURRENT->content_length += *p - '0';
  }

  action use_identity_encoding {
    printf("use identity encoding\n");
    CURRENT->transfer_encoding = EBB_IDENTITY;
  }

  action use_chunked_encoding {
    printf("use chunked encoding\n");
    CURRENT->transfer_encoding = EBB_CHUNKED;
  }

  action trailer {
    printf("trailer\n");
    /* not implemenetd yet. (do requests even have trailing headers?) */
  }


  action request_method { 
    //printf("request method\n");
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    if(parser->request_method)
      parser->request_method(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action version_major {
    CURRENT->version_major *= 10;
    CURRENT->version_major += *p - '0';
  }

  action version_minor {
    CURRENT->version_minor *= 10;
    CURRENT->version_minor += *p - '0';
  }

  action add_to_chunk_size {
    printf("add to chunk size\n");
    parser->chunk_size *= 16;
    /* XXX: this can be optimized slightly */
    if( 'A' <= *p && *p <= 'F') 
      parser->chunk_size += *p - 'A' + 10;
    else if( 'a' <= *p && *p <= 'f') 
      parser->chunk_size += *p - 'a' + 10;
    else if( '0' <= *p && *p <= '9') 
      parser->chunk_size += *p - '0';
    else  
      assert(0 && "bad hex char");
  }

  action skip_chunk_data {
    printf("skip chunk data\n");
    printf("chunk_size: %d\n", parser->chunk_size);
    if(parser->chunk_size > REMAINING) {
      parser->eating = TRUE;
      parser->chunk_handler(parser->data, p, REMAINING);
      parser->chunk_size -= REMAINING;
      fhold; 
      fbreak;
    } else {
      parser->chunk_handler(parser->data, p, parser->chunk_size);
      p += parser->chunk_size;
      parser->chunk_size = 0;
      parser->eating = FALSE;
      fhold; 
      fgoto chunk_end; 
    }
  }

  action end_chunked_body {
    printf("end chunked body\n");
    if(parser->request_complete)
      parser->request_complete(parser->data);
    fret; // goto Request; 
  }

  action start_req {
    if(parser->first_request) {
      for(request = parser->first_request; request->next; request = request->next) {;}
      request->next = parser->new_request(parser->data);
      request = request->next;
      request->next = NULL;
      CURRENT = request;
    } else {
      parser->first_request = parser->new_request(parser->data);
      CURRENT = parser->first_request;
    }
  }

#
##
###
#### HTTP/1.1 STATE MACHINE
###
##   RequestHeaders and character types are from
#    Zed Shaw's beautiful Mongrel parser.

  CRLF = "\r\n";

# character types
  CTL = (cntrl | 127);
  safe = ("$" | "-" | "_" | ".");
  extra = ("!" | "*" | "'" | "(" | ")" | ",");
  reserved = (";" | "/" | "?" | ":" | "@" | "&" | "=" | "+");
  unsafe = (CTL | " " | "\"" | "#" | "%" | "<" | ">");
  national = any -- (alpha | digit | reserved | extra | safe | unsafe);
  unreserved = (alpha | digit | safe | extra | national);
  escape = ("%" xdigit xdigit);
  uchar = (unreserved | escape);
  pchar = (uchar | ":" | "@" | "&" | "=" | "+");
  tspecials = ("(" | ")" | "<" | ">" | "@" | "," | ";" | ":" | "\\" | "\"" | "/" | "[" | "]" | "?" | "=" | "{" | "}" | " " | "\t");

# elements
  token = (ascii -- (CTL | tspecials));
#  qdtext = token -- "\""; 
#  quoted_pair = "\" ascii;
#  quoted_string = "\"" (qdtext | quoted_pair )* "\"";

#  headers
  scheme = ( alpha | digit | "+" | "-" | "." )* ;
  absolute_uri = (scheme ":" (uchar | reserved )*);
  path = ( pchar+ ( "/" pchar* )* ) ;
  query = ( uchar | reserved )* >mark %query_string ;
  param = ( pchar | "/" )* ;
  params = ( param ( ";" param )* ) ;
  rel_path = ( path? (";" params)? ) ("?" query)?;
  absolute_path = ( "/"+ rel_path ) >mmark %request_path;
  Request_URI = ( "*" | absolute_uri | absolute_path ) >mark %request_uri;
  Fragment = ( uchar | reserved )* >mark %fragment;
  Method = ( upper | digit | safe ){1,20} >mark %request_method;
  http_number = (digit+ $version_major "." digit+ $version_minor);
  HTTP_Version = ( "HTTP/" http_number );

  field_name = ( token -- ":" )+ %write_field;
  field_value = ((any - " ") any*)? >mark %write_value;

  head_sep = ":" " "**;
  message_header = field_name head_sep field_value :> CRLF;

  cl = "Content-Length"i %write_field  head_sep
       digit+ >mark $content_length %write_value;

  te = "Transfer-Encoding"i %write_field %use_chunked_encoding head_sep
       "identity"i >mark %use_identity_encoding %write_value;

  t =  "Trailer"i %write_field head_sep
        field_value %trailer;

  rest = (field_name head_sep field_value);

  header  = cl     @(headers,4)
          | te     @(headers,4)
          | t      @(headers,4)
          | rest   @(headers,1)
          ;

  Request_Line = ( Method " " Request_URI ("#" Fragment)? " " HTTP_Version CRLF ) ;
  RequestHeader = Request_Line (header >mark :> CRLF)* :> CRLF;

# chunked message
  trailing_headers = message_header*;
  #chunk_ext_val   = token | quoted_string;
  chunk_ext_val = token*;
  chunk_ext_name = token*;
  chunk_extension = ( ";" " "* chunk_ext_name ("=" chunk_ext_val)? )*;
  last_chunk = "0"+ chunk_extension CRLF;
  chunk_size = (xdigit* [1-9a-fA-F] xdigit*) $add_to_chunk_size;
  chunk_end  = CRLF;
  chunk_body = any >skip_chunk_data;
  chunk_begin = chunk_size chunk_extension CRLF;
  chunk = chunk_begin chunk_body chunk_end;
  ChunkedBody := chunk* last_chunk trailing_headers CRLF @end_chunked_body;

  Request = RequestHeader @{
    if(CURRENT->transfer_encoding == EBB_CHUNKED) {
      printf("\nchunked!\n\n");
      fcall ChunkedBody;
    } else {
      /*
       * EAT BODY
       * this is very ugly. sorry.
       *
       */
      if( CURRENT->content_length == 0) {

        if( parser->request_complete )
          parser->request_complete(parser->data);


      } else if( CURRENT->content_length < REMAINING ) {
        /* 
         * 
         * FINISH EATING THE BODY. there is still more 
         * on the buffer - so we just let it continue
         * parsing after we're done
         *
         */
        p += 1;
        if( parser->chunk_handler )
          parser->chunk_handler(parser->data, p, CURRENT->content_length); 

        p += CURRENT->content_length;
        CURRENT->body_read = CURRENT->content_length;

        assert(0 <= REMAINING);

        if( parser->request_complete )
          parser->request_complete(parser->data);

        fhold;

      } else {
        /* 
         * The body is larger than the buffer
         * EAT REST OF BUFFER
         * there is still more to read though. this will  
         * be handled on the next invokion of ebb_parser_execute
         * right before we enter the state machine. 
         *
         */
        p += 1;
        size_t eat = REMAINING;

        if( parser->chunk_handler )
          parser->chunk_handler(parser->data, p, eat); 

        p += eat;
        CURRENT->body_read += eat;

        assert(CURRENT->body_read < CURRENT->content_length);
        assert(REMAINING == 0);
        
        fhold; fbreak;  
      }
    }
  };

  
# sequence of requests (for keep-alive)
  main := (Request >start_req)+;
}%%

%% write data;

#define COPYSTACK(dest, src)  for(i = 0; i < PARSER_STACK_SIZE; i++) { dest[i] = src[i]; }

void ebb_parser_init
  ( ebb_parser *parser
  ) 
{
  int i;

  int cs = 0;
  int top = 0;
  int stack[PARSER_STACK_SIZE];
  %% write init;
  parser->cs = cs;
  parser->top = top;
  COPYSTACK(parser->stack, stack);

  parser->chunk_size = 0;
  parser->eating = 0;
  

  parser->eip_stack[0] = NULL;
  parser->current_request = NULL;
  parser->first_request = NULL;
  parser->header_field_element = NULL;

  parser->nread = 0;

  parser->new_element = NULL;
  parser->new_request = NULL;
  parser->request_complete = NULL;
  parser->chunk_handler = NULL;
  parser->header_handler = NULL;
  parser->request_method = NULL;
  parser->request_uri = NULL;
  parser->fragment = NULL;
  parser->request_path = NULL;
  parser->query_string = NULL;
}


/** exec **/
size_t ebb_parser_execute
  ( ebb_parser *parser
  , const char *buffer
  , size_t len
  )
{
  ebb_element *eip, *last; 
  ebb_request *request; 
  const char *p, *pe;
  int i, cs = parser->cs;

  int top = parser->top;
  int stack[PARSER_STACK_SIZE];
  COPYSTACK(stack, parser->stack);

  assert(parser->new_element && "undefined callback");
  assert(parser->new_request && "undefined callback");

  p = buffer;
  pe = buffer+len;

  if(0 < parser->chunk_size && parser->eating) {
    /*
     *
     * eat chunked body
     * 
     */
    printf("eat chunk body (before parse)\n");
    size_t eat = MIN(len, parser->chunk_size);
    if(eat == parser->chunk_size) {
      parser->eating = FALSE;
    }
    parser->chunk_handler(parser->data, p, eat);
    p += eat;
    parser->chunk_size -= eat;
    //printf("eat: %d\n", eat);
  } else if( parser->current_request && 
             CURRENT->content_length > 0 && 
             CURRENT->body_read > 0) {
    /*
     *
     * eat normal body
     * 
     */
    printf("eat normal body (before parse)\n");
    size_t eat = MIN(len, CURRENT->content_length - CURRENT->body_read);

    parser->chunk_handler(parser->data, p, eat);
    p += eat;
    CURRENT->body_read += eat;

    if(CURRENT->body_read == CURRENT->content_length)
      if(parser->request_complete)
        parser->request_complete(parser->data);

  }



  /* each on the eip stack gets expanded */
  for(i = 0; parser->eip_stack[i] != NULL; i++) {
    last = ebb_element_last(parser->eip_stack[i]);
    last->next = parser->new_element();
    last->next->base = buffer;
  }

  %% write exec;

  parser->cs = cs;
  parser->top = top;
  COPYSTACK(parser->stack, stack);

  parser->nread += p - buffer;

  /* each on the eip stack gets len */
  for(i = 0; parser->eip_stack[i] != NULL; i++) {
    parser->eip_stack[i]->len = pe - parser->eip_stack[i]->base;
    assert( parser->eip_stack[i]->base < pe && "mark is after buffer end");
  }

  assert(p <= pe && "buffer overflow after parsing execute");

  return(p - buffer);
}

int ebb_parser_has_error
  ( ebb_parser *parser
  ) 
{
  return parser->cs == ebb_parser_error;
}

int ebb_parser_is_finished
  ( ebb_parser *parser
  ) 
{
  return parser->cs == ebb_parser_first_final;
}

void ebb_request_init
  ( ebb_request *request
  )
{
  request->content_length = 0;
  request->version_major = 0;
  request->version_minor = 0;
  request->transfer_encoding = EBB_IDENTITY;
  request->complete = FALSE;
  request->next = NULL;
  request->free = NULL;
}

int ebb_element_init
  ( ebb_element *element
  ) 
{
  element->base = NULL;
  element->len = 0;
  element->next = NULL;
  element->free = NULL;
}

ebb_element* ebb_element_last
  ( ebb_element *element
  )
{
  for( ; element->next; element = element->next) {;}
  return element;
}

size_t ebb_element_len
  ( ebb_element *element
  )
{
  size_t len; 
  for(len = 0; element; element = element->next)
    len += element->len;
  return len;
}

void ebb_element_strcpy
  ( ebb_element *element
  , char *dest
  )
{
  dest[0] = '\0';
  for( ; element; element = element->next) 
    strncat(dest, element->base, element->len);
}

void ebb_element_printf
  ( ebb_element *element
  , const char *format
  )
{
  char str[1000];
  ebb_element_strcpy(element, str);
  printf(format, str);
}

#ifdef UNITTEST
#include <stdlib.h>

static ebb_parser parser;
struct request_data {
  char request_method[500];
  char request_path[500];
  char request_uri[500];
  char fragment[500];
  char query_string[500];
  char body[500];
  int num_headers;
  char* header_fields[500];
  char* header_values[500];
  ebb_request request;
};
static struct request_data requests[5];
static int num_requests;

ebb_element* new_element ()
{
  ebb_element *el = malloc(sizeof(ebb_element));
  ebb_element_init(el);
  return el;
}

ebb_request* new_request ()
{
  requests[num_requests].num_headers = 0;
  requests[num_requests].body[0] = 0;
  ebb_request *r = &requests[num_requests].request ;
  ebb_request_init(r);
  printf("new request %d\n", num_requests);
  return r;
}

void request_complete()
{
  printf("request complete\n");
  num_requests++;
}

void request_method_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].request_method);
}

void request_path_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].request_path);
}

void request_uri_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].request_uri);
}

void fragment_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].fragment);
}

void header_handler(void *data, ebb_element *field, ebb_element *value)
{
  char *field_s, *value_s;

  field_s = malloc( ebb_element_len(field) );
  ebb_element_strcpy( field, field_s);

  value_s = malloc( ebb_element_len(value) );
  ebb_element_strcpy( value,  value_s);

  int nh = requests[num_requests].num_headers;

  requests[num_requests].header_fields[nh] = field_s;
  requests[num_requests].header_values[nh] = value_s;

  requests[num_requests].num_headers += 1;

  printf("header %s: %s\n", field_s, value_s);
}


void query_string_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].query_string);
}


void chunk_handler(void *data, const char *p, size_t len)
{
  strncat(requests[num_requests].body, p, len);
  printf("chunk_handler: '%s'\n", requests[num_requests].body);
}

int test_error
  ( const char *buf
  )
{
  size_t traversed = 0;
  num_requests = 0;

  ebb_parser_init(&parser);

  parser.new_element = new_element;
  parser.new_request = new_request;
  parser.request_complete = request_complete;
  parser.header_handler = header_handler;
  parser.request_method = request_method_cb;
  parser.request_path = request_path_cb;
  parser.request_uri = request_uri_cb;
  parser.fragment = fragment_cb;
  parser.query_string = query_string_cb;
  parser.chunk_handler = chunk_handler;

  traversed = ebb_parser_execute(&parser, buf, strlen(buf));

  return ebb_parser_has_error(&parser);
}

int test_multiple
  ( const char *buf1
  , const char *buf2
  , const char *buf3
  )
{
  char total[80*1024] = "\0";

  strcat(total, buf1); 
  strcat(total, buf2); 
  strcat(total, buf3); 

  size_t traversed = 0;
  num_requests = 0;

  ebb_parser_init(&parser);

  parser.new_element = new_element;
  parser.new_request = new_request;
  parser.request_complete = request_complete;
  parser.header_handler = header_handler;
  parser.request_method = request_method_cb;
  parser.request_path = request_path_cb;
  parser.request_uri = request_uri_cb;
  parser.fragment = fragment_cb;
  parser.query_string = query_string_cb;
  parser.chunk_handler = chunk_handler;

  traversed = ebb_parser_execute(&parser, total, strlen(total));


  if( ebb_parser_has_error(&parser) )
    return -1;
  if(! ebb_parser_is_finished(&parser) )
    return -2;

  return traversed;
}

#define assert_req_str_eql(num, FIELD, expected)  \
  assert(0 == strcmp(requests[num].FIELD, expected))

int main() 
{
  // get - no headers - no body
  const char *req1 = "GET /req1/world HTTP/1.1\r\n\r\n"; 

  // get - one header - no body
  const char *req2 = "GET /req2 HTTP/1.1\r\nAccept: */*\r\n\r\n"; 

  // post - one header - no body
  const char *req3 = "POST /req3 HTTP/1.1\r\nAccept: */*\r\n\r\n"; 

  // get - no headers - body "HELLO"
  const char *req4 = "GET /req4 HTTP/1.1\r\nContent-Length: 5\r\n\r\nHELLO";

  // post - one header - body "World"
  const char *req5 = "POST /req5 HTTP/1.1\r\nAccept: */*\r\nContent-Length: 5\r\n\r\nWorld";

  // post - no headers - chunked body "all your base are belong to us"
  const char *req6 = "POST /req6 HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n1e\r\nall your base are belong to us\r\n0\r\n\r\n";

  // no content-length
  const char *bad_req1 = "GET /bad_req1/world HTTP/1.1\r\nAccept: */*\r\nHELLO\r\n";

  assert(test_error("hello world"));
  assert(test_error("GET / HTP/1.1\r\n\r\n"));

  assert(!test_error(req1));
  assert(1 == num_requests);
  assert_req_str_eql(0, body, "");
  assert_req_str_eql(0, fragment, "");
  assert_req_str_eql(0, query_string, "");
  assert_req_str_eql(0, request_method, "GET");
  assert_req_str_eql(0, request_path, "/req1/world");
  assert(1 == requests[0].request.version_major);
  assert(1 == requests[0].request.version_minor);
  assert(0 == requests[0].num_headers);

  assert(!test_error(req2));
  assert(1 == num_requests);
  assert_req_str_eql(0, body, "");
  assert_req_str_eql(0, fragment, "");
  assert_req_str_eql(0, query_string, "");
  assert_req_str_eql(0, request_method, "GET");
  assert_req_str_eql(0, request_path, "/req2");
  assert_req_str_eql(0, request_uri, "/req2");
  assert(1 == requests[0].request.version_major);
  assert(1 == requests[0].request.version_minor);
  assert(1 == requests[0].num_headers);
  assert_req_str_eql(0, header_fields[0], "Accept");
  assert_req_str_eql(0, header_values[0], "*/*");

  assert(!test_error(req3));
  assert_req_str_eql(0, body, "");
  assert(1 == requests[0].num_headers);
  assert_req_str_eql(0, header_fields[0], "Accept");
  assert_req_str_eql(0, header_values[0], "*/*");

  // error if there is a body without content length
  assert(test_error(bad_req1));

  // no error if there is a is body with content length
  assert(!test_error(req4));
  assert_req_str_eql(0, body, "HELLO");
  assert(1 == num_requests);
  assert(1 == requests[0].num_headers);
  assert_req_str_eql(0, header_fields[0], "Content-Length");
  assert_req_str_eql(0, header_values[0], "5");

  assert(!test_error(req5));
  assert_req_str_eql(0, body, "World");
  assert(2 == requests[0].num_headers);
  assert_req_str_eql(0, header_fields[0], "Accept");
  assert_req_str_eql(0, header_values[0], "*/*");
  assert_req_str_eql(0, header_fields[1], "Content-Length");
  assert_req_str_eql(0, header_values[1], "5");

  // chunked body
  assert(!test_error(req6));
  assert_req_str_eql(0, fragment, "");
  assert_req_str_eql(0, query_string, "");
  assert_req_str_eql(0, request_method, "POST");
  assert_req_str_eql(0, request_path, "/req6");
  assert_req_str_eql(0, request_uri, "/req6");
  assert_req_str_eql(0, body, "all your base are belong to us");
  assert(1 == requests[0].num_headers);
  assert_req_str_eql(0, header_fields[0], "Transfer-Encoding");
  assert_req_str_eql(0, header_values[0], "chunked");

  // three requests - no bodies
  assert(0 < test_multiple(req1, req2, req3));
  assert(3 == num_requests);

  // three requests - one body
  assert(0 < test_multiple(req1, req4, req3));
  assert(3 == num_requests);
  assert_req_str_eql(0, body, "");
  assert_req_str_eql(1, body, "HELLO");
  assert_req_str_eql(2, body, "");


  // three requests with bodies -- last is chunked
  assert(0 < test_multiple(req4, req5, req6));
  assert_req_str_eql(0, body, "HELLO");
  assert_req_str_eql(1, body, "World");
  assert_req_str_eql(2, body, "all your base are belong to us");
  assert(3 == num_requests);

  // three chunked requests
  assert(0 < test_multiple(req6, req6, req6));
  assert_req_str_eql(0, body, "all your base are belong to us");
  assert_req_str_eql(1, body, "all your base are belong to us");
  assert_req_str_eql(2, body, "all your base are belong to us");
  assert(3 == num_requests);

  printf("okay\n");
  return 0;
}

#endif

