#define EW_MAX_CLIENTS 1024
#define EW_MAX_HEADER_SIZE 1024*8

typedef struct ew_buf ew_buf;
typedef struct ew_server ew_server;
typedef struct ew_connection ew_connection;
typedef struct ew_request ew_request;
typedef struct ew_res ew_res;


struct ew_buf {
  unsigned char   *buf;
  size_t len;
  size_t max_len;

  void (*free) (ew_buf*);
  void (*save) (ew_buf*);
  void *data; 
};

void ew_buf_save_finished
  ( ew_buf *buf
  );

struct ew_server {
  int fd;                      /* ro */
  struct sockaddr_in sockaddr; /* ro */
  socklen_t socklen;           /* ro */
  char port[6];                /* ro */
  struct ev_loop *loop;        /* ro */
  ev_io connection_watcher;    /* private */
  unsigned listening:1;        /* ro */

  /* public */
  ew_connection* (*new_connection) (ew_server*);
  void (*free) (ew_server*);
  void *data;
};


void ew_server_init
  ( ew_server *server
  , struct ev_loop *loop
  );

int ew_server_listen_on_port
  ( ew_server *server
  , const int port
  );

int ew_server_listen_on_fd
  ( ew_server *server
  , const int sfd 
  );

void ew_server_unlisten
  ( ew_server *server
  );

/********** CONNECTION **********/

struct ew_connection {
  int fd;                      /* ro */
  struct sockaddr_in sockaddr; /* ro */
  socklen_t socklen;           /* ro */ 
  ew_server *server            /* ro */
  float timeout;               /* ro */
  char ip[40];                 /* ro */
  unsigned open:1;             /* ro */
  ev_io request_watcher;       /* private */
  ev_io write_watcher;         /* private */
  ev_timer timeout_watcher;    /* private */

  /* public */
  ew_request* (*new_request) (ew_connection*);
  void (*free) (ew_connection*);
  void *data;
};

/********** REQUEST *********/


struct ew_request {
  ew_connection *connection;           /* ro */
  request_headers headers;             /* ro */
  char header_buf[EW_MAX_HEADER_SIZE]; /* ro */
  size_t read;                         /* ro */
  size_t read_body_normal;             /* private */
  unsigned has_read_head:1;            /* ro */
  ev_io read_watcher;                  /* private */

  /* public */
  ew_buf* (*new_buf)(ew_request*, size_t needed);
  void (*free) (ew_request*);
  void *data;
};


/********** RESPONSE ********/
struct ew_res {
  ew_request          *request; 
  ew_connection       *connection; 
};
