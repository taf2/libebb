#include <error.h>
#include <ev.h>
#include "ew.h"

static void set_nonblock
  ( int fd
  )
{
  int flags = fcntl(fd, F_GETFL, 0);
  int r = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  assert(0 <= r && "Setting socket non-block failed!");
}

/** 
 * Must call this after ew_buf->save callback has been called.
 * Allows you do to do async save operations (like writing to file).
 * ew_buf->save, like all callbacks, MUST be non-blocking.  
 */
void ew_buf_save_finished
  ( ew_buf *buf
  )
{
  ;
}


/* Internal callback 
 * called by request->read_watcher
 */
static void on_readable 
  ( struct ev_loop *loop
  , ev_io *watcher
  , int revents
  )
{
  ew_request *request = (ew_request*)(watcher->data);

  if(request->has_read_head)
    if(request->headers.chunked_encoding) 
      goto read_body_chunked;
    else
      goto read_body_normal;
  else
    goto read_header;

/* read the header into request->header_buf. overflow is not tolerated.
 *
 */
read_header:
  if(EW_MAX_HEADER_SIZE <= request->read) {
    /* header buffer overflow. increase EW_MAX_HEADER_SIZE? */
    goto error;
  }
  
  ssize_t read = recv( request->connection->fd
                     , request->header_buf + request->read
                     , EW_MAX_HEADER_SIZE - request->read
                     , 0
                     );

  if(read < 0) goto error;
  if(read == 0) goto error; /* XXX is this the right action to take for read==0 ? */
  request->read += read;

  ev_timer_again(loop, watcher);

  request_headers_parse( &request->headers
                       , request->header_buf
                       , request->read
                       );

  if(request_headers_has_error(&request->headers)) 
    goto error;

  if(!request_headers_is_finished(&request->headers))
    return;

  /* otherwise we're finished */

  request->has_read_head = TRUE;

  assert(request->read >= request->headers.nread);
  unsigned int left_over = request->read - request->headers.nread;
  
  if(left_over > 0) {
    if(request->headers.chunked)
      goto read_body_chunked;
    else
      goto read_body_normal;
  }
  if(content_length == 0 && left_over > 0)
  if(request->headers.method == EW_GET || request->headers.method == EW_HEAD) {
    ev_io_stop(&request->read_watcher);
    /* start a new requestuest with left_over? */
    assert(left_over == 0 && "left_over == 0 for get/head. ");
     
  } else {
    unsigned int left_over = request->read - request->headers.len;
    ew_buf *buf = request->get_buf(request, left_over);
    memcpy(buf->buf, request->header_buf + request->headers.len, left_over);
    request->body = buf;
  }

recv_unknown_amount:
  ew_recv_buf *recv_buf = NULL;

read_body_chunked:
  assert(0 && "Not Implemented");
  return;

read_body_normal:
  unsigned int needed;

  if(request->headers->content_length > 0) {
    needed = request->headers->content_length - request->read;
    buf = request->get_buf(request, needed);
  } else {
    /* need a buf but unknown size */
    buf = request->get_buf(request, 0);
  }

  if(buf == NULL) goto error;

  assert(buf->max_len > buf->len);

  ssize_t read = recv( request->connection->fd
                     , buf->buf + buf->len
                     , buf->max_len - buf->len
                     , 0
                     );
  if(read < 0) goto error;
  if(read == 0) goto error; /* XXX is this the right action to take for read==0 ? */
  buf->len += read;
  request->read += read;

  ev_timer_again( request->connection->server->loop
                , &request->connection->timeout_watcher
                );

  if(request->headers.content_length > 0) {
    if(request->read - request->header_buf.len == request->headers->content_length)
      finished!
  } else {
  }
  return;

error:
}

/* Internal callback 
 * Called by when a connection sends a new request.
 * Seperated from on_connection() because Keep-Alive connections can have
 * multiple requests
 * this is callback might be called multiple times per connection.
 */
