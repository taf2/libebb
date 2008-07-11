
#define EW_MAX_CLIENTS 1024

typedef struct ew_chunk      ew_chunk;
typedef struct ew_server     ew_server;
typedef struct ew_connection ew_connection;
typedef struct ew_request    ew_request;


typedef void (*ew_free_chunk)(ew_chunk *chunk);
struct ew_chunk {
  unsigned char   *ptr;
  unsigned int     len;
  ew_free_chunk    free; 
  void            *data; 
};

typedef ew_connection* (*ew_new_connection_handler)
  ( ew_server *server
  , struct sockaddr_in *sockaddr
  ) 

struct ew_server {
  int fd;
  struct sockaddr_in        sockaddr;
  socklen_t                 socklen;    /* size of sockaddr */ 
  char                      port[8];    /* port as a string */

  struct ev_loop           *loop;

  ev_io                     connection_watcher;
  ew_new_connection_handler new_connection;


  void *data;
};


void ew_server_init
  ( ew_server *server
  , struct ev_loop *loop
  , ew_new_connection_handler handler
  , void *data
  );

int ew_server_listen_on_port
  ( ew_server *server
  , const int port
  );

int ew_server_listen_on_fd
  ( ew_server *server
  , const int sfd 
  );


/********** CONNECTION ******/

struct ew_connection {
  int fd;
  struct sockaddr_in    sockaddr;
  socklen_t             socklen;    /* size of sockaddr */ 

  char *ip;
  unsigned open:1; 
}; 

/********** REQUEST *********/

struct ew_request {
  ew_connection       *connection; 
  ew_headers           headers;
};


/********** RESPONSE ********/
typedef struct ew_response ew_response;
struct ew_response {
  ew_request          *request; 
  ew_connection       *connection; 
};
