bin_PROGRAMS = submarine

submarine_SOURCES = report.vala \
					main.vala
submarine_VALAFLAGS = $(SUBMARINE_VALAPACKAGES) ../vapi/config.vapi ../lib/submarine.vapi
submarine_CPPFLAGS = -I../lib/ $(SUBMARINE_CFLAGS)
submarine_LDADD = ../lib/libsubmarine.la $(SUBMARINE_LIBS)

CLEANFILES = *.h *.c *.vapi *.stamp
