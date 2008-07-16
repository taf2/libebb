#include "parser.h"
#include <stdlib.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>



static ebb_parser parser;
struct request_data {
  const char *raw;
  char request_method[500];
  char request_path[500];
  char request_uri[500];
  char fragment[500];
  char query_string[500];
  char body[500];
  int num_headers;
  char* header_fields[500];
  char* header_values[500];
  ebb_parser_request request;
};
static struct request_data requests[5];
static int num_requests;


// get - no headers - no body
const struct request_data req1 =  
  { raw: "GET /req1/world HTTP/1.1\r\n\r\n"
  , request_method: "GET"
  , query_string: ""
  , fragment: ""
  , request_path: "/req1/world"
  , request_uri: "/req1/world"
  , num_headers: 0
  , header_fields: {  }
  , header_values: {  }
  , body: ""
  };

// get - one header - no body
const struct request_data req2 =  
  { raw: "GET /req2 HTTP/1.1\r\nAccept: */*\r\n\r\n"
  , request_method: "GET"
  , query_string: ""
  , fragment: ""
  , request_path: "/req2"
  , request_uri: "/req2"
  , num_headers: 1
  , header_fields: { "Accept" }
  , header_values: { "*/*" }
  , body: ""
  };

// post - one header - no body
const struct request_data req3 =  
  { raw: "POST /req3 HTTP/1.1\r\nAccept: */*\r\n\r\n"
  , request_method: "POST"
  , query_string: ""
  , fragment: ""
  , request_path: "/req3"
  , request_uri: "/req3"
  , num_headers: 1
  , header_fields: { "Accept" }
  , header_values: { "*/*" }
  , body: ""
  };


// get - no headers - body "HELLO"
const struct request_data req4 =  
  { raw: "GET /req4 HTTP/1.1\r\nconTENT-Length: 5\r\n\r\nHELLO"
  , request_method: "GET"
  , query_string: ""
  , fragment: ""
  , request_path: "/req4"
  , request_uri: "/req4"
  , num_headers: 1
  , header_fields: { "conTENT-Length" }
  , header_values: { "5" }
  , body: "HELLO"
  };

// post - one header - body "World"
const struct request_data req5 =  
  { raw: "POST /req5?q=search#hey HTTP/1.1\r\nAccept: */*\r\nContent-Length: 5\r\n\r\nWorld"
  , request_method: "POST"
  , query_string: "q=search"
  , fragment: "hey"
  , request_path: "/req5"
  , request_uri: "/req5?q=search"
  , num_headers: 2
  , header_fields: { "Accept", "Content-Length" }
  , header_values: { "*/*", "5" }
  , body: "World"
  };

// post - no headers - chunked body "all your base are belong to us"
const struct request_data req6 =  
  { raw: "POST /req6 HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n1e\r\nall your base are belong to us\r\n0\r\n\r\n"
  , request_method: "POST"
  , query_string: ""
  , fragment: ""
  , request_path: "/req6"
  , request_uri: "/req6"
  , num_headers: 1
  , header_fields: { "Transfer-Encoding" }
  , header_values: { "chunked" }
  , body: "all your base are belong to us"
  };

// two chunks ; triple zero ending
const struct request_data req7 =  
  { raw: "POST /req7 HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n000\r\n\r\n"
  , request_method: "POST"
  , query_string: ""
  , fragment: ""
  , request_path: "/req7"
  , request_uri: "/req7"
  , num_headers: 1
  , header_fields: { "Transfer-Encoding" }
  , header_values: { "chunked" }
  , body: "hello world"
  };


// chunked with trailing headers. blech.
const struct request_data req8 =  
  { raw: "POST /req8 HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\nVary: *\r\nContent-Type: text/plain\r\n\r\n"
  , request_method: "POST"
  , query_string: ""
  , fragment: ""
  , request_path: "/req8"
  , request_uri: "/req8"
  , num_headers: 1
  , header_fields: { "Transfer-Encoding" }
  , header_values: { "chunked" }
  , body: "hello world"
  };

// with bullshit after the length
const struct request_data req9 =  
  { raw: "POST /req9 HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5; ihatew3;whatthefuck=aretheseparametersfor\r\nhello\r\n6; blahblah; blah\r\n world\r\n0\r\n\r\n"
  , request_method: "POST"
  , query_string: ""
  , fragment: ""
  , request_path: "/req9"
  , request_uri: "/req9"
  , num_headers: 1
  , header_fields: { "Transfer-Encoding" }
  , header_values: { "chunked" }
  , body: "hello world"
  };


