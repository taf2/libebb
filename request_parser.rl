#include "request_parser.h"

#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h> /* for the default methods */

#define TRUE 1
#define FALSE 0
#define MIN(a,b) (a < b ? a : b)

#define REMAINING (pe - p)
#define CURRENT (parser->current_request)
#define CONTENT_LENGTH (parser->current_request->content_length)

#define LEN(FROM) (p - parser->FROM##_mark)
#define CALLBACK(FOR)                         \
  if(parser->FOR##_mark && parser->FOR) {     \
    parser->FOR( CURRENT                      \
               , parser->FOR##_mark           \
               , p - parser->FOR##_mark       \
               );                             \
 }
#define HEADER_CALLBACK(FOR)                  \
  if(parser->FOR##_mark && parser->FOR) {     \
    parser->FOR( CURRENT                      \
               , parser->FOR##_mark           \
               , p - parser->FOR##_mark       \
               , CURRENT->number_of_headers   \
               );                             \
 }

%%{
  machine ebb_request_parser;

  action mark_header_field   { parser->header_field_mark   = p; }
  action mark_header_value   { parser->header_value_mark   = p; }
  action mark_fragment       { parser->fragment_mark       = p; }
  action mark_query_string   { parser->query_string_mark   = p; }
  action mark_request_method { parser->request_method_mark = p; }
  action mark_request_path   { parser->request_path_mark   = p; }
  action mark_request_uri    { parser->request_uri_mark    = p; }

  action write_field { 
    //printf("write_field!\n");
    HEADER_CALLBACK(header_field);
    parser->header_field_mark = NULL;
  }

  action write_value {
    //printf("write_value!\n");
    HEADER_CALLBACK(header_value);
    parser->header_value_mark = NULL;
  }

  action end_header {
    CURRENT->number_of_headers++;
  }

  action request_uri { 
    //printf("request uri\n");
    CALLBACK(request_uri);
    parser->request_uri_mark = NULL;
  }

  action fragment { 
    //printf("fragment\n");
    CALLBACK(fragment);
    parser->fragment_mark = NULL;
  }

  action query_string { 
    //printf("query  string\n");
    CALLBACK(query_string);
    parser->query_string_mark = NULL;
  }

  action request_path {
    //printf("request path\n");
    CALLBACK(request_path);
    parser->request_path_mark = NULL;
  }

  action request_method { 
    //printf("request method\n");
    CALLBACK(request_method);
    parser->request_method_mark = NULL;
  }

  action content_length {
    //printf("content_length!\n");
    CURRENT->content_length *= 10;
    CURRENT->content_length += *p - '0';
  }

  action use_identity_encoding {
    //printf("use identity encoding\n");
    CURRENT->transfer_encoding = EBB_IDENTITY;
  }

  action use_chunked_encoding {
    //printf("use chunked encoding\n");
    CURRENT->transfer_encoding = EBB_CHUNKED;
  }

  action multipart_boundary {
    if(CURRENT->multipart_boundary_len == EBB_MAX_MULTIPART_BOUNDARY_LEN) {
      cs = -1;
      fbreak;
    }
    CURRENT->multipart_boundary[CURRENT->multipart_boundary_len++] = *p;
  } 

  action expect_continue {
    CURRENT->expect_continue = TRUE;
  }

  action trailer {
    //printf("trailer\n");
    /* not implemenetd yet. (do requests even have trailing headers?) */
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
    //printf("add to chunk size\n");
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
    //printf("skip chunk data\n");
    //printf("chunk_size: %d\n", parser->chunk_size);
    if(parser->chunk_size > REMAINING) {
      parser->eating = TRUE;
      parser->body_handler(CURRENT, p, REMAINING);
      parser->chunk_size -= REMAINING;
      fhold; 
      fbreak;
    } else {
      parser->body_handler(CURRENT, p, parser->chunk_size);
      p += parser->chunk_size;
      parser->chunk_size = 0;
      parser->eating = FALSE;
      fhold; 
      fgoto chunk_end; 
    }
  }

  action end_chunked_body {
    //printf("end chunked body\n");
    if(parser->request_complete)
      parser->request_complete(CURRENT);
    fret; // goto Request; 
  }

  action start_req {
    if(CURRENT && CURRENT->free)
      CURRENT->free(CURRENT);
    CURRENT = parser->new_request(parser->data);
    CURRENT->connection = parser->connection;
  }

  action body_logic {
    if(CURRENT->transfer_encoding == EBB_CHUNKED) {
      fcall ChunkedBody;
    } else {
      /*
       * EAT BODY
       * this is very ugly. sorry.
       *
       */
      if( CURRENT->content_length == 0) {

        if( parser->request_complete )
          parser->request_complete(CURRENT);


      } else if( CURRENT->content_length < REMAINING ) {
        /* 
         * 
         * FINISH EATING THE BODY. there is still more 
         * on the buffer - so we just let it continue
         * parsing after we're done
         *
         */
        p += 1;
        if( parser->body_handler )
          parser->body_handler(CURRENT, p, CURRENT->content_length); 

        p += CURRENT->content_length;
        CURRENT->body_read = CURRENT->content_length;

        assert(0 <= REMAINING);

        if( parser->request_complete )
          parser->request_complete(CURRENT);

        fhold;

      } else {
        /* 
         * The body is larger than the buffer
         * EAT REST OF BUFFER
         * there is still more to read though. this will  
         * be handled on the next invokion of ebb_request_parser_execute
         * right before we enter the state machine. 
         *
         */
        p += 1;
        size_t eat = REMAINING;

        if( parser->body_handler && eat > 0)
          parser->body_handler(CURRENT, p, eat); 

        p += eat;
        CURRENT->body_read += eat;
        CURRENT->eating_body = TRUE;
        //printf("eating body!\n");

        assert(CURRENT->body_read < CURRENT->content_length);
        assert(REMAINING == 0);
        
        fhold; fbreak;  
      }
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
  quote = "\"";
#  qdtext = token -- "\""; 
#  quoted_pair = "\" ascii;
#  quoted_string = "\"" (qdtext | quoted_pair )* "\"";

#  headers

  Method = ( upper | digit | safe ){1,20} >mark_request_method %request_method;

  HTTP_Version = "HTTP/" digit+ $version_major "." digit+ $version_minor;

  scheme = ( alpha | digit | "+" | "-" | "." )* ;
  absolute_uri = (scheme ":" (uchar | reserved )*);
  path = ( pchar+ ( "/" pchar* )* ) ;
  query = ( uchar | reserved )* >mark_query_string %query_string ;
  param = ( pchar | "/" )* ;
  params = ( param ( ";" param )* ) ;
  rel_path = ( path? (";" params)? ) ;
  absolute_path = ( "/"+ rel_path ) >mark_request_path %request_path ("?" query)?;
  Request_URI = ( "*" | absolute_uri | absolute_path ) >mark_request_uri %request_uri;
  Fragment = ( uchar | reserved )* >mark_fragment %fragment;

  field_name = ( token -- ":" )+;
  Field_Name = field_name >mark_header_field %write_field;

  field_value = ((any - " ") any*)?;
  Field_Value = field_value >mark_header_value %write_value;

  hsep = ":" " "*;
  header = (field_name hsep field_value) :> CRLF;
  Header = ( ("Content-Length"i hsep digit+ $content_length)
           | ("Content-Type"i hsep 
              "multipart/form-data" any* 
              "boundary=" quote token+ $multipart_boundary quote
             )
           | ("Transfer-Encoding"i %use_chunked_encoding hsep "identity" %use_identity_encoding)
           | ("Expect"i hsep "100-continue"i %expect_continue)
           | ("Trailer"i hsep field_value %trailer)
           | (Field_Name hsep Field_Value)
           ) :> CRLF;

  Request_Line = ( Method " " Request_URI ("#" Fragment)? " " HTTP_Version CRLF ) ;
  RequestHeader = Request_Line (Header %end_header)* :> CRLF;

# chunked message
  trailing_headers = header*;
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

  Request = RequestHeader >start_req @body_logic;

  main := Request+; # sequence of requests (for keep-alive)
}%%

%% write data;

#define COPYSTACK(dest, src)  for(i = 0; i < EBB_RAGEL_STACK_SIZE; i++) { dest[i] = src[i]; }

static ebb_request* default_new_request
  ( void *data
  )
{
  ebb_request *request = malloc(sizeof(ebb_request));
  ebb_request_init(request);
  request->free = (void (*)(ebb_request*))free;
  return request; 
}

void ebb_request_parser_init
  ( ebb_request_parser *parser
  ) 
{
  int i;

  int cs = 0;
  int top = 0;
  int stack[EBB_RAGEL_STACK_SIZE];
  %% write init;
  parser->cs = cs;
  parser->top = top;
  COPYSTACK(parser->stack, stack);

  parser->chunk_size = 0;
  parser->eating = 0;
  
  parser->current_request = NULL;

  parser->header_field_mark = parser->header_value_mark   = 
  parser->query_string_mark = parser->request_path_mark   = 
  parser->request_uri_mark  = parser->request_method_mark = 
  parser->fragment_mark     = NULL;

  parser->new_request = default_new_request;

  parser->request_complete = NULL;
  parser->body_handler = NULL;
  parser->header_field = NULL;
  parser->header_value = NULL;
  parser->request_method = NULL;
  parser->request_uri = NULL;
  parser->fragment = NULL;
  parser->request_path = NULL;
  parser->query_string = NULL;
}


/** exec **/
size_t ebb_request_parser_execute
  ( ebb_request_parser *parser
  , const char *buffer
  , size_t len
  )
{
  const char *p, *pe;
  int i, cs = parser->cs;

  int top = parser->top;
  int stack[EBB_RAGEL_STACK_SIZE];
  COPYSTACK(stack, parser->stack);

  assert(parser->new_request && "undefined callback");

  p = buffer;
  pe = buffer+len;

  if(0 < parser->chunk_size && parser->eating) {
    /*
     *
     * eat chunked body
     * 
     */
    //printf("eat chunk body (before parse)\n");
    size_t eat = MIN(len, parser->chunk_size);
    if(eat == parser->chunk_size) {
      parser->eating = FALSE;
    }
    parser->body_handler(CURRENT, p, eat);
    p += eat;
    parser->chunk_size -= eat;
    //printf("eat: %d\n", eat);
  } else if( parser->current_request && CURRENT->eating_body ) {
    /*
     *
     * eat normal body
     * 
     */
    //printf("eat normal body (before parse)\n");
    size_t eat = MIN(len, CURRENT->content_length - CURRENT->body_read);

    parser->body_handler(CURRENT, p, eat);
    p += eat;
    CURRENT->body_read += eat;

    if(CURRENT->body_read == CURRENT->content_length) {
      if(parser->request_complete)
        parser->request_complete(CURRENT);
      CURRENT->eating_body = FALSE;
    }
  }

  if(parser->header_field_mark)   parser->header_field_mark   = buffer;
  if(parser->header_value_mark)   parser->header_value_mark   = buffer;
  if(parser->fragment_mark)       parser->fragment_mark       = buffer;
  if(parser->query_string_mark)   parser->query_string_mark   = buffer;
  if(parser->request_method_mark) parser->request_method_mark = buffer;
  if(parser->request_path_mark)   parser->request_path_mark   = buffer;
  if(parser->request_uri_mark)    parser->request_uri_mark    = buffer;

  %% write exec;

  parser->cs = cs;
  parser->top = top;
  COPYSTACK(parser->stack, stack);

  HEADER_CALLBACK(header_field);
  HEADER_CALLBACK(header_value);
  CALLBACK(fragment);
  CALLBACK(query_string);
  CALLBACK(request_method);
  CALLBACK(request_path);
  CALLBACK(request_uri);

  assert(p <= pe && "buffer overflow after parsing execute");

  return(p - buffer);
}

int ebb_request_parser_has_error
  ( ebb_request_parser *parser
  ) 
{
  return parser->cs == ebb_request_parser_error;
}

int ebb_request_parser_is_finished
  ( ebb_request_parser *parser
  ) 
{
  return parser->cs == ebb_request_parser_first_final;
}

void ebb_request_init
  ( ebb_request *request
  )
{
  request->expect_continue = FALSE;
  request->eating_body = 0;
  request->body_read = 0;
  request->content_length = 0;
  request->version_major = 0;
  request->version_minor = 0;
  request->number_of_headers = 0;
  request->transfer_encoding = EBB_IDENTITY;
  request->connection = NULL;
  request->free = NULL;
  request->multipart_boundary_len = 0;
}

