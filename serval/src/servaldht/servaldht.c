/*
 * A distributed service resolution service for the serval
 * architecture.
 *
 * Authors: Marios Isaakidis <misaakidis@yahoo.gr>
 *
 *
 *	This program is free software; you can redistribute it and/or
 *	modify it under the terms of the GNU General Public License as
 *	published by the Free Software Foundation; either version 2 of
 *	the License, or (at your option) any later version.
 */

#if defined(__linux__)
#define OS_LINUX 1
#define OS_UNIX 1
#if defined(ANDROID)
#define OS_ANDROID 1
#endif
#endif /* OS_LINUX */

#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>
#include <libgen.h>
#include <asm/types.h>
#include <sys/socket.h>
#include <linux/netlink.h>

//sha256sum of "ServalDHT" is 1ecc0d5cbe78dd18fcb75be4902ad17b148a7cfbf3a72270771d3231391d75e1
//alternatively, 53 is the default port of DNS servers and could be used as service id.
#define ServalDHT_srv_id 53
#define NETLINK_SERVAL 17

int nltest_recvmsg(int sock)
{
	int len;
	char buf[4096];
	struct iovec iov = { buf, sizeof(buf) };
	struct sockaddr_nl sa;
	struct msghdr msg = { (void *)&sa, sizeof(sa), &iov, 1, NULL, 0, 0 };
	struct nlmsghdr *nh = (struct nlmsghdr *)buf;

	len = recvmsg(sock, &msg, 0);

	for (; NLMSG_OK(nh, len); nh = NLMSG_NEXT(nh, len)) {
		switch (nh->nlmsg_type) {
		case NLMSG_DONE:
			printf("NLMSG_DONE\n");
			break;
		case NLMSG_ERROR:
		{
			struct nlmsgerr *nlmerr = (struct nlmsgerr *)NLMSG_DATA(nh);
			if (nlmerr->error == 0) {
				printf("NLMSG_ACK\n");
			} else {
				printf("NLMSG_ERROR\n");
			}
			break;
		}
		default:
			printf("NLMSG type %d\n", nh->nlmsg_type);
		}
	}

	return len;
}

int nltest_sendmsg(int sock, struct nlmsghdr *nh)
{
	struct sockaddr_nl sa;
	struct iovec iov = { (void *) nh, nh->nlmsg_len };
	struct msghdr msg = { (void *)&sa, sizeof(sa), &iov, 1, NULL, 0, 0 };
	static int sequence_number = 0;

	memset(&sa, 0, sizeof(sa));
	sa.nl_family = AF_NETLINK;
	nh->nlmsg_pid = 0;
	nh->nlmsg_seq = ++sequence_number;
	/* Request an ack from kernel by setting NLM_F_ACK. */
	nh->nlmsg_flags |= NLM_F_ACK;

	printf("Sending message\n");
	return sendmsg(sock, &msg, 0);
}

static int should_exit = 0;
void signal_handler(int sig)
{
	//printf("signal caught! exiting...\n");
	should_exit = 1;
}


static char *progname = NULL;
#define PID_FILE "/tmp/servaldht.pid"

static int write_pid_file(void)
{
	FILE *f;

	f = fopen(PID_FILE, "w");

	if (!f) {
		fprintf(stderr, "Could not write PID file to %s : %s\n",
				PID_FILE, strerror(errno));
		return -1;
	}

	fprintf(f, "%u\n", getpid());

	fclose(f);

	return 0;
}

#define BUFLEN 256

enum {
	SERVALDHT_NOT_RUNNING = 0,
	SERVALDHT_RUNNING,
	SERVALDHT_BAD_PID,
	SERVALDHT_CRASHED,
};

static int check_pid_file(void)
{
	FILE *f;
	pid_t pid;
	int res = SERVALDHT_NOT_RUNNING;

	f = fopen(PID_FILE, "r");

	if (!f) {
		switch (errno) {
		case ENOENT:
			/* File probably doesn't exist */
			return SERVALDHT_NOT_RUNNING;
		case EACCES:
		case EPERM:
			/* Probably not owner and lack permissions */
			return SERVALDHT_RUNNING;
		case EISDIR:
		default:
			fprintf(stderr, "Pid file error: %s\n",
					strerror(errno));
		}
		return SERVALDHT_BAD_PID;
	}

	if (fscanf(f, "%u", (unsigned *)&pid) == 0) {
		fprintf(stderr, "Could not read PID file %s\n",
				PID_FILE);
		return SERVALDHT_BAD_PID;
	}

	fclose(f);

#if defined(OS_LINUX)
	{
		char buf[BUFLEN];
		snprintf(buf, BUFLEN, "/proc/%d/cmdline", pid);

		res = SERVALDHT_CRASHED;

		f = fopen(buf, "r");

		if (f) {
			size_t nitems = fread(buf, 1, BUFLEN, f);
			if (nitems && strstr(buf, progname) != NULL)
				res = SERVALDHT_RUNNING;
			fclose(f);
		}
	}
#endif
	return res;
}