int request_data_eq
  ( struct request_data *r1
  , const struct request_data *r2
  )
{ 
  if(0 != strcmp(r1->body, r2->body)) {
    printf("body '%s' != '%s'\n", r1->body, r2->body);
    return FALSE;
  }
  if(0 != strcmp(r1->fragment, r2->fragment)) {
    printf("fragment '%s' != '%s'\n", r1->fragment, r2->fragment);
    return FALSE;
  }
  if(0 != strcmp(r1->query_string, r2->query_string)) {
    printf("query_string '%s' != '%s'\n", r1->query_string, r2->query_string);
    return FALSE;
  }
  if(0 != strcmp(r1->request_method, r2->request_method)) {
    printf("request_method '%s' != '%s'\n", r1->request_method, r2->request_method);
    return FALSE;
  }
  if(0 != strcmp(r1->request_path, r2->request_path)) {
    printf("request_path '%s' != '%s'\n", r1->request_path, r2->request_path);
    return FALSE;
  }
  if(0 != strcmp(r1->request_uri, r2->request_uri)) {
    printf("request_uri '%s' != '%s'\n", r1->request_uri, r2->request_uri);
    return FALSE;
  }
  if(r1->num_headers != r2->num_headers) {
    printf("num_headers '%d' != '%d'\n", r1->num_headers, r2->num_headers);
    return FALSE;
  }
  int i;
  for(i = 0; i < r1->num_headers; i++) {
    if(0 != strcmp(r1->header_fields[i], r2->header_fields[i])) {
      printf("header field '%s' != '%s'\n", r1->header_fields[i], r2->header_fields[i]);
      return FALSE;
    }
    if(0 != strcmp(r1->header_values[i], r2->header_values[i])) {
      printf("header field '%s' != '%s'\n", r1->header_values[i], r2->header_values[i]);
      return FALSE;
    }
  }
  return TRUE;
}

int request_eq
  ( int index
  , const struct request_data *expected
  )
{
  return request_data_eq(&requests[index], expected);
}

ebb_element* new_element ()
{
  ebb_element *el = malloc(sizeof(ebb_element));
  ebb_element_init(el);
  return el;
}

ebb_parser_request* new_request ()
{
  requests[num_requests].num_headers = 0;
  requests[num_requests].request_method[0] = 0;
  requests[num_requests].request_path[0] = 0;
  requests[num_requests].request_uri[0] = 0;
  requests[num_requests].fragment[0] = 0;
  requests[num_requests].query_string[0] = 0;
  requests[num_requests].body[0] = 0;
  ebb_parser_request *r = &requests[num_requests].request;
  ebb_parser_request_init(r);
 // printf("new request %d\n", num_requests);
  return r;
}

void request_complete()
{
 // printf("request complete\n");
  num_requests++;
}

void request_method_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].request_method);
}

void request_path_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].request_path);
}

void request_uri_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].request_uri);
}

void fragment_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].fragment);
}

void header_handler(void *data, ebb_element *field, ebb_element *value)
{
  char *field_s, *value_s;

  field_s = malloc( ebb_element_len(field) );
  ebb_element_strcpy( field, field_s);

  value_s = malloc( ebb_element_len(value) );
  ebb_element_strcpy( value,  value_s);

  int nh = requests[num_requests].num_headers;

  requests[num_requests].header_fields[nh] = field_s;
  requests[num_requests].header_values[nh] = value_s;

  requests[num_requests].num_headers += 1;

 // printf("header %s: %s\n", field_s, value_s);
}


void query_string_cb(void *data, ebb_element *el)
{
  ebb_element_strcpy(el, requests[num_requests].query_string);
}


void chunk_handler(void *data, const char *p, size_t len)
{
  strncat(requests[num_requests].body, p, len);
 // printf("chunk_handler: '%s'\n", requests[num_requests].body);
}

void parser_init()
{
  num_requests = 0;

  ebb_parser_init(&parser);

  parser.new_element = new_element;
  parser.new_request = new_request;
  parser.request_complete = request_complete;
  parser.header_handler = header_handler;
  parser.request_method = request_method_cb;
  parser.request_path = request_path_cb;
  parser.request_uri = request_uri_cb;
  parser.fragment = fragment_cb;
  parser.query_string = query_string_cb;
  parser.chunk_handler = chunk_handler;
}

