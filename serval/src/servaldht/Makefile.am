SUBDIRS = \
	dht

bin_PROGRAMS = \
	servaldht
	
servaldht_SOURCES = \
	servaldht.c

noinst_HEADERS =

CFLAGS = -g3 -O0

servaldht_CPPFLAGS =-I$(top_srcdir)/include/sys/
servaldht_LDFLAGS =
	
clean-local:
	rm -f *~
