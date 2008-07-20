#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <ev.h>
#include <server.h>

#define MSG ("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 12\r\n\r\nhello world\n")
static int c = 0;

static void request_complete(ebb_request *request)
{
  ebb_connection_enable_on_writable(ebb_request_connection(request));
  printf("request done!\n");
}

static int on_writable(ebb_connection *connection)
{
  size_t written = write(connection->fd, MSG, sizeof MSG);
  printf("wrote %d byte response\n", written);
  ebb_connection_close(connection);
  return EBB_STOP;
}

ebb_request* new_request(ebb_connection *connection)
{
  ebb_request *request = malloc(sizeof(ebb_request));
  request->request_complete = request_complete;
  request->free = (void (*)(ebb_request*))free;
  return request;
}

ebb_connection* new_connection(ebb_server *server, struct sockaddr_in *addr)
{
  ebb_connection *connection = malloc(sizeof(ebb_connection));

  ebb_connection_init(connection, 30.0);
  connection->new_request = new_request;
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

  printf("hello_world listening on port 5000\n");
  ebb_server_listen_on_port(&server, 5000);
  ev_loop(loop, 0);

  return 0;
}
