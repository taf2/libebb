#include <stdio.h>
#include <stdlib.h>
#include <ev.h>
#include "ebb.h"

ebb_connection* 
new_connection(ebb_server *server, struct sockaddr_in *addr)
{
  ebb_connection *connection = malloc(sizeof(ebb_connection));
  connection->new_buf = new_buf;
  connection->on_writable = on_writable;

  ebb_request_parser *parser = malloc(sizeof(ebb_request_parser));
  ebb_request_parser_init(parser); 

  ebb_connection_init(connection, parser, 30.0);
  parser->new_element = new_element;
  parser->new_request_info = new_request_info;
  parser->body_handler = body_handler;
  parser->body_handler = header_handler;
  
  printf("connection!\n");
  return NULL;
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
