
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
    printf("write_field!\n");
    assert(parser->header_field_element == NULL);  
    eip = eip_pop(parser);
    last = ebb_element_last(eip);
    last->len = p - last->base;
    parser->header_field_element = eip;
    assert(eip_empty(parser) && "eip_stack must be empty after header field");
  }

  action write_value {
    printf("write_value!\n");
    assert(parser->header_field_element != NULL);  

    eip = eip_pop(parser);
    last = ebb_element_last(eip);
    last->len = p - eip->base;  

    if(parser->http_field)
      parser->http_field( parser->data
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
    parser->current_request->content_length *= 10;
    parser->current_request->content_length += *p - '0';
  }

  action use_identity_encoding {
    printf("use identity encoding\n");
    parser->current_request->transfer_encoding = EBB_IDENTITY;
  }

  action use_chunked_encoding {
    printf("use chunked encoding\n");
    parser->current_request->transfer_encoding = EBB_CHUNKED;
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
    parser->current_request->version_major *= 10;
    parser->current_request->version_major += *p - '0';
  }

  action version_minor {
    parser->current_request->version_minor *= 10;
    parser->current_request->version_minor += *p - '0';
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
      parser->eating = 1;
      parser->chunk_handler(parser->data, p, REMAINING);
      parser->chunk_size -= REMAINING;
      fhold; 
      fbreak;
    } else {
      parser->chunk_handler(parser->data, p, parser->chunk_size);
      p += parser->chunk_size;
      parser->chunk_size = 0;
      parser->eating = 0;
      fhold; 
      fgoto chunk_end; 
    }
  }

  action end_chunked_body {
    printf("end chunked body\n");
    fgoto Request; 
  }

  action parse_body { 
    printf("got to parse body\n");
    if(!eip_empty(parser))
      printf("still on stack: '%s'\n", parser->eip_stack[0]->base);
    assert( eip_empty(parser) && "stack must be empty when at body");

    if(parser->current_request->transfer_encoding == EBB_CHUNKED) {
      fhold; 
      fgoto Chunked_Body;

    } else if(parser->current_request->content_length > 0) { 
      parser->chunk_size = parser->current_request->content_length;

      /* skip content-length bytes */
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
        fgoto Request; 
      }
    }
  }

  action start_req {
    if(parser->first_request) {
      for(request = parser->first_request; request->next; request = request->next) {;}
      request->next = parser->new_request(parser->data);
      request = request->next;
      request->next = NULL;
    } else {
      parser->first_request = parser->new_request(parser->data);
      parser->current_request = parser->first_request;
    }
  }

  action end_req {
    printf("end request\n");
    if(parser->request_complete)
      parser->request_complete(parser->data);
    parser->current_request->complete = TRUE;
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
  query = ( uchar | reserved )* >mark >{printf("mark query\n");} %query_string ;
  param = ( pchar | "/" )* ;
  params = ( param ( ";" param )* ) ;
  rel_path = ( path? (";" params)? ) ("?" query)?;
  absolute_path = ( "/"+ rel_path ) >mmark >{printf("mark abspath\n");} %request_path;
  Request_URI = ( "*" | absolute_uri | absolute_path ) >mark >{printf("mark uri\n");} %request_uri;
  Fragment = ( uchar | reserved )* >mark >{printf("mark fragment\n");} %fragment;
  Method = ( upper | digit | safe ){1,20} >mark >{printf("mark method\n");} %request_method;
  http_number = (digit+ $version_major "." digit+ $version_minor);
  HTTP_Version = ( "HTTP/" http_number );

  field_name = ( token -- ":" )+ %write_field;
  field_value = ((any - " ") any*)? >mark >{printf("mark value\n");} %write_value;

  head_sep = ":" " "**;
  message_header = field_name head_sep field_value :> CRLF;

  cl = "Content-Length"i %write_field  head_sep
       digit+ >mark >{printf("mark cl value\n");} $content_length %write_value;

  te = "Transfer-Encoding"i %write_field head_sep %use_identity_encoding 
       "identity"i >mark >{printf("mark identity\n");} %use_chunked_encoding %write_value;

  t =  "Trailer"i %write_field head_sep
        field_value %trailer;

  rest = (field_name head_sep field_value);

  header  = cl     @(headers,4)
          | te     @(headers,4)
          | t      @(headers,4)
          | rest   @(headers,1)
          ;

  Request_Line = ( Method " " Request_URI ("#" Fragment)? " " HTTP_Version CRLF ) ;
  RequestHeader = Request_Line (header >mark >{printf("mark headbeg\n");} :> CRLF)* :> CRLF;

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
  Chunked_Body := chunk* last_chunk trailing_headers CRLF @end_chunked_body zlen;

  Request = (RequestHeader @parse_body zlen) >start_req @end_req;
  
# sequence of requests (for keep-alive)
  main := Request+;
}%%

