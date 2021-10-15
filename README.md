# Tiny HTTPd

Tiny HTTPd 是一个超轻量型 HTTP Server

https://sourceforge.net/projects/tinyhttpd/

## 工作流程

- 服务器启动，在指定端口或随机选取端口绑定 httpd 服务。

- 收到一个 HTTP 请求时（其实就是 listen 的端口 accpet 的时候），派生一个线程运行 accept_request 函数。

- 取出 HTTP 请求中的 method (GET 或 POST) 和 url。对于 GET 方法，如果有携带参数，则 query_string 指针指向 url 中 ？ 后面的 GET 参数。

- 格式化 url 到 path 数组，表示浏览器请求的服务器文件路径，在 tiny_httpd 中服务器文件是在 www 文件夹下。当 url 以 / 结尾，或 url 是个目录，则默认在 path 中加上 index.html，表示访问主页。

- 如果文件路径合法，对于无参数的 GET 请求，直接输出服务器文件到浏览器，即用 HTTP 格式写到套接字上，跳到（10）。其他情况（带参数 GET，POST 方式，url 为可执行文件），则调用 excute_cgi 函数执行 cgi 脚本。

- 读取整个 HTTP 请求并丢弃headers，如果是 POST 则找出 Content-Length. 把 HTTP 200  状态码写到套接字。

- 建立两个管道，cgi_input 和 cgi_output, 并 fork 一个进程。

- 在子进程中，把 STDOUT 重定向到 cgi_output 的写入端，把 STDIN 重定向到 cgi_input 的读取端，关闭 cgi_input 的写入端 和 cgi_output 的读取端，设置 request_method 的环境变量，GET 的话设置 query_string 的环境变量，POST 的话设置 content_length 的环境变量，这些环境变量都是为了给 cgi 脚本调用，接着用 execl 运行 cgi 程序。

- 在父进程中，关闭 cgi_input 的读取端 和 cgi_output 的写入端，如果 POST 的话，把 POST 数据写入 cgi_input，已被重定向到 STDIN，读取 cgi_output 的管道输出到客户端，该管道输入是 STDOUT。接着关闭所有管道，等待子进程结束。

- 关闭与浏览器的连接，完成了一次 HTTP 请求与回应。

## 每个函数的作用

```c
// 处理从套接字上监听到的一个HTTP请求
void accept_request(void *);
// 返回客户端这是个错误的请求，状态码400
void bad_request(int);
// 读取某个文件写到socket套接字
void cat(int, FILE *);
// 处理执行cgi程序时的错误
void cannot_execute(int);
// 把错误信息写到perror并退出
void error_die(const char *);
// 执行cgi程序
void execute_cgi(int, const char *, const char *, const char *);
// 读取套接字的一行，把回车换行等情况都统一为换行符结束
int get_line(int, char *, int);
// 把HTTP响应的头部写到套接字
void headers(int, const char *);
// 请求的资源不存在
void not_found(int);
// 调用cat把文件返回给浏览器
void serve_file(int, const char *);
// 初始化httpd
int startup(u_short *);
// method不被支持
void unimplemented(int);
```

 main --> startup --> accept_request --> execute_cgi

## 管道相关知识

```c
int pipe(int pipefd[2]);
```

pipe函数的功能是创建一个用于进程间通信的通道。数组pipefd返回所创建管道的两个文件描述符，其中pipefd[0]表示管道的读端，而pipefd[1]表示管道的写端。从写端写入到管道中的数据由内核进行缓存，直到有进程从读端将数据读出。

pipe函数是基于文件描述符工作的，所以在使用pipe创建的管道要使用read和write调用来读取和发送数据。

另外，管道的读、写行为和一般文件也不相同。当一个进程使用read读取一个空管道时，read会阻塞，直到管道中有数据被写入；当一个进程试图向一个满的管道写入数据时，write将会被阻塞，直到足够多的数据被从管道中读取，write可以将数据全部写入管道中。

```c
// 与pipe函数经常一起使用的还有dup、dup2函数
int dup(int oldfd);
int dup2(int oldfd, int newfd);
```

两个函数的主要功能都是实现对oldfd文件描述符的复制。其中dup函数使用所有文件描述符中未使用的最小的编号作为新的描述符，而dup2则使用传入的newfd作为oldfd的副本。



## 套接字相关知识

一个套接字就类似于一扇门。当门打开，外面的人可以通过门进到房子里来，里面的人也可以通过门出去。当门关闭时，就拒绝了和外界的交往。如果两个人互相朝对方打开了一扇门，那么他们之间就建立了联系（连接），彼此就可以相互交流（通信）.

```c
int socket(int domain, int type, int protocol);
```

domain参数是套接字的域（协议簇）

type指定套接字的类型，决定了套接字所采用的通信机制

protocol指定通信所用的协议，一般由套接字域和类型来决定，一般将其设置为0，表示使用默认协议

```c
int bind(int socket, const struct sockaddr *address, size_t address_len);
```

socket 是所要命名的套接字的标识符，address为要绑定的地址，address_len为地址结构的长度。

`注意：在这里，需要将一个特定的地址结构指针转换为通用地址类型（struct sockaddr *）`

```c
int listen(int socket, int backlog);
```

listen函数会创建一个队列来缓存未处理的连接，其中，socket是服务套接字的标识符。backlog为连接队列的最大长度（因为Linux系统通常会对队列中的最大连接数有所限制），当队列中的连接数超过这个值时，后续的连接将被拒绝。backlog参数通常设为5

```c
int accept(int socket, struct sockaddr *address, size_t *address_len);
```

只有当监听队列中第一个未处理的连接试图连接到由socket参数指定的服务套接字时，函数才返回。accept函数会创建一个新的套接字来与所接受的客户进行通信，并返回新套接字的描述符。新套接字类型与服务套接字类型是一样的。

address参数所指向的sockaddr结构用于存放连接客户的地址，如果程序不需要客户地址，也可以将该参数设为空指针。address_len参数用以指定客户地址结构的长度。如果客户地址长度超过这个值，它将被截断，因此在调用accept之前必须将address_len设置为足够的长度。当函数返回时，address_len将被设置为客户地址结构的实际长度。

如果监听队列中没有未处理的连接，accept函数将阻塞，程序暂停执行，直到有客户连接上为止。当有未处理的客户连接时，accept函数返回一个新套接字的描述符。发生错误时，返回-1。

```c
int close(int socket);
```

通过调用close函数关闭客户套接字sock，与服务器套接字的连接也自然关闭。其中socket是要关闭的套接字标识符。函数成功时返回0，失败时返回-1。