static void on_request 
  ( struct ev_loop *loop
  , ev_io *watcher
  , int revents
  )
{
  ew_connection *connection = (ew_connection*)(watcher->data);
  
  assert(connection->open);
  assert(connection->server->listening);
  assert(connection->server->loop == loop);
  assert(&connection->read_watcher == watcher);

  ev_io_stop(loop, watcher);

  ew_request *request = NULL;
  if(connection->new_request)
    request = connection->new_request(connection);
  if(request == NULL) {
    return;
  }

  request->connection = connection;
  ev_io_set(&request->read_watcher, connection->fd, EV_READ | EV_ERROR);
  /* XXX: more reason for connections to have special error watchers */
  ev_io_start(loop, &request->read_watcher);
  /* XXX: the callback for the read_watcher 
   * should be called immediately? or should i call it manually?
   */

  ev_timer_again(loop, &connection->timeout_watcher);
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
  ew_server *server = (ew_server*)(watcher->data);

  assert(server->listening);
  assert(server->loop == loop);
  assert(&server->connection_watcher == watcher);
  
  if(EV_ERROR & revents) {
    error(0, 0, "on_connection() got error event, closing server.\n");
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

  ew_connection *connection = NULL;
  if(server->new_connection)
     connection = server->new_connection(server, addr);
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

  /* Note: not starting the write watcher until there is data to be written */
  ev_io_set(&connection->write_watcher,   connection->fd, EV_WRITE);
  ev_io_set(&connection->request_watcher, connection->fd, EV_READ | EV_ERROR);
  /* XXX: seperate error watcher? */

  ev_io_start(loop, &connection->request_watcher);
  ev_timer_start(loop, &connection->timeout_watcher);
}


static ew_request* request_new
  ( ew_connection *connection
  , const char *intial_data
  , size_t initial_data_len 
  )
{
  ew_request *request = connection->request_handler(connection);

  if(request == NULL) {
    return NULL;
  }

  request->connection = connection; 

  assert(initial_data_len < EW_MAX_HEADER_SIZE);

  memcpy(request->header_buf, initial_data, initial_data_len);
  request->read = intial_data_len;

  request->read_watcher.data = request;
  ev_init(&request->read_watcher, read_request);
  ev_io_set(&request->read_watcher, connection->fd, EV_READ | EV_ERROR);
  ev_io_start(connection->loop, &request->read_watcher);
  /* Note, not starting the read_watcher until there is something to be
   * a request is made
   */
}

/**
 * begin the server listening on a file descriptor
 * Thie DOES NOT start the event loop. That is your job.
 * Start the event loop after the server is listening.
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
  assert(server->listening == FALSE);
  server->listening = TRUE;
  
  ev_io_set (&server->connection_watcher, server->fd, EV_READ | EV_ERROR);
  ev_io_start (server->loop, &server->connection_watcher);
  
  return server->fd;
}


/**
 * begin the server listening on a localhost TCP port
 * Thie DOES NOT start the event loop. That is your job.
 * Start the event loop after the server is listening.
 */
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

/**
 * Stops a server from listening. Will not accept new connections.
 * TODO: Drops all connections?
 */
void ew_server_unlisten
  ( ew_server *server
  )
{
  if(server->listening) {
    ev_io_stop(server->loop, &server->connection_watcher);
    close(server->fd);
    server->port = "\0";
    server->listening = FALSE;
  }
}

/**
 * Initialize an ew_server structure.
 * After calling ew_server_init set the callback server->new_connection 
 * and, optionally, callback data server->data 
 *
 * @params server the server to initialize
 * @params loop a libev loop
 */
void ew_server_init
  ( ew_server *server
  , struct ev_loop *loop
  )
{
  server->loop = loop;
  server->listening = FALSE;
  server->port = "\0";
  server->fd = -1;
  server->connection_watcher.data = server;
  ev_init (&server->connection_watcher, on_connection);

  server->new_connection = NULL;
  server->data = NULL;
}

/**
 * Initialize an ew_connection structure.
 * After calling ew_connection_init set the callback 
 * connection->new_request 
 * and, optionally, callback data connection->data 
 * 
 * This should be called immediately after allocating space for
 * a new ew_connection structure. Most likely, this will only 
 * be called within the ew_server->new_connection callback which
 * you supply. 
 *
 * @params connection the connection to initialize
 * @params timeout    the timeout in seconds
 */
void ew_connection_init
  ( ew_connection *connection
  , float timeout
  )
{
  connection->fd = -1;
  connection->server = NULL;
  connection->ip = "\0";
  connection->open = FALSE;
  connection->timeout = timeout;
  
  connection->write_watcher.data = connection;
  ev_init (&connection->write_watcher, on_writable);

  connection->request_watcher.data = connection;
  ev_init(&connection->request_watcher, on_request);

  connection->timeout_watcher.data = connection;  
  ev_timer_init(&connection->timeout_watcher, on_timeout, timeout, 0);


  connection->new_request = NULL;
  connection->free = NULL;
  connection->data = NULL;
}

/** 
 * Initialze ew_request structure. Call this from your connection->new_request
 * callback
 */
void ew_request_init
  ( ew_request *request
  ) 
{
  request->connection = NULL;
  request_headers_init(&request->headers);
  request->header_buf[0] = '\0';
  request->read = 0;
  request->read_body_normal = 0;
  request->has_read_head = FALSE;

  request->read_watcher.data = request;
  ev_init(&request->read_watcher, on_readable);

  request->new_buf = NULL;
  request->free = NULL;
  request->data = NULL;
}