int test_request
  ( const struct request_data *request_data
  )
{
  size_t traversed = 0;
  parser_init();

  traversed = ebb_parser_execute( &parser
                                , request_data->raw 
                                , strlen(request_data->raw));

  if( ebb_parser_has_error(&parser) )
    return FALSE;
  if(! ebb_parser_is_finished(&parser) )
    return FALSE;
  if(num_requests != 1)
    return FALSE;

  return request_eq(0, request_data);
}

int test_error
  ( const char *buf
  )
{
  size_t traversed = 0;
  parser_init();

  traversed = ebb_parser_execute(&parser, buf, strlen(buf));

  return ebb_parser_has_error(&parser);
}


int test_multiple3
  ( const struct request_data *r1
  , const struct request_data *r2
  , const struct request_data *r3
  )
{
  char total[80*1024] = "\0";

  strcat(total, r1->raw); 
  strcat(total, r2->raw); 
  strcat(total, r3->raw); 

  size_t traversed = 0;
  parser_init();

  traversed = ebb_parser_execute(&parser, total, strlen(total));


  if( ebb_parser_has_error(&parser) )
    return FALSE;
  if(! ebb_parser_is_finished(&parser) )
    return FALSE;
  if(num_requests != 3)
    return FALSE;

  return request_eq(0, r1) &&
         request_eq(1, r2) &&
         request_eq(2, r3);
}

/**
 * SCAN through every possible breaking to make sure the 
 * parser can handle getting the content in any chunks that
 * might come from the socket
 */
int test_scan2
  ( const struct request_data *r1
  , const struct request_data *r2
  , const struct request_data *r3
  )
{
  char total[80*1024] = "\0";
  char buf1[80*1024] = "\0";
  char buf2[80*1024] = "\0";

  strcat(total, r1->raw); 
  strcat(total, r2->raw); 
  strcat(total, r3->raw); 

  int total_len = strlen(total);

  //printf("total_len = %d\n", total_len);
  int i;
  for(i = 1; i < total_len - 1; i ++ ) {

    parser_init();


    int buf1_len = i;
    strncpy(buf1, total, buf1_len);
    buf1[buf1_len] = 0;

    int buf2_len = total_len - i;
    strncpy(buf2, total+i, buf2_len);
    buf2[buf2_len] = 0;

    ebb_parser_execute(&parser, buf1, buf1_len);

    if( ebb_parser_has_error(&parser) ) {
      return FALSE;
    }
    /*
    if(ebb_parser_is_finished(&parser)) 
      return FALSE;
    */

    ebb_parser_execute(&parser, buf2, buf2_len);

    if( ebb_parser_has_error(&parser))
      return FALSE;
    if(!ebb_parser_is_finished(&parser)) 
      return FALSE;

    if(3 != num_requests) {
      printf("scan error: got %d requests in iteration %d\n", num_requests, i);
      return FALSE;
    }

    if(!request_eq(0, r1)) {
      printf("not maching r1\n");
      return FALSE;
    }
    if(!request_eq(1, r2)) {
      printf("not maching r2\n");
      return FALSE;
    }
    if(!request_eq(2, r3)) {
      printf("not maching r3\n");
      return FALSE;
    }
  }
  return TRUE;
}

int test_scan3
  ( const struct request_data *r1
  , const struct request_data *r2
  , const struct request_data *r3
  )
{
  char total[80*1024] = "\0";
  char buf1[80*1024] = "\0";
  char buf2[80*1024] = "\0";
  char buf3[80*1024] = "\0";

  strcat(total, r1->raw); 
  strcat(total, r2->raw); 
  strcat(total, r3->raw); 

  int total_len = strlen(total);

  //printf("total_len = %d\n", total_len);
  int i,j;
  for(j = 2; j < total_len - 1; j ++ ) {
    for(i = 1; i < j; i ++ ) {

      parser_init();



      int buf1_len = i;
      strncpy(buf1, total, buf1_len);
      buf1[buf1_len] = 0;

      int buf2_len = j - i;
      strncpy(buf2, total+i, buf2_len);
      buf2[buf2_len] = 0;

      int buf3_len = total_len - j;
      strncpy(buf3, total+j, buf3_len);
      buf3[buf3_len] = 0;

      /*
      printf("buf1: %s - %d\n", buf1, buf1_len);
      printf("buf2: %s - %d \n", buf2, buf2_len );
      printf("buf3: %s - %d\n\n", buf3, buf3_len);
      */

      ebb_parser_execute(&parser, buf1, buf1_len);

      if( ebb_parser_has_error(&parser) ) {
        return FALSE;
      }

      ebb_parser_execute(&parser, buf2, buf2_len);

      if( ebb_parser_has_error(&parser) ) {
        return FALSE;
      }

      ebb_parser_execute(&parser, buf3, buf3_len);

      if( ebb_parser_has_error(&parser))
        return FALSE;
      if(!ebb_parser_is_finished(&parser)) 
        return FALSE;

      if(3 != num_requests) {
        printf("scan error: only got %d requests in iteration %d\n", num_requests, i);
        return FALSE;
      }

      if(!request_eq(0, r1)) {
        printf("not maching r1\n");
        return FALSE;
      }
      if(!request_eq(1, r2)) {
        printf("not maching r2\n");
        return FALSE;
      }
      if(!request_eq(2, r3)) {
        printf("not maching r3\n");
        return FALSE;
      }
    }
  }
  return TRUE;
}

