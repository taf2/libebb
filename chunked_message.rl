#include "chunked_message.h"
#include <stdio.h>
#include <assert.h>

#ifndef MIN
# define MIN(a,b) (a < b ? a : b)
#endif

static unsigned int hextoi
  ( const char *p
  , size_t len
  )
{
  unsigned int i, total = 0;
  int n;
  for(i = 0; i < len; i++) {
    switch(p[i]) {
      case '0': n =  0; break;
      case '1': n =  1; break;
      case '2': n =  2; break;
      case '3': n =  3; break;
      case '4': n =  4; break;
      case '5': n =  5; break;
      case '6': n =  6; break;
      case '7': n =  7; break;
      case '8': n =  8; break;
      case '9': n =  9; break;
      case 'A':
      case 'a': n = 10; break;
      case 'b':
      case 'B': n = 11; break;
      case 'c':
      case 'C': n = 12; break;
      case 'd':
      case 'D': n = 13; break;
      case 'e':
      case 'E': n = 14; break;
      case 'f':
      case 'F': n = 15; break;
      default: assert(0 && "bad hex char");
    }
    total *= 16;
    total += n;
  }
  return total;
}

#define LEN (p - parser->mark)
#define REMAINING (pe - p)
%%{
  machine chunked_parser;

  action mark { parser->mark = p; }

  action start_field {;}
  action write_field {;}
  action start_value {;}
  action write_value {;}

  action chunk_size {
    parser->chunk_size = hextoi(parser->mark, LEN);
    //printf("chunksize: %d\n", parser->chunk_size);
  }

  action skip_data {
    // step past the \n in \r\n
    p += 1;
    //printf("skip!\n");
    if(parser->chunk_size > REMAINING) {
      parser->chunk_handler(parser->data, p, REMAINING);
      parser->chunk_size -= REMAINING;
      fbreak;
    } else {
      parser->chunk_handler(parser->data, p, parser->chunk_size);
      p += parser->chunk_size;
      parser->chunk_size = 0;
      fhold; fgoto chunk_end; 
    }
  }

  include http11 "http11.rl";

  trailer         = (message_header CRLF)*;

  nonzero_xdigit = [1-9a-fA-F];
  #chunk_ext_val   = token | quoted_string;
  chunk_ext_val   = token;

  chunk_ext_name  = token;
  chunk_extension = ( ";" chunk_ext_name ("=" chunk_ext_val)? )*;
  last_chunk = "0"+ chunk_extension? CRLF;
  chunk_size = (xdigit* nonzero_xdigit xdigit*) >mark %chunk_size;
  chunk_end  = CRLF;
  chunk_begin  = chunk_size chunk_extension? CRLF;
  chunk        = chunk_begin @skip_data chunk_end;
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
  parser->mark = NULL;
  parser->chunk_size = 0;
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

  if(0 < parser->chunk_size) {
    size_t eat = MIN(len, parser->chunk_size);
    //printf("eat: %d\n", eat);
    parser->chunk_handler(parser->data, p, eat);
    p += eat;
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
static char buffer[200];

void chunk_handler(void *data, const char *p, size_t len)
{
  //printf("chunk_handler: '%s'", buffer);
  strncat(buffer, p, len);
  //printf(" -> '%s'\n", buffer);
}


int test_string(const char *buf)
{
  int traversed = 0;
  buffer[0] = 0;

  chunked_parser_init(&parser);
  parser.chunk_handler = chunk_handler;
  traversed = chunked_parser_execute(&parser, buf, strlen(buf));

  assert(chunked_parser_is_finished(&parser));
  assert(!chunked_parser_has_error(&parser));

  return traversed;
}

int test_split(const char *buf1, const char *buf2)
{
  int traversed = 0;
  buffer[0] = 0;

  chunked_parser_init(&parser);
  parser.chunk_handler = chunk_handler;
  traversed = chunked_parser_execute(&parser, buf1, strlen(buf1));

  //printf("buffer: %s\n", buffer);

  assert(!chunked_parser_is_finished(&parser));
  assert(!chunked_parser_has_error(&parser));

  traversed += chunked_parser_execute(&parser, buf2, strlen(buf2));

  assert(chunked_parser_is_finished(&parser));
  assert(!chunked_parser_has_error(&parser));

  //printf("buffer: %s\n", buffer);

  return traversed;
}


int main() 
{
  assert(3416 == hextoi("d58", 3));
  assert(0 == hextoi("0", 1));
  assert(2748 == hextoi("ABC", 3));

  test_string("5\r\nhello\r\n0\r\n\r\n"); 
  assert(0 == strcmp("hello", buffer));

  test_string("5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"); 
  assert(0 == strcmp("hello world", buffer));

  // with trailing headers. blech.
  //test_string("5\r\nhello\r\n6\r\n world\r\n0\r\nContent-Type: text/plain\r\n\r\n"); 
  //assert(0 == strcmp("hello world", buffer));

  test_split("5\r\nhello\r", "\n6\r\n world\r\n0\r\n\r\n"); 
  assert(0 == strcmp("hello world", buffer));


  test_split("5\r\nhello", "\r\n6\r\n world\r\n0\r\n\r\n"); 
  assert(0 == strcmp("hello world", buffer));

  test_split("5\r\nhel", "lo\r\n6\r\n world\r\n0\r\n\r\n"); 
  assert(0 == strcmp("hello world", buffer));

  printf("okay\n");
  return 0;
}

#endif
