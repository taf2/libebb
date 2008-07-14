
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
  ( ew_parser *parser
  , ew_element *element
  )
{
  int i = 0;
  /* NO BOUNDS CHECKING - LIVING ON THE EDGE! */
  for(i = 0; parser->eip_stack[i] != NULL; i++) {;}
  parser->eip_stack[i] = element;
}

static ew_element* eip_pop
  ( ew_parser *parser
  )
{
  int i = 0;
  ew_element *top;
  /* NO BOUNDS CHECKING - LIVING ON THE EDGE! */
  for(i = 0; parser->eip_stack[i] != NULL; i++) {;}
  top = parser->eip_stack[i];
  parser->eip_stack[i] = NULL;
  return top;
}


%%{
  machine ew_parser;

  action mark {
    eip = parser->new_element();
    eip->base = p;
    eip_push(parser, eip);
  }

  action write_field { 
    assert(parser->header_field_element == NULL);  
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    parser->header_field_element = eip;
  }

  action write_value {
    assert(parser->header_field_element != NULL);  
    eip = eip_pop(parser);
    eip->len = p - eip->base;  

    /* TODO: extract headers that we need for parsing
     * Content-Length, Transfer-Encoding, Trailer 
     */
    parser->http_field( parser->data
                      , parser->header_field_element
                      , eip
                      );

    eip = parser->header_field_element = NULL;
  }

  action content_length {
    parser->current_request->content_length *= 10;
    parser->current_request->content_length += *p - '0';
  }

  action use_chunked_encoding {
    parser->current_request->transfer_encoding = EW_CHUNKED;
  }

  action trailer {
    /* not implemenetd yet. (do requests even have trailing headers?) */
  }


  action request_method { 
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    parser->request_method(parser->data, eip);
  }

  action request_uri { 
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    parser->request_uri(parser->data, eip);
  }

  action fragment { 
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    parser->fragment(parser->data, eip);
  }

  action query_string { 
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    parser->query_string(parser->data, eip);
  }

  action http_version {	
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    parser->http_version(parser->data, eip);
  }

  action request_path {
    eip = eip_pop(parser);
    eip->len = p - eip->base;  
    parser->request_path(parser->data, eip);
  }

  action add_to_chunk_size {
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
    //printf("chunk_size: %d\n", parser->chunk_size);
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
    fgoto Request; 
  }

  action parse_body { 
    assert( eip_empty(parser) && "stack must be empty when at body");

    if(parser->current_request->transfer_encoding == EW_CHUNKED) {
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
    for(request = parser->requests; request->next; request = request->next) {;}
    request->next = parser->new_request(parser->data);
    request = request->next;
    request->next = NULL;
    parser->current_request = request;
  }

  action end_req {
    parser->request_complete(parser->data);
    parser->current_request->complete = TRUE;
  }

#
##
###
#### HTTP/1.1 STATE MACHINE
###
##
#

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
  rel_path = ( path? %request_path (";" params)? ) ("?" query)?;
  absolute_path = ( "/"+ rel_path );
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

void ew_parser_init
  ( ew_parser *parser
  ) 
{
  int cs = 0;
  %% write init;
  parser->cs = cs;
  parser->chunk_size = 0;
  parser->eating = 0;

  parser->eip_stack[0] = NULL;
  parser->current_request = NULL;
  parser->header_field_element = NULL;

  parser->nread = 0;

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
size_t ew_parser_execute
  ( ew_parser *parser
  , const char *buffer
  , size_t len
  )
{
  ew_element *eip; 
  ew_request *request; 
  const char *p, *pe;
  int i, cs = parser->cs;

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
    parser->eip_stack[i] = parser->expand_element(parser->eip_stack[i]);
    /* circular linked list? */
    parser->eip_stack[i]->base = buffer;
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

int ew_parser_has_error
  ( ew_parser *parser
  ) 
{
  return parser->cs == ew_parser_error;
}

int ew_parser_is_finished
  ( ew_parser *parser
  ) 
{
  return parser->cs == ew_parser_first_final;
}

int ew_element_init
  ( ew_element *element
  ) 
{
  element->base = NULL;
  element->len = 0;
  element->next = element;
}

void ew_request_init
  ( ew_request *request
  )
{
  request->content_length = 0;
  request->transfer_encoding = EW_IDENTITY;
  request->next = NULL;
  request->complete = FALSE;
}

#ifdef UNITTEST


int main() 
{
  printf("okay\n");
  return 0;
}

#endif