static int daemonize(void)
{
	int i, sid;
	FILE *f;

	/* check if already a daemon */
	if (getppid() == 1)
		return -1;

	i = fork();

	if (i < 0) {
		fprintf(stderr, "Fork error...\n");
		return -1;
	}
	if (i > 0) {
		printf("Parent done... pid=%u. Going on daemon\n", getpid());
		exit(0);
	}
	/* new child (daemon) continues here */

	/* Change the file mode mask */
	umask(0);

	/* Create a new SID for the child process */
	sid = setsid();

	if (sid < 0)
		return -1;

	/*
	 Change the current working directory. This prevents the current
	 directory from being locked; hence not being able to remove it.
	 */
	if ((chdir("/")) < 0) {
		return -1;
	}

	/* Redirect standard files to /dev/null */
	f = freopen("/dev/null", "r", stdin);

	if (!f) {
		fprintf(stderr, "stdin redirection failed\n");
	}

	f = freopen("/dev/null", "w", stdout);

	if (!f) {
		fprintf(stderr, "stdout redirection failed\n");
	}

	f = freopen("/dev/null", "w", stderr);

	if (!f) {
		fprintf(stderr, "stderr redirection failed\n");
	}

	return 0;
}

static void print_usage()
{
	printf("Usage: %s [ OPTIONS ]\n"
			"where OPTIONS:\n"
			"\t-d,--daemon\t\t\t - Run in the background as a daemon.\n"
			"\t-h,--help\t\t\t - Print this help message.\n", progname);
}


int main(int argc, char **argv)
{
	progname = basename(argv[0]);
	int ret;
	int daemon = 0;

	argc--;
	argv++;
	while (argc) {
		if (strcmp(argv[0], "-d") == 0 ||strcmp(argv[0], "--daemon") == 0) {
			daemon = 1;
		} else if (strcmp(argv[0], "-h") == 0 ||strcmp(argv[0], "--help") == 0) {
			print_usage();
			return -1;
		} else {
			print_usage();
			return -1;
		}

		//More args are needed, for example for bootstrapping
		argc--;
		argv++;
	}

	ret = check_pid_file();
	if (ret == SERVALDHT_RUNNING) {
		fprintf(stderr, "A ServalDHT instance is already running!\n");
		return -1;
	} else if (ret == SERVALDHT_CRASHED) {
		fprintf(stderr, "ServalDHT has been executed since last boot!\n");
		unlink(PID_FILE);
	}
	if (write_pid_file() != 0) {
		fprintf(stderr, "Could not write PID file!\n");
		return -1;
	}

	struct sigaction action;
	memset(&action, 0, sizeof(struct sigaction));
	action.sa_handler = signal_handler;
	sigaction(SIGTERM, &action, 0);
	sigaction(SIGHUP, &action, 0);
	sigaction(SIGINT, &action, 0);

	/* Should we run ServalDHT as a deamon?
	 * Then there is the problem of multiple instances
	 * But it will be useful if servd initiates it
	if (daemon) {
		ret = daemonize();
		if (ret < 0) {
        	fprintf(stderr, "Could not make daemon\n");
			return ret;
		}
	}
	 */

	int sock;
	struct sockaddr_nl sa;
	struct {
		struct nlmsghdr nh;
		char payload[8];
	} msg;

	memset(&sa, 0, sizeof(sa));
	sa.nl_family = AF_NETLINK;
	sa.nl_groups = 0;

	sock = socket(PF_NETLINK, SOCK_RAW, NETLINK_SERVAL);

	if (sock == -1) {
		fprintf(stderr, "Could not open Serval netlink socket\n");
		return -1;
	}

	ret = bind(sock, (struct sockaddr*)&sa, sizeof(sa));

	if (ret == -1) {
		fprintf(stderr, "Could not bind netlink socket\n");
		return -1;
	}

	while(!should_exit)
	{
		printf("uid=%u\n", getpid());
		printf("service id=%d\n", ServalDHT_srv_id);
		printf("Listening...\n");
		nltest_recvmsg(sock);
		should_exit = 1;
	}

	printf("ServalDHT exiting...\n");
	return 0;
}
