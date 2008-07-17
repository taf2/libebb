#ifndef server_h
#define server_h

#include "request_parser.h"
#include <ev.h>
#include <sys/socket.h>
#include <netinet/in.h>
#define EBB_MAX_CLIENTS 1024

#define EBB_AGAIN 0
#define EBB_STOP 1

typedef struct ebb_buf        ebb_buf;
typedef struct ebb_server     ebb_server;
typedef struct ebb_connection ebb_connection;

struct ebb_buf {
  char *base;
  size_t len;
  void (*free)(ebb_buf*);
};

struct ebb_server {
  int fd;                      /* ro */
  struct sockaddr_in sockaddr; /* ro */
  socklen_t socklen;           /* ro */
  char port[6];                /* ro */
  struct ev_loop *loop;        /* ro */
  ev_io connection_watcher;    /* private */
  unsigned listening:1;        /* ro */

  /* Public */
  ebb_connection* (*new_connection) (ebb_server*, struct sockaddr_in*);
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
  
  /* Public */
  ebb_request_parser parser;  /* don't forget to set the callbacks here */
  ebb_buf* (*new_buf) (ebb_connection*); 
  int (*on_writable) (ebb_connection*); /* Returns EBB_STOP or EBB_AGAIN */
  int (*on_timeout) (ebb_connection*); /* Returns EBB_STOP or EBB_AGAIN */
  void (*free) (ebb_connection*);
  void *data;
};

void ebb_connection_init
  ( ebb_connection *connection
  , float timeout
  );

void ebb_connection_close
  ( ebb_connection *
  );

void ebb_connection_start_write_watcher 
  ( ebb_connection *
  );

#endif
