
#include "parser.h"
#include <stdio.h>
#include <assert.h>

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
  printf("push! (stack size before: %d)\n", i);
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
  printf("pop! (stack size before: %d)\n", i);
  top = parser->eip_stack[i-1];
  parser->eip_stack[i-1] = NULL;
  return top;
}


%%{
  machine ebb_parser;

  action mark {
    printf("mark!\n");
    eip = parser->new_element();
    eip->base = p;
    eip_push(parser, eip);
  }

  action mmark {
    printf("mmark!\n");
    eip = parser->new_element();
    eip->base = p;
    eip_push(parser, eip);
  }

  action write_field { 
    printf("write_field!\n");
    assert(parser->header_field_element == NULL);  
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    parser->header_field_element = eip;
  }

  action write_value {
    printf("write_value!\n");
    assert(parser->header_field_element != NULL);  
    eip = eip_pop(parser);
    eip->len = p - eip->base;  

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

  action content_length {
    printf("content_length!\n");
    parser->current_request->content_length *= 10;
    parser->current_request->content_length += *p - '0';
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
    printf("request method\n");
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    if(parser->request_method)
      parser->request_method(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action request_uri { 
    printf("request uri\n");
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    if(parser->request_uri)
      parser->request_uri(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action fragment { 
    printf("fragment\n");
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    if(parser->fragment)
      parser->fragment(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action query_string { 
    printf("query  string\n");
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    if(parser->query_string)
      parser->query_string(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action http_version {	
    printf("http version\n");
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    if(parser->http_version)
      parser->http_version(parser->data, eip);
    if(eip->free)
      eip->free(eip);
  }

  action request_path {
    printf("request path\n");
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    if(parser->request_path)
      parser->request_path(parser->data, eip);
    if(eip->free)
      eip->free(eip);
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
    printf("new request\n");
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
  query = ( uchar | reserved )* >mark %query_string ;
  param = ( pchar | "/" )* ;
  params = ( param ( ";" param )* ) ;
  rel_path = ( path? (";" params)? ) ("?" query)?;
  absolute_path = ( "/"+ rel_path ) >mmark %request_path;
  Request_URI = ( "*" | absolute_uri | absolute_path ) >mark %request_uri;
  Fragment = ( uchar | reserved )* >mark %fragment;
  Method = ( upper | digit | safe ){1,20} >mark %request_method;
  http_number = ( digit+ "." digit+ ) ;
  HTTP_Version = ( "HTTP/" http_number ) >mark %http_version ;
  field_name = ( token -- ":" )+ >mark %write_field;
  field_value = any* >mark %write_value;
  message_header = field_name ":" " "* field_value :> CRLF;
  # Header values that are needed for parsing the message
  content_length = "Content-Length:"i " "* (digit+ >mark $content_length %write_value);
  transfer_encoding = "Transfer-Encoding:"i " "* 
                      ( "identity" 
                      | (field_value -- "identity") %use_chunked_encoding
                      );
  trailer = "Trailer:"i " "* (field_value %trailer);
  needed_header = (content_length | transfer_encoding | trailer) :> CRLF;
  unneeded_header = message_header -- needed_header;
  Request_Line = ( Method " " Request_URI ("#" Fragment)? " " HTTP_Version CRLF ) ;
  RequestHeader = Request_Line (needed_header | unneeded_header)* CRLF;

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
  parser->http_version = NULL;
}


/** exec **/
size_t ebb_parser_execute
  ( ebb_parser *parser
  , const char *buffer
  , size_t len
  )
{
  ebb_element *eip; 
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
    ebb_element *el;
    for(el = parser->eip_stack[i]; el->next; el = el->next) {;}
    el->next = parser->new_element();
    el = el->next;
    el->base = buffer;
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

int ebb_element_init
  ( ebb_element *element
  ) 
{
  element->base = NULL;
  element->len = 0;
  element->next = element;
  element->free = NULL;
}

void ebb_request_init
  ( ebb_request *request
  )
{
  request->content_length = 0;
  request->transfer_encoding = EBB_IDENTITY;
  request->complete = FALSE;
  request->next = NULL;
  request->free = NULL;
}

#ifdef UNITTEST
#include <stdlib.h>
#include <string.h>

static char body[500];
static ebb_parser parser;

ebb_element* new_element ()
{
  ebb_element *el = malloc(sizeof(ebb_element));
  ebb_element_init(el);
  return el;
}

ebb_request* new_request ()
{
  ebb_request *r = malloc(sizeof(ebb_request));
  ebb_request_init(r);
  return r;
}

void request_method(void *data, ebb_element *el)
{
  printf("got request method\n");
}

void request_path(void *data, ebb_element *el)
{
  printf("got request path\n");
}

void chunk_handler(void *data, const char *p, size_t len)
{
  //printf("chunk_handler: '%s'", body);
  strncat(body, p, len);
  //printf(" -> '%s'\n", body);
}

int test_error
  ( const char *buf
  )
{
  size_t traversed = 0;
  body[0] = 0;

  ebb_parser_init(&parser);

  parser.new_element = new_element;
  parser.new_request = new_request;
  parser.request_method = request_method;
  parser.request_path = request_path;
  parser.chunk_handler = chunk_handler;

  traversed = ebb_parser_execute(&parser, buf, strlen(buf));

  return ebb_parser_has_error(&parser);
}


int main() 
{


  assert(test_error("hello world"));
  //assert(test_error("GET / HTP/1.1\r\n\r\n"));
  assert(!test_error("GET /hello/world HTTP/1.1\r\n\r\n"));


  printf("okay\n");
  return 0;
}

#endif