%% write data;

void ebb_parser_init
  ( ebb_parser *parser
  ) 
{
  int cs = 0;
  %% write init;
  parser->cs = cs;
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
  parser->http_field = NULL;
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

  assert(parser->new_element && "undefined callback");
  assert(parser->new_request && "undefined callback");

  p = buffer;
  pe = buffer+len;

  if(0 < parser->chunk_size && parser->eating) {
    size_t eat = MIN(len, parser->chunk_size);
    if(eat == parser->chunk_size) {
      parser->eating = FALSE;
    }
    parser->chunk_handler(parser->data, p, eat);
    p += eat;
    parser->chunk_size -= eat;
    //printf("eat: %d\n", eat);
  }

  /* each on the eip stack gets expanded */
  for(i = 0; parser->eip_stack[i] != NULL; i++) {
    last = ebb_element_last(parser->eip_stack[i]);
    last->next = parser->new_element();
    last->next->base = buffer;
  }

  %% write exec;

  parser->cs = cs;
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

void http_field_cb(void *data, ebb_element *field, ebb_element *value)
{
  ebb_element_printf(field, "field: %s\n");
  ebb_element_printf(value, "value: %s\n\n");
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
  parser.http_field = http_field_cb;
  parser.request_method = request_method_cb;
  parser.request_path = request_path_cb;
  parser.request_uri = request_uri_cb;
  parser.fragment = fragment_cb;
  parser.query_string = query_string_cb;
  parser.chunk_handler = chunk_handler;

  traversed = ebb_parser_execute(&parser, buf, strlen(buf));

  return ebb_parser_has_error(&parser);
}


int main() 
{


  assert(test_error("hello world"));
  assert(test_error("GET / HTP/1.1\r\n\r\n"));

  assert(!test_error("GET /hello/world HTTP/1.1\r\n\r\n"));
  assert(1 == num_requests);
  assert(0 == strcmp(requests[0].body, ""));
  assert(0 == strcmp(requests[0].fragment, ""));
  assert(0 == strcmp(requests[0].query_string, ""));
  assert(0 == strcmp(requests[0].request_method, "GET"));
  assert(0 == strcmp(requests[0].request_path, "/hello/world"));
  assert(1 == requests[0].request.version_major);
  assert(1 == requests[0].request.version_minor);

  assert(!test_error("GET /hello/world HTTP/1.1\r\nAccept: */*\r\n\r\n"));
  assert(1 == num_requests);
  assert(0 == strcmp(requests[0].body, ""));
  assert(0 == strcmp(requests[0].fragment, ""));
  assert(0 == strcmp(requests[0].query_string, ""));
  assert(0 == strcmp(requests[0].request_method, "GET"));
  assert(0 == strcmp(requests[0].request_path, "/hello/world"));
  assert(0 == strcmp(requests[0].request_uri, "/hello/world"));
  assert(1 == requests[0].request.version_major);
  assert(1 == requests[0].request.version_minor);

  // error if there is a body without content length
  assert(test_error("GET /hello/world HTTP/1.1\r\nAccept: */*\r\nHello\r\n"));

  // no error if there is a is body with content length
  assert(test_error("GET /hello/world HTTP/1.1\r\nAccept: */*\r\nContent-Length: 5\r\n\r\nHello"));
  assert(0 == strcmp(requests[0].body, "Hello"));

  printf("okay\n");
  return 0;
}

#endif

