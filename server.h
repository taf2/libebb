#define EBB_MAX_CLIENTS 1024
#define EBB_MAX_HEADER_SIZE 1024*8

typedef struct ebb_buf ebb_buf;
typedef struct ebb_server ebb_server;
typedef struct ebb_connection ebb_connection;
typedef struct ebb_request ebb_request;
typedef struct ebb_res ebb_res;


struct ebb_buf {
  unsigned char   *buf;
  size_t len;
  size_t max_len;

  void (*free) (ebb_buf*);
  void (*save) (ebb_buf*);
  void *data; 
};

void ebb_buf_save_finished
  ( ebb_buf *buf
  );

struct ebb_server {
  int fd;                      /* ro */
  struct sockaddr_in sockaddr; /* ro */
  socklen_t socklen;           /* ro */
  char port[6];                /* ro */
  struct ev_loop *loop;        /* ro */
  ev_io connection_watcher;    /* private */
  unsigned listening:1;        /* ro */

  /* public */
  ebb_connection* (*new_connection) (ebb_server*);
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

/********** CONNECTION **********/

struct ebb_connection {
  int fd;                      /* ro */
  struct sockaddr_in sockaddr; /* ro */
  socklen_t socklen;           /* ro */ 
  ebb_server *server            /* ro */
  float timeout;               /* ro */
  char ip[40];                 /* ro */
  unsigned open:1;             /* ro */
  ev_io request_watcher;       /* private */
  ev_io write_watcher;         /* private */
  ev_timer timeout_watcher;    /* private */

  /* public */
  ebb_request* (*new_request) (ebb_connection*);
  void (*free) (ebb_connection*);
  void *data;
};

/********** REQUEST *********/


struct ebb_request {
  ebb_connection *connection;           /* ro */
  request_headers headers;             /* ro */
  char header_buf[EBB_MAX_HEADER_SIZE]; /* ro */
  size_t read;                         /* ro */
  size_t read_body_normal;             /* private */
  unsigned has_read_head:1;            /* ro */
  ev_io read_watcher;                  /* private */

  /* public */
  ebb_buf* (*new_buf)(ebb_request*, size_t needed);
  void (*free) (ebb_request*);
  void *data;
};


/********** RESPONSE ********/
struct ebb_res {
  ebb_request          *request; 
  ebb_connection       *connection; 
};
