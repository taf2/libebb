

#include <ev.h>
#include "ew.h"

static void set_nonblock
  ( int fd
  )
{
  int flags = fcntl(fd, F_GETFL, 0);
  assert(0 <= fcntl(fd, F_SETFL, flags | O_NONBLOCK) && "Setting socket non-block failed!");
}



/* Internal callback */
static void on_connection
  ( struct ev_loop *loop
  , ev_io *watcher
  , int revents
  )
{
  ew_server *server = (ew_server*)(watcher->data);

  assert(server->open);
  assert(server->loop == loop);
  assert(&server->req_watcher == watcher);
  
  if(EV_ERROR & revents) {
    g_message("on_connection() got error event, closing server.");
    ew_server_unlisten(server);
    return;
  }

  
  struct sockaddr_in addr; // connector's address information
  socklen_t addr_len = sizeof(their_addr); 
  int fd = accept( server->fd
                 , (struct sockaddr*) & addr
                 , & addr_len
                 );
  if(fd < 0) {
    perror("accept()");
    return;
  }

  
  ew_connection *connection = server->connection_handler(server, addr);
  
  if(connection == NULL) {
    close(fd);    
    return;
  } 

  set_nonblock(fd);
  connection->fd = fd;
  connection->open = TRUE;
  connection->server = server;
  
  memcpy(&connection->sockaddr, &addr, addr_len);
  
  if(server->port[0] != '\0')
    connection->ip = inet_ntoa(addr.sin_addr);  

  connection->write_watcher.data = connection;
  ev_init (&connection->write_watcher, on_writable);
  ev_io_set (&connection->write_watcher, connection->fd, EV_WRITE);
  /* Note: not starting the write watcher until there is data to 
   * be written
   */

  connection->req_watcher.data = connection;
  ev_init(&connection->req_watcher, on_reqable);
  ev_io_set(&connection->req_watcher, connection->fd, EV_READ | EV_ERROR);
  ev_io_start(server->loop, &connection->req_watcher);
  
  connection->timeout_watcher.data = connection;  
  ev_timer_init(&connection->timeout_watcher, on_timeout, connection->timeout, 0);
  ev_timer_start(connection->server->loop, &connection->timeout_watcher);
}

/**
 * begin the server listening on a file descriptor
 * @param  server pointer to ew_server
 * @param  sfd    the descriptor to listen on
 */
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
  , ew_connection_handler handler
  , void *data
  )
{
  server->connection_handler = handler;
  server->data = data;
  server->loop = loop;
  server->open = FALSE;

  server->port = "\0";

  server->fd = -1;
}
