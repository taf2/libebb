#include <assert.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/tcp.h> /* TCP_NODELAY */
#include <netinet/in.h>  /* inet_ntoa */
#include <arpa/inet.h>   /* inet_ntoa */
#include <unistd.h>
#include <error.h>
#include <stdio.h>      /* perror */
#include <errno.h>      /* perror */
#include <stdlib.h> /* for the default methods */

#include <ev.h>

#include "ebb.h"
#include "ebb_request_parser.h"

#define TRUE 1
#define FALSE 0

#define FREE_CONNECTION_IF_CLOSED \
  if(!connection->open && connection->free) connection->free(connection);

static void set_nonblock (int fd)
{
  int flags = fcntl(fd, F_GETFL, 0);
  int r = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  assert(0 <= r && "Setting socket non-block failed!");
}

/* Internal callback 
 * called by connection->timeout_watcher
 */
static void on_timeout 
  ( struct ev_loop *loop
  , ev_timer *watcher
  , int revents
  )
{
  ebb_connection *connection = watcher->data;

  /* if on_timeout returns true, we don't time out */
  if( connection->on_timeout 
   && connection->on_timeout(connection) != EBB_AGAIN
    ) 
  {
    ev_timer_again(loop, watcher);
    return;
  }

  ebb_connection_close(connection);
  FREE_CONNECTION_IF_CLOSED 
}

/* Internal callback 
 * called by connection->wrte_watcher
 */
static void on_writable 
  ( struct ev_loop *loop
  , ev_io *watcher
  , int revents
  )
{
  ebb_connection *connection = watcher->data;

  if(connection->on_writable) {
    int r = connection->on_writable(connection);
    assert(r == EBB_STOP || r == EBB_AGAIN);
    if(EBB_STOP == r)
      ev_io_stop(loop, watcher);
    else
      ev_timer_again(loop, &connection->timeout_watcher);
  } else {
    ev_io_stop(loop, watcher);
  }
  FREE_CONNECTION_IF_CLOSED 
}


/* Internal callback 
 * called by connection->read_watcher
 */
static void on_readable 
  ( struct ev_loop *loop
  , ev_io *watcher
  , int revents
  )
{
  ebb_connection *connection = watcher->data;

  ebb_buf *buf = NULL;
  if(connection->new_buf)
    buf = connection->new_buf(connection);
  if(buf == NULL) goto error; 

  ssize_t read = recv( connection->fd
                     , buf->base
                     , buf->len
                     , 0
                     );
  if(read < 0) goto error;
  /* XXX is this the right action to take for read==0 ? */
  if(read == 0) goto error; 

  ev_timer_again(loop, &connection->timeout_watcher);

  ebb_request_parser_execute( &connection->parser
                            , buf->base
                            , read
                            );

  /* parse error? just drop the client. screw the 400 response */
  if(ebb_request_parser_has_error(&connection->parser)) goto error;

  if(buf->free)
    buf->free(buf);

  FREE_CONNECTION_IF_CLOSED 
  return;
error:
  ebb_connection_close(connection);
  FREE_CONNECTION_IF_CLOSED 
}


/* Internal callback 
 * Called by server->connection_watcher.
 */
static void on_connection
  ( struct ev_loop *loop
  , ev_io *watcher
  , int revents
  )
{
  ebb_server *server = watcher->data;

  assert(server->listening);
  assert(server->loop == loop);
  assert(&server->connection_watcher == watcher);
  
  if(EV_ERROR & revents) {
    error(0, 0, "on_connection() got error event, closing server.\n");
    ebb_server_unlisten(server);
    return;
  }
  
  struct sockaddr_in addr; // connector's address information
  socklen_t addr_len = sizeof(addr); 
  int fd = accept( server->fd
                 , (struct sockaddr*) & addr
                 , & addr_len
                 );
  if(fd < 0) {
    perror("accept()");
    return;
  }

  ebb_connection *connection = NULL;
  if(server->new_connection)
    connection = server->new_connection(server, &addr);
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
    connection->ip = inet_ntoa(connection->sockaddr.sin_addr);  

  /* Note: not starting the write watcher until there is data to be written */
  ev_io_set(&connection->write_watcher, connection->fd, EV_WRITE);
  ev_io_set(&connection->read_watcher, connection->fd, EV_READ | EV_ERROR);
  /* XXX: seperate error watcher? */

  ev_io_start(loop, &connection->read_watcher);
  ev_timer_start(loop, &connection->timeout_watcher);
}

/**
 * Begin the server listening on a file descriptor.  This DOES NOT start the
 * event loop.  Start the event loop after making this call.
 */
int ebb_server_listen_on_fd
  ( ebb_server *server
  , const int fd 
  )
{
  assert(server->listening == FALSE);

  if (listen(fd, EBB_MAX_CONNECTIONS) < 0) {
    perror("listen()");
    return -1;
  }
  
  set_nonblock(fd); /* XXX superfluous? */
  
  server->fd = fd;
  server->listening = TRUE;
  
  ev_io_set (&server->connection_watcher, server->fd, EV_READ | EV_ERROR);
  ev_io_start (server->loop, &server->connection_watcher);
  
  return server->fd;
}


