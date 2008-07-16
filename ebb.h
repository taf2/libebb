#ifndef ebb_h
#define ebb_h

#include "request_parser.h"
#include <ev.h>
#include <sys/socket.h>
#include <netinet/in.h>
#define EBB_MAX_CLIENTS 1024

typedef struct ebb_buf ebb_buf;
typedef struct ebb_server ebb_server;
typedef struct ebb_connection ebb_connection;
typedef struct ebb_request ebb_request;
typedef struct ebb_res ebb_res;


struct ebb_buf {
  char *base;
  size_t len;
};

struct ebb_server {
  int fd;                      /* ro */
  struct sockaddr_in sockaddr; /* ro */
  socklen_t socklen;           /* ro */
  char port[6];                /* ro */
  struct ev_loop *loop;        /* ro */
  ev_io connection_watcher;    /* private */
  unsigned listening:1;        /* ro */

  /* public */
  ebb_connection* (*new_connection) (ebb_server*, struct sockaddr_in*);
  void (*free) (ebb_server*);
  void *data;
};

void ebb_server_init
  ( ebb_server *server
  , struct ev_loop *loop
  );

int ebb_server_listen_on_port
  ( ebb_server *server
  , const int port
  );

int ebb_server_listen_on_fd
  ( ebb_server *server
  , const int sfd 
  );

void ebb_server_unlisten
  ( ebb_server *server
  );


struct ebb_connection {
  int fd;                      /* ro */
  struct sockaddr_in sockaddr; /* ro */
  socklen_t socklen;           /* ro */ 
  ebb_server *server;          /* ro */
  float timeout;               /* ro */
  char *ip;                    /* ro */
  unsigned open:1;             /* ro */
  ev_io read_watcher;          /* private */
  ev_io write_watcher;         /* private */
  ev_timer timeout_watcher;    /* private */
  ebb_parser parser;           /* private */

  /* public */
  ebb_element* (*new_element) (ebb_connection*);
  ebb_buf* (*new_buf) (ebb_connection*);
  ebb_request* (*new_request) (ebb_connection*);
  int (*on_timeout) (ebb_connection*); /* return true to keep alive */
  void (*on_close) (ebb_connection*); 
  void (*free) (ebb_connection*);
  void *data;
};

void ebb_connection_close
  ( ebb_connection *connection
  );

ssize_t ebb_connection_write 
  ( ebb_connection *
  , const char *data
  , size_t len
  );

ebb_request* ebb_connection_current_request
  ( ebb_connection *connection
  );

void ebb_response_written_for
  ( ebb_request *request
  );

struct ebb_request {
  ebb_request_info info;              /* ro */
  ebb_request *next;                  /* ro */
  ebb_connection *connection;         /* ro */

  /* public */
  int  (*on_expect_continue)(ebb_request*);
  void (*on_complete)       (ebb_request*);
  void (*ready_for_write)   (ebb_request*);

  void (*body_handler)  (ebb_request*, const char *at, size_t length);
  void (*header_handler)(ebb_request*, ebb_element *field, ebb_element *value);
  void (*request_method)(ebb_request*, ebb_element*);
  void (*request_uri)   (ebb_request*, ebb_element*);
  void (*fragment)      (ebb_request*, ebb_element*);
  void (*request_path)  (ebb_request*, ebb_element*);
  void (*query_string)  (ebb_request*, ebb_element*);

  void *data;
};



#endif
