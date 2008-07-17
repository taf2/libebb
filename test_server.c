#include <stdio.h>
#include <stdlib.h>
#include <ev.h>
#include "server.h"

#define BUFFERS 80
#define SIZE 1024
static char buffer[BUFFERS*SIZE] = "\0";
static int c = 0;
static ebb_connection *connection;

ebb_buf* new_buf() { 
  if(c > BUFFERS) {
    printf("no more buffers :(\n");
    exit(1);
  }
  ebb_buf *buf = malloc(sizeof(ebb_buf));
  buf->base = buffer + SIZE * c++;
  buf->len = SIZE;
  return buf; 
}

static void request_complete(ebb_request_info *info, void *data)
{
  printf("request done!\n");
  ebb_connection_close(connection);
}


ebb_connection* new_connection(ebb_server *server, struct sockaddr_in *addr)
{
  connection = malloc(sizeof(ebb_connection));

  ebb_request_parser *parser = malloc(sizeof(ebb_request_parser));
  ebb_request_parser_init(parser); 
  parser->request_complete = request_complete;
  //parser->body_handler = body_handler;
  //parser->body_handler = header_handler;

  ebb_connection_init(connection, parser, 30.0);
  connection->new_buf = new_buf;
  //connection->on_writable = on_writable;
  
  printf("connection: %d\n", c);
  return connection;
}

int main() 
{
  struct ev_loop *loop = ev_default_loop(0);
  ebb_server *server;

  server = malloc(sizeof(ebb_server));

  ebb_server_init(server, loop);
  server->new_connection = new_connection;

  ebb_server_listen_on_port(server, 5000);
  ev_loop(loop, 0);

  return 0;
}