/**
 * Begin the server listening on a file descriptor This DOES NOT start the
 * event loop. Start the event loop after making this call.
 */
int ebb_server_listen_on_port
  ( ebb_server *server
  , const int port
  )
{
  int fd = -1;
  struct linger ling = {0, 0};
  struct sockaddr_in addr;
  int flags = 1;
  
  if ((fd = socket(AF_INET, SOCK_STREAM, 0)) == -1) {
    perror("socket()");
    goto error;
  }
  
  flags = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (void *)&flags, sizeof(flags));
  setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, (void *)&flags, sizeof(flags));
  setsockopt(fd, SOL_SOCKET, SO_LINGER, (void *)&ling, sizeof(ling));

  /* TODO: Sending single byte messages in a response?  Perhaps need to
   * enable the Nagel algorithm dynamically For now disabling.
   */
  setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (void *)&flags, sizeof(flags));
  
  /* the memset call clears nonstandard fields in some impementations that
   * otherwise mess things up.
   */
  memset(&addr, 0, sizeof(addr));
  
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  
  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    perror("bind()");
    goto error;
  }
  
  int ret = ebb_server_listen_on_fd(server, fd);
  if (ret >= 0) {
    sprintf(server->port, "%d", port);
  }
  return ret;
error:
  if(fd > 0) close(fd);
  return -1;
}

/**
 * Stops the server. Will not accept new connections.  Does not drop
 * existing connections.
 */
void ebb_server_unlisten
  ( ebb_server *server
  )
{
  if(server->listening) {
    ev_io_stop(server->loop, &server->connection_watcher);
    close(server->fd);
    server->port[0] = '\0';
    server->listening = FALSE;
  }
}

/**
 * Initialize an ebb_server structure.  After calling ebb_server_init set
 * the callback server->new_connection and, optionally, callback data
 * server->data.  The new connection MUST be initialized with
 * ebb_connection_init before returning it to the server.
 *
 * @param server the server to initialize
 * @param loop a libev loop
 */
void ebb_server_init
  ( ebb_server *server
  , struct ev_loop *loop
  )
{
  server->loop = loop;
  server->listening = FALSE;
  server->port[0] = '\0';
  server->fd = -1;
  server->connection_watcher.data = server;
  ev_init (&server->connection_watcher, on_connection);

  server->new_connection = NULL;
  server->data = NULL;
}

static void default_buf_free 
  ( ebb_buf *buf
  )
{
  free(buf->base);
  free(buf);
}

static ebb_buf* default_new_buf
  ( ebb_connection *connection
  )
{
  ebb_buf *buf = malloc(sizeof(ebb_buf));
  buf->base = malloc(4*1024);
  buf->len = 4*1024;
  buf->free = default_buf_free;
  return buf;
}

static ebb_request* new_request_wrapper
  ( void *data
  )
{
  ebb_connection *connection = data;
  if(connection->new_request)
    return connection->new_request(connection);
  return NULL;
}

/**
 * Initialize an ebb_connection structure. After calling this function you
 * must setup callbacks for the different actions the server can take. See
 * server.h for which callbacks are availible. 
 * 
 * This should be called immediately after allocating space for a new
 * ebb_connection structure. Most likely, this will only be called within
 * the ebb_server->new_connection callback which you supply. 
 *
 * @param connection the connection to initialize
 * @param timeout    the timeout in seconds
 */
void ebb_connection_init
  ( ebb_connection *connection
  , float timeout
  )
{
  connection->fd = -1;
  connection->server = NULL;
  connection->ip = NULL;
  connection->open = FALSE;
  connection->timeout = timeout;

  ebb_request_parser_init( &connection->parser );
  connection->parser.data = connection;
  connection->parser.new_request = new_request_wrapper;
  
  connection->write_watcher.data = connection;
  ev_init (&connection->write_watcher, on_writable);

  connection->read_watcher.data = connection;
  ev_init(&connection->read_watcher, on_readable);

  connection->timeout_watcher.data = connection;  
  ev_timer_init(&connection->timeout_watcher, on_timeout, timeout, 0);

  connection->new_buf = default_new_buf;
  connection->new_request = NULL;
  connection->on_timeout = NULL;
  connection->on_writable = NULL;
  connection->free = NULL;
  connection->data = NULL;
}

void ebb_connection_close
  ( ebb_connection *connection
  )
{
  if(connection->open) {
    close(connection->fd);
    ev_io_stop(connection->server->loop, &connection->read_watcher);
    ev_io_stop(connection->server->loop, &connection->write_watcher);
    ev_timer_stop(connection->server->loop, &connection->timeout_watcher);
    connection->open = FALSE;
  }
}

/** Enables connection->on_writable callback
 * It will be called when the socket is okay to write to.  Stop the callback
 * by returning EBB_STOP from connection->on_writable.
 */
void ebb_connection_enable_on_writable 
  ( ebb_connection *connection
  )
{
  ev_io_start(connection->server->loop, &connection->write_watcher);
}

