noinst_LTLIBRARIES = libsubmarine.la

libsubmarine_la_SOURCES = language_codes.vala \
						 subtitle.vala \
						 server.vala \
						 open_subtitles.vala \
						 session.vala
libsubmarine_la_VALAFLAGS = $(LIBSUBMARINE_VALAPACKAGES) --library submarine -H submarine.h
libsubmarine_la_CPPFLAGS = $(LIBSUBMARINE_CFLAGS)

CLEANFILES = *.h *.c *.vapi *.stamp
