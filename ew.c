

#include <ev.h>
#include "ew.h"

static void set_nonblock
  ( int fd
  )
{
  int flags = fcntl(fd, F_GETFL, 0);
  assert(0 <= fcntl(fd, F_SETFL, flags | O_NONBLOCK) && "Setting socket non-block failed!");
}

static void on_connection
  ( struct ev_loop *loop
  , ev_io *watcher
  , int revents
  )
{
  ew_server *server = (ew_server*)(watcher->data);

  assert(server->open);
  assert(server->loop == loop);
  assert(&server->request_watcher == watcher);
  
  if(EV_ERROR & revents) {
    g_message("on_connection() got error event, closing server.");
    ew_server_unlisten(server);
    return;
  }


  
  struct sockaddr_in connection_addr; // connector's address information
  socklen_t connection_addr_len = sizeof(their_addr); 
  int fd = accept( server->fd
                 , (struct sockaddr*) & connection_addr
                 , & connection_addr_len
                 );
  if(fd < 0) {
    perror("accept()");
    return;
  }

  
  ew_connection *connection = 
    server->new_connection(server, connection_addr);
  
  if(connection == NULL) {
    close(fd);    
    return;
  } 

  set_nonblock(fd);
  connection->fd = fd;
  connection->open = TRUE;
  
  memcpy(&connection->sockaddr, &connection_addr, connection_addr_len);
  
  if(server->port[0] != '\0')
    client->ip = inet_ntoa(client->sockaddr.sin_addr);  
  
  /* INITIALIZE http_parser */
  http_parser_init(&client->parser);
  client->parser.data = client;
  client->parser.http_field = http_field_cb;
  client->parser.on_element = on_element;
  
  /* OTHER */
  client->env_size = 0;
  client->read =  0;
  if(client->request_buffer == NULL) {
    /* Only allocate the request_buffer once */
    client->request_buffer = (char*)malloc(EBB_BUFFERSIZE);
  }
  client->keep_alive = FALSE;
  client->status_written = client->headers_written = client->body_written = FALSE;
  client->written = 0;
  
  if(client->response_buffer != NULL)
    g_string_free(client->response_buffer, TRUE);
  client->response_buffer = g_string_new("");
  
  /* SETUP READ AND TIMEOUT WATCHERS */
  client->write_watcher.data = client;
  ev_init (&client->write_watcher, on_client_writable);
  ev_io_set (&client->write_watcher, client->fd, EV_WRITE | EV_ERROR);
  /* Note, do not start write_watcher until there is something to be written.
   * See ebb_client_write_body() */
  
  client->read_watcher.data = client;
  ev_init(&client->read_watcher, on_client_readable);
  ev_io_set(&client->read_watcher, client->fd, EV_READ | EV_ERROR);
  ev_io_start(client->server->loop, &client->read_watcher);
  
  client->timeout_watcher.data = client;  
  ev_timer_init(&client->timeout_watcher, on_timeout, EBB_TIMEOUT, EBB_TIMEOUT);
  ev_timer_start(client->server->loop, &client->timeout_watcher);
}

int ew_server_listen_on_fd
  ( ew_server *server
  , const int sfd 
  )
{
  if (listen(sfd, EW_MAX_CLIENTS) < 0) {
    perror("listen()");
    return -1;
  }
  
  set_nonblock(sfd); /* XXX superfluous? */
  
  server->fd = sfd;
  assert(server->open == FALSE);
  server->open = TRUE;
  
  server->connection_watcher.data = server;
  ev_init (&server->connection_watcher, on_connection);
  ev_io_set (&server->connection_watcher, server->fd, EV_READ | EV_ERROR);
  ev_io_start (server->loop, &server->connection_watcher);
  
  return server->fd;
}


int ew_server_listen_on_port
  ( ew_server *server
  , const int port
  )
{
  int sfd = -1;
  struct linger ling = {0, 0};
  struct sockaddr_in addr;
  int flags = 1;
  
  if ((sfd = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
    perror("socket()");
    goto error;
  }
  
  flags = 1;
  setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, (void *)&flags, sizeof(flags));
  setsockopt(sfd, SOL_SOCKET, SO_KEEPALIVE, (void *)&flags, sizeof(flags));
  setsockopt(sfd, SOL_SOCKET, SO_LINGER, (void *)&ling, sizeof(ling));
  setsockopt(sfd, IPPROTO_TCP, TCP_NODELAY, (void *)&flags, sizeof(flags));
  
  /*
   * the memset call clears nonstandard fields in some impementations
   * that otherwise mess things up.
   */
  memset(&addr, 0, sizeof(addr));
  
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  
  if (bind(sfd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    perror("bind()");
    goto error;
  }
  
  int ret = ew_server_listen_on_fd(server, sfd);
  if (ret >= 0) {
    sprintf(server->port, "%d", port);
  }
  return ret;
error:
  if(sfd > 0) close(sfd);
  return -1;
}


void ew_server_init
  ( ew_server *server
  , struct ev_loop *loop
  , ew_new_connection_handler handler
  , void *data
  )
{
  server->new_connection = handler;
  server->data = request_cb_data;
  server->loop = loop;
  server->open = FALSE;

  server->port = "\0";

  server->fd = -1;
}