#define break_output printf("test_break error.\ni: %d\nbuf1: %s\nbuf2: %s\n", i, buf1, buf2)

#define assert_req_str_eql(num, FIELD, expected)  \
  assert(0 == strcmp(requests[num].FIELD, expected))

int main() 
{

  assert(test_error("hello world"));
  assert(test_error("GET / HTP/1.1\r\n\r\n"));

  // Zed's header tests

  const char *dumbfuck = "GET / HTTP/1.1\r\naaaaaaaaaaaaa:++++++++++\r\n\r\n";
  assert(!test_error(dumbfuck));
  assert(1 == num_requests);
  assert_req_str_eql(0, body, "");
  assert_req_str_eql(0, fragment, "");
  assert_req_str_eql(0, query_string, "");
  assert_req_str_eql(0, request_method, "GET");
  assert_req_str_eql(0, request_path, "/");
  assert(1 == requests[0].request.version_major);
  assert(1 == requests[0].request.version_minor);
  assert(1 == requests[0].num_headers);
  assert_req_str_eql(0, header_fields[0], "aaaaaaaaaaaaa");
  assert_req_str_eql(0, header_values[0], "++++++++++");

  const char *dumbfuck2 = "GET / HTTP/1.1\r\nX-SSL-Bullshit:   -----BEGIN CERTIFICATE-----\r\n\tMIIFbTCCBFWgAwIBAgICH4cwDQYJKoZIhvcNAQEFBQAwcDELMAkGA1UEBhMCVUsx\r\n\tETAPBgNVBAoTCGVTY2llbmNlMRIwEAYDVQQLEwlBdXRob3JpdHkxCzAJBgNVBAMT\r\n\tAkNBMS0wKwYJKoZIhvcNAQkBFh5jYS1vcGVyYXRvckBncmlkLXN1cHBvcnQuYWMu\r\n\tdWswHhcNMDYwNzI3MTQxMzI4WhcNMDcwNzI3MTQxMzI4WjBbMQswCQYDVQQGEwJV\r\n\tSzERMA8GA1UEChMIZVNjaWVuY2UxEzARBgNVBAsTCk1hbmNoZXN0ZXIxCzAJBgNV\r\n\tBAcTmrsogriqMWLAk1DMRcwFQYDVQQDEw5taWNoYWVsIHBhcmQYJKoZIhvcNAQEB\r\n\tBQADggEPADCCAQoCggEBANPEQBgl1IaKdSS1TbhF3hEXSl72G9J+WC/1R64fAcEF\r\n\tW51rEyFYiIeZGx/BVzwXbeBoNUK41OK65sxGuflMo5gLflbwJtHBRIEKAfVVp3YR\r\n\tgW7cMA/s/XKgL1GEC7rQw8lIZT8RApukCGqOVHSi/F1SiFlPDxuDfmdiNzL31+sL\r\n\t0iwHDdNkGjy5pyBSB8Y79dsSJtCW/iaLB0/n8Sj7HgvvZJ7x0fr+RQjYOUUfrePP\r\n\tu2MSpFyf+9BbC/aXgaZuiCvSR+8Snv3xApQY+fULK/xY8h8Ua51iXoQ5jrgu2SqR\r\n\twgA7BUi3G8LFzMBl8FRCDYGUDy7M6QaHXx1ZWIPWNKsCAwEAAaOCAiQwggIgMAwG\r\n\tA1UdEwEB/wQCMAAwEQYJYIZIAYb4QgEBBAQDAgWgMA4GA1UdDwEB/wQEAwID6DAs\r\n\tBglghkgBhvhCAQ0EHxYdVUsgZS1TY2llbmNlIFVzZXIgQ2VydGlmaWNhdGUwHQYD\r\n\tVR0OBBYEFDTt/sf9PeMaZDHkUIldrDYMNTBZMIGaBgNVHSMEgZIwgY+AFAI4qxGj\r\n\tloCLDdMVKwiljjDastqooXSkcjBwMQswCQYDVQQGEwJVSzERMA8GA1UEChMIZVNj\r\n\taWVuY2UxEjAQBgNVBAsTCUF1dGhvcml0eTELMAkGA1UEAxMCQ0ExLTArBgkqhkiG\r\n\t9w0BCQEWHmNhLW9wZXJhdG9yQGdyaWQtc3VwcG9ydC5hYy51a4IBADApBgNVHRIE\r\n\tIjAggR5jYS1vcGVyYXRvckBncmlkLXN1cHBvcnQuYWMudWswGQYDVR0gBBIwEDAO\r\n\tBgwrBgEEAdkvAQEBAQYwPQYJYIZIAYb4QgEEBDAWLmh0dHA6Ly9jYS5ncmlkLXN1\r\n\tcHBvcnQuYWMudmT4sopwqlBWsvcHViL2NybC9jYWNybC5jcmwwPQYJYIZIAYb4QgEDBDAWLmh0\r\n\tdHA6Ly9jYS5ncmlkLXN1cHBvcnQuYWMudWsvcHViL2NybC9jYWNybC5jcmwwPwYD\r\n\tVR0fBDgwNjA0oDKgMIYuaHR0cDovL2NhLmdyaWQt5hYy51ay9wdWIv\r\n\tY3JsL2NhY3JsLmNybDANBgkqhkiG9w0BAQUFAAOCAQEAS/U4iiooBENGW/Hwmmd3\r\n\tXCy6Zrt08YjKCzGNjorT98g8uGsqYjSxv/hmi0qlnlHs+k/3Iobc3LjS5AMYr5L8\r\n\tUO7OSkgFFlLHQyC9JzPfmLCAugvzEbyv4Olnsr8hbxF1MbKZoQxUZtMVu29wjfXk\r\n\thTeApBv7eaKCWpSp7MCbvgzm74izKhu3vlDk9w6qVrxePfGgpKPqfHiOoGhFnbTK\r\n\twTC6o2xq5y0qZ03JonF7OJspEd3I5zKY3E+ov7/ZhW6DqT8UFvsAdjvQbXyhV8Eu\r\n\tYhixw1aKEPzNjNowuIseVogKOLXxWI5vAi5HgXdS0/ES5gDGsABo4fqovUKlgop3\r\n\tRA==\r\n\t-----END CERTIFICATE-----\r\n\r\n";
  assert(test_error(dumbfuck2));

  const char *fragment_in_uri = "GET /forums/1/topics/2375?page=1#posts-17408 HTTP/1.1\r\n\r\n";
  assert(!test_error(fragment_in_uri));
  assert_req_str_eql(0, fragment, "posts-17408");
  assert_req_str_eql(0, query_string, "page=1");
  assert_req_str_eql(0, request_method, "GET");
  assert_req_str_eql(0, request_path, "/forums/1/topics/2375");
  /* XXX request uri does not include fragment? */
  assert_req_str_eql(0, request_uri, "/forums/1/topics/2375?page=1");


  /* TODO sending junk and large headers gets rejected */


  /* check to make sure our predefined requests are okay */

  assert(test_request(&req1));
  assert(test_request(&req2));
  assert(test_request(&req3));

  // no content-length
  const char *bad_req1 = "GET /bad_req1/world HTTP/1.1\r\nAccept: */*\r\nHELLO\r\n";
  assert(test_error(bad_req1)); // error if there is a body without content length

  assert(test_request(&req4));
  assert(test_request(&req5));
  assert(test_request(&req6));
  assert(test_request(&req7));
  assert(test_request(&req8));

  assert(test_request(&req9));
  assert(1 == requests[0].request.version_major); 
  assert(1 == requests[0].request.version_minor);



  // three requests - no bodies
  assert(test_multiple3(&req1, &req2, &req3));

  // three requests - one body
  assert( test_multiple3(&req1, &req4, &req3));

  // three requests with bodies -- last is chunked
  assert( test_multiple3(&req4, &req5, &req6));

  // three chunked requests
  assert( test_multiple3(&req7, &req6, &req8));


  assert(test_scan2(&req1, &req2, &req3));
  assert(test_scan2(&req4, &req5, &req6));
  assert(test_scan2(&req7, &req8, &req9));

  assert(test_scan3(&req1, &req2, &req3));
  assert(test_scan3(&req4, &req5, &req6));
  assert(test_scan3(&req7, &req8, &req9));


  printf("okay\n");
  return 0;
}

