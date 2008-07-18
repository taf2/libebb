#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <ev.h>
#include "server.h"

static int c = 0;

static void request_complete(ebb_request *request)
{
  ebb_connection_start_write_watcher(request->connection);
  printf("request done!\n");
}

static int on_writable(ebb_connection *connection)
{
  const char *message = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 12\r\n\r\nhello world\n";
  size_t written = write( connection->fd
                        , message
                        , strlen(message)
                        );
  printf("wrote %d byte response\n", written);
  ebb_connection_close(connection);
  return EBB_STOP;
}

ebb_connection* new_connection(ebb_server *server, struct sockaddr_in *addr)
{
  ebb_connection *connection = malloc(sizeof(ebb_connection));

  ebb_connection_init(connection, 30.0);
  connection->parser.request_complete = request_complete;
  connection->on_writable = on_writable;
  connection->free = (void (*)(ebb_connection*))free;
  
  printf("connection: %d\n", c++);
  return connection;
}

int main() 
{
  struct ev_loop *loop = ev_default_loop(0);
  ebb_server server;

  ebb_server_init(&server, loop);
  server.new_connection = new_connection;

  printf("test_server listening on port 5000\n");
  ebb_server_listen_on_port(&server, 5000);
  ev_loop(loop, 0);

  return 0;
}
