
#define EW_MAX_CLIENTS 1024
#define EW_MAX_HEADER_SIZE 1024*8

typedef struct ew_buf      ew_buf;
typedef struct ew_server     ew_server;
typedef struct ew_connection ew_connection;
typedef struct ew_req    ew_req;


typedef void (*ew_buf_handler)(ew_buf *buf);
struct ew_buf {
  unsigned char   *buf;
  unsigned int     len;
  unsigned int     max_len;


  ew_buf_handler  free; 
  ew_buf_handler  save;  // return EW_FINISHED or EW_NOT_FINISHED
  void            *data; 

  // must be called when save is finished if EW_NOT_FINSIHED
  // was returned 
  ew_buf_handler  save_finished;  

};

typedef ew_connection* (*ew_connection_handler)
  ( ew_server *server
  , struct sockaddr_in *sockaddr
  ); 

struct ew_server {
  int fd;
  struct sockaddr_in        sockaddr;
  socklen_t                 socklen;    /* size of sockaddr */ 
  char                      port[8];    /* port as a string */

  struct ev_loop           *loop;

  ev_io                     connection_watcher;
  ew_connection_handler     connection_handler;

  void *data;
};


void ew_server_init
  ( ew_server *server
  , struct ev_loop *loop
  , ew_connection_handler handler
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

typedef ew_req* (*ew_req_handler) (ew_connection *connection);

struct ew_connection {
  int                   fd;
  struct sockaddr_in    sockaddr;
  socklen_t             socklen;    /* size of sockaddr */ 
  ew_server            *server

  float timeout;
  char *ip;
  unsigned open:1; 

  ew_req_handler   req_handler;

  void *data;
}; 

/********** REQUEST *********/

typedef ew_buf* (*ew_buf_get) (ew_req *req, size_t needed);
typedef void    (*ew_buf_save) (ew_buf *buf);

struct ew_req {
  ew_connection *connection; 
  ew_req_headers headers;

  char header_buf[EW_MAX_HEADER_SIZE];

  ew_buf *body;

  unsigned int read;

  unsigned has_read_head:1;
};


/********** RESPONSE ********/
typedef struct ew_res ew_res;
struct ew_res {
  ew_req          *req; 
  ew_connection       *connection; 
};
