#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <assert.h>

#include <ev.h>
#include <ebb.h>

#define MSG ("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 12\r\n\r\nhello world\n")
static int c = 0;

struct hello_connection {
  unsigned int responses_to_write;
};

static ebb_buf response = { base: MSG
                          , len: sizeof MSG
                          };

static void response_complete_close(ebb_buf *buf)
{
  ebb_connection *connection = buf->data;
  ebb_connection_close(connection);
}

static void response_complete_continue(ebb_buf *buf)
{
  ebb_connection *connection = buf->data;
  struct hello_connection *connection_data = connection->data;
  //printf("response complete \n");
  if(--connection_data->responses_to_write > 0)
    /* write another response */
    assert(ebb_connection_write(connection, &response));
  else
    ebb_connection_close(connection);
}

static void request_complete(ebb_request *request)
{
  //printf("request complete \n");
  ebb_connection *connection = ebb_request_connection(request);
  struct hello_connection *connection_data = connection->data;
  connection_data->responses_to_write++;
  response.data = connection;

  if(ebb_request_should_keep_alive(request))
    response.free = response_complete_continue;
  else
    response.free = response_complete_close;

  ebb_connection_write(connection, &response);
}

static ebb_request* new_request(ebb_connection *connection)
{
  //printf("request %d\n", ++c);
  ebb_request *request = malloc(sizeof(ebb_request));
  ebb_request_init(request);
  request->request_complete = request_complete;
  request->free = (void (*)(ebb_request*))free;
  return request;
}

void free_connection(ebb_connection *connection)
{
  free(connection->data);
  free(connection);
}

ebb_connection* new_connection(ebb_server *server, struct sockaddr_in *addr)
{
  struct hello_connection *connection_data = malloc(sizeof(struct hello_connection));
  if(connection_data == NULL)
    return NULL;
  connection_data->responses_to_write = 0;

  ebb_connection *connection = malloc(sizeof(ebb_connection));
  if(connection == NULL) {
    free(connection_data);
    return NULL;
  }

  ebb_connection_init(connection, 3.0);
  connection->data = connection_data;
  connection->new_request = new_request;
  connection->free = free_connection;
  
  //printf("connection: %d\n", c++);
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
