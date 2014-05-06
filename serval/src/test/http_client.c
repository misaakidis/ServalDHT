/* -*- Mode: C++; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 8 -*- */
// Copyright (c) 2014 Marios Isaakidis (misaakidis@yahoo.gr)

// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and/or hardware specification (the “Work”) to deal
// in the Work without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Work, and to permit persons to whom the Work is
// furnished to do so, subject to the following conditions: The above
// copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Work.

// THE WORK IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
// OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE WORK OR THE USE OR OTHER
// DEALINGS IN THE WORK.
#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <errno.h>
#include <netinet/serval.h>
#include <libserval/serval.h>

static const char *progname = "http_client";
static unsigned short DEFAULT_SERVER_SID = 80;
static struct service_id server_srvid;
static char *page = "/";
static char *host = "127.0.0.1";
char *get;
char buf[BUFSIZ+1];

#define USERAGENT "HTMLGET 1.0"

static void signal_handler(int sig)
{
        switch (sig) {
        case SIGHUP:
                printf("Doing failover\n");
                break;
                // kill -TERM requests graceful termination (may hang if
                // in syscall in which case a subsequent SIGINT is reqd.
        case SIGTERM:
                printf("signal term caught! exiting...\n");
                //should_exit = 1;
                break;
                // ctrl-c does abnormal termination
        case SIGINT:
                printf("abnormal termination! exiting..\n");
                signal(sig, SIG_DFL);
                raise(sig);
                break;
        default:
                printf("unknown signal");
                signal(sig, SIG_DFL);
                raise(sig);
                break;
        }
}

static int set_reuse_ok(int soc)
{
	int option = 1;

	if (setsockopt(soc, SOL_SOCKET, SO_REUSEADDR,
			&option, sizeof(option)) < 0) {
		fprintf(stderr, "proxy setsockopt error");
		return -1;
	}

	return 0;
}

char *build_get_query()
{
	char *query;
	char *getpage = page;
	char *tpl = "GET /%s HTTP/1.0\r\nHost: %s\r\nUser-Agent: %s\r\n\r\n";
	if(getpage[0] == '/'){
		getpage = getpage + 1;
		fprintf(stderr,"Removing leading \"/\", converting %s to %s\n", page, getpage);
	}
	// -5 is to consider the %s %s %s in tpl and the ending \0
	query = (char *)malloc(strlen(host)+strlen(getpage)+strlen(USERAGENT)+strlen(tpl)-5);
	sprintf(query, tpl, getpage, host, USERAGENT);
	return query;
}

int send_httpget_req(int sock) {
	//Send the query to the server
	int sent = 0;
	int tmpres = 0;
	while(sent < strlen(get))
	{
		tmpres = send_sv(sock, get+sent, strlen(get)-sent, 0);
		if(tmpres == -1){
			perror("Can't send query");
			exit(1);
		}
		sent += tmpres;
	}
	//now it is time to receive the page
	memset(buf, 0, sizeof(buf));
	int htmlstart = 0;
	char * htmlcontent;
	while((tmpres = recv_sv(sock, buf, BUFSIZ, 0)) > 0){
		if(htmlstart == 0)
		{
			/* Under certain conditions this will not work.
			 * If the \r\n\r\n part is splitted into two messages
			 * it will fail to detect the beginning of HTML content
			 */
			htmlcontent = strstr(buf, "\r\n\r\n");
			if(htmlcontent != NULL){
				htmlstart = 1;
				htmlcontent += 4;
			}
		}else{
			htmlcontent = buf;
		}
		if(htmlstart){
			fprintf(stdout, htmlcontent);
		}

		memset(buf, 0, tmpres);
	}
	if(tmpres < 0)
	{
		perror("Error receiving data");
	}
	return 0;
}

