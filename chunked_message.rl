#include "chunked_message.h"
#include <stdio.h>
#include <assert.h>

#ifndef MIN
# define MIN(a,b) (a < b ? a : b)
#endif


#define LEN (p - parser->mark)
#define REMAINING (pe - p)
%%{
  machine chunked_parser;

  action mark { parser->mark = p; }

  action add_to_chunk_size {
    parser->chunk_size *= 16;

    if( 'A' <= *p && *p <= 'F') 
      parser->chunk_size += *p - 'A' + 10;
    else if( 'a' <= *p && *p <= 'f') 
      parser->chunk_size += *p - 'a' + 10;
    else if( '0' <= *p && *p <= '9') 
      parser->chunk_size += *p - '0';
    else  
      assert(0 && "bad hex char");

  }

  action start_field {;}
  action write_field {;}
  action start_value {;}
  action write_value {;}

  action skip_data {
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

  include http11 "http11.rl";

  trailer = message_header*;

  nonzero_xdigit = [1-9a-fA-F];
  #chunk_ext_val   = token | quoted_string;
  chunk_ext_val   = token*;

  chunk_ext_name  = token*;
  chunk_extension = ( ";" " "* chunk_ext_name ("=" chunk_ext_val)? )*;
  last_chunk = "0"+ chunk_extension CRLF;
  chunk_size = (xdigit* nonzero_xdigit xdigit*) $add_to_chunk_size;
  chunk_end  = CRLF;
  chunk_body = any >skip_data;
  chunk_begin  = chunk_size chunk_extension CRLF;
  chunk        = chunk_begin chunk_body chunk_end;
  Chunked_Body = chunk* last_chunk trailer CRLF;

main := Chunked_Body;

}%%

%% write data;

void chunked_parser_init
  ( chunked_parser *parser
  ) 
{
  int cs = 0;
  %% write init;
  parser->cs = cs;
  parser->chunk_size = 0;
  parser->eating = 0;

  parser->mark = NULL;
  parser->nread = 0;
  parser->chunk_handler = NULL;
}


/** exec **/
size_t chunked_parser_execute
  ( chunked_parser *parser
  , const char *buffer
  , size_t len
  )  
{
  const char *p, *pe;
  int cs = parser->cs;


  p = buffer;
  pe = buffer+len;

  if(0 < parser->chunk_size && parser->eating) {
    size_t eat = MIN(len, parser->chunk_size);
    if(eat == parser->chunk_size) {
      parser->eating = 0;
    }
    parser->chunk_handler(parser->data, p, eat);
    p += eat;
    parser->chunk_size -= eat;
    //printf("eat: %d\n", eat);
  }


  %% write exec;

  parser->cs = cs;
  parser->nread += p - buffer;

  assert(p <= pe && "buffer overflow after parsing execute");

  if(parser->mark)
    assert(parser->mark < pe && "mark is after buffer end");

  return(p - buffer);
}

int chunked_parser_has_error
  ( chunked_parser *parser
  ) 
{
  return parser->cs == chunked_parser_error;
}

int chunked_parser_is_finished
  ( chunked_parser *parser
  ) 
{
  return parser->cs == chunked_parser_first_final;
}

#ifdef UNITTEST
#include <string.h>

static chunked_parser parser;   
static char test_buf[200];

void chunk_handler(void *data, const char *p, size_t len)
{
  //printf("chunk_handler: '%s'", test_buf);
  strncat(test_buf, p, len);
  //printf(" -> '%s'\n", test_buf);
}


int test_string(const char *buf)
{
  int traversed = 0;
  test_buf[0] = 0;

  chunked_parser_init(&parser);
  parser.chunk_handler = chunk_handler;
  traversed = chunked_parser_execute(&parser, buf, strlen(buf));

  if(!chunked_parser_is_finished(&parser)) 
    return -1;
  if(chunked_parser_has_error(&parser))
    return -2;

  return 1;
}

int test_split(const char *buf1, const char *buf2)
{
  int traversed = 0;
  test_buf[0] = 0;

  chunked_parser_init(&parser);
  parser.chunk_handler = chunk_handler;
  traversed = chunked_parser_execute(&parser, buf1, strlen(buf1));

  //printf("test_buf: %s\n", test_buf);

  if(chunked_parser_is_finished(&parser))
    return -1;
  if(chunked_parser_has_error(&parser))
    return -2;

  traversed += chunked_parser_execute(&parser, buf2, strlen(buf2));

  if(chunked_parser_has_error(&parser))
    return -3;
  if(!chunked_parser_is_finished(&parser))
    return -4;

  //printf("test_buf: %s\n", test_buf);

  return 1;
}


int main() 
{
  assert(0 < test_string("5\r\nhello\r\n0\r\n\r\n")); 
  assert(0 == strcmp("hello", test_buf));

  assert(0 < test_string("5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n")); 
  assert(0 == strcmp("hello world", test_buf));

  // with trailing headers. blech.
  assert(0 < test_string("5\r\nhello\r\n6\r\n world\r\n0\r\nVary: *\r\nContent-Type: text/plain\r\n\r\n")); 
  assert(0 == strcmp("hello world", test_buf));

  // with bullshit after the length
  assert(0 < test_string("5; ihatew3;whatthefuck=aretheseparametersfor\r\nhello\r\n6; blahblah; blah\r\n world\r\n0\r\n\r\n"));
  assert(0 == strcmp("hello world", test_buf));

  assert(0 < test_split("5\r\nhello\r", "\n6\r\n world\r\n0\r\n\r\n")); 
  assert(0 == strcmp("hello world", test_buf));

  assert(0 < test_split("5\r\nhello\r\n", "6\r\n world\r\n0\r\n\r\n")); 
  assert(0 == strcmp("hello world", test_buf));

  assert(0 < test_split("5\r\nhello", "\r\n6\r\n world\r\n0\r\n\r\n")); 
  assert(0 == strcmp("hello world", test_buf));

  assert(0 < test_split("5\r\nhel", "lo\r\n6\r\n world\r\n0\r\n\r\n")); 
  assert(0 == strcmp("hello world", test_buf));

  assert(0 < test_split("5\r\nhello\r\n6\r\n world\r\n0", "\r\n\r\n")); 
  assert(0 == strcmp("hello world", test_buf));

  assert(0 < test_split("5\r\nhello\r\n6\r\n world\r\n0\r\n\r", "\n")); 
  assert(0 == strcmp("hello world", test_buf));

  // split with trailing headers. blech.
  assert(0 < test_split("5\r\nhello\r\n6\r\n world\r\n0\r\nVary: *\r\nCon", "tent-Type: text/plain\r\n\r\n")); 
  assert(0 == strcmp("hello world", test_buf));

  // split with bullshit after the length
  assert(0 < test_split("5; iha", "tew3;whatthefuck=aretheseparametersfor\r\nhello\r\n6; blahblah; blah\r\n world\r\n0\r\n\r\n"));
  assert(0 == strcmp("hello world", test_buf));

  // now work with "all your base are belong to us"
  // because it is two digits in length (0x1e = 30) 

  assert(0 < test_string("1e\r\nall your base are belong to us\r\n0\r\n\r\n")); 
  assert(0 == strcmp("all your base are belong to us", test_buf));

  assert(0 < test_split("1e\r\nall your", " base are belong to us\r\n0\r\n\r\n")); 
  assert(0 == strcmp("all your base are belong to us", test_buf));

  assert(0 < test_split("1e\r", "\nall your base are belong to us\r\n0\r\n\r\n")); 
  assert(0 == strcmp("all your base are belong to us", test_buf));

  assert(0 < test_split("1", "e\r\nall your base are belong to us\r\n0\r\n\r\n")); 
  assert(0 == strcmp("all your base are belong to us", test_buf));

  printf("okay\n");
  return 0;
}

#endif