static int client(struct in_addr *srv_inetaddr, int port)
{
	int sock, ret = EXIT_FAILURE;
	union {
		struct sockaddr_sv serval;
		struct sockaddr_in inet;
		struct sockaddr saddr;
	} cliaddr, srvaddr;
	socklen_t addrlen = 0;
	unsigned short srv_inetport = (unsigned short)port;
	int family = AF_SERVAL;

	memset(&cliaddr, 0, sizeof(cliaddr));
	memset(&srvaddr, 0, sizeof(srvaddr));

	if (srv_inetaddr) {
		family = AF_INET;
		cliaddr.inet.sin_family = family;
		cliaddr.inet.sin_port = htons(6767);
		srvaddr.inet.sin_family = family;
		srvaddr.inet.sin_port = htons(srv_inetport);
		memcpy(&srvaddr.inet.sin_addr, srv_inetaddr,
				sizeof(*srv_inetaddr));
		addrlen = sizeof(cliaddr.inet);
	} else {
		cliaddr.serval.sv_family = family;
		cliaddr.serval.sv_srvid.s_sid32[0] = htonl(getpid());
		srvaddr.serval.sv_family = AF_SERVAL;
		memcpy(&srvaddr.serval.sv_srvid,
				&server_srvid, sizeof(server_srvid));
		addrlen = sizeof(cliaddr.serval);
		/* srvaddr.sv_flags = SV_WANT_FAILOVER; */
	}

	sock = socket_sv(family, SOCK_STREAM, 0);

	set_reuse_ok(sock);

	if (family == AF_SERVAL) {
		ret = bind_sv(sock, &cliaddr.saddr, addrlen);

		if (ret < 0) {
			fprintf(stderr, "error client binding socket: %s\n",
					strerror_sv(errno));
			goto out;
		}
	}

	if (family == AF_INET) {
		char buf[18];
		printf("Connecting to service %s:%u\n",
				inet_ntop(family, srv_inetaddr, buf, 18),
				srv_inetport);
	} else {
		printf("Connecting to service id %s\n",
				service_id_to_str(&srvaddr.serval.sv_srvid));
	}
	ret = connect_sv(sock, &srvaddr.saddr, addrlen);

	if (ret < 0) {
		fprintf(stderr, "ERROR connecting: %s\n",
				strerror_sv(errno));
		goto out;
	}
#if defined(SERVAL_NATIVE)
	{
		struct {
			struct sockaddr_sv sv;
			struct sockaddr_in in;
		} saddr;
		socklen_t addrlen = sizeof(saddr.in);
		char ipaddr[18];

		memset(&saddr, 0, sizeof(saddr));

		ret = getsockname(sock, (struct sockaddr *)&saddr, &addrlen);

		if (ret == -1) {
			fprintf(stderr, "Could not get sock name : %s\n",
					strerror(errno));
		} else {
			printf("sock name is %s @ %s\n",
					service_id_to_str(&saddr.sv.sv_srvid),
					inet_ntop(AF_INET, &saddr.in.sin_addr,
							ipaddr, 18));
		}

		memset(&saddr, 0, sizeof(saddr));

		ret = getpeername(sock, (struct sockaddr *)&saddr, &addrlen);

		if (ret == -1) {
			fprintf(stderr, "Could not get peer name : %s\n",
					strerror(errno));
		} else {
			printf("peer name is %s @ %s\n",
					service_id_to_str(&saddr.sv.sv_srvid),
					inet_ntop(AF_INET, &saddr.in.sin_addr,
							ipaddr, 18));
		}
	}
#endif
	printf("Connected successfully!\n");

	//ret = recv_file(sock, filepath, digest);
	get = build_get_query();
	ret = send_httpget_req(sock);

	if (ret == EXIT_SUCCESS) {
		printf("Success\n");
	} else {
		printf("Receive failed\n");
	}
	out:
	fprintf(stderr, "Closing socket...\n");
	close_sv(sock);

	return ret;
}

static void print_help()
{
	printf("Usage: %s [OPTIONS]\n", progname);
	printf("-h, --help                        - Print this information.\n"
			"-s, --serviceid SERVICE_ID        - ServiceID to connect to.\n"
			"-i, --inet IP_ADDR                - Use AF_INET\n");
}

static int parse_inet_str(char *inet_str,
		struct in_addr *ip, int *port)
{
	if (!ip)
		return -1;

	if (port) {
		char *p;
		char *save;
		/* Find out whether there is a port number */
		p = strtok_r(inet_str, ":", &save);

		printf("parsing %s p=%c\n", inet_str, *p);

		if (!p)
			goto out;

		p = strtok_r(NULL, ":", &save);

		if (p != NULL && p != inet_str)
			*port = atoi(p);
	}
	out:
	return inet_pton(AF_INET, inet_str, ip) == 1;
}

int main(int argc, char **argv)
{
	struct sigaction action;

	struct in_addr srv_inetaddr;
	int port = DEFAULT_SERVER_SID;
	int family = AF_SERVAL;

	server_srvid.s_sid32[0] = htonl(DEFAULT_SERVER_SID);

	memset (&action, 0, sizeof(struct sigaction));
	action.sa_handler = signal_handler;

	/* This server should shut down on these signals. */
	sigaction(SIGTERM, &action, 0);
	sigaction(SIGHUP, &action, 0);
	sigaction(SIGINT, &action, 0);

	progname = argv[0];
	argc--;
	argv++;

	while (argc && argv) {
		if (strcmp("-i", argv[0]) == 0 ||
				strcmp("--inet", argv[0]) == 0) {
			if (argv[1] &&
					parse_inet_str(argv[1],
							&srv_inetaddr, &port) == 1) {
				family = AF_INET;
				argc--;
				argv++;
			}
		} else if (strcmp("-h", argv[0]) == 0 ||
				strcmp("--help", argv[0]) == 0) {
			print_help();
			return EXIT_SUCCESS;
		} else if (strcmp("-s", argv[0]) == 0 ||
				strcmp("--serviceid", argv[0]) == 0) {
			char *endptr = NULL;
			unsigned long sid = strtoul(argv[1], &endptr, 10);

			if (*endptr != '\0') {
				fprintf(stderr, "invalid service id %s",
						argv[1]);
				return EXIT_FAILURE;
			} else  {
				server_srvid.s_sid32[0] = htonl(sid);
			}
			argc--;
			argv++;
		} else if (strcmp("-page", argv[0]) == 0 ||
				strcmp("--page", argv[0]) == 0) {
			if (argv[1]) {
				page = argv[1];
				argc--;
				argv++;
			}
		}else {
			print_help();
			return EXIT_FAILURE;
		}
		argc--;
		argv++;
	}

	return client(family == AF_INET ? &srv_inetaddr : NULL, port);
}
