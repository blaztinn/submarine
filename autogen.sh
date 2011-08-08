#!/bin/sh

srcdir=`dirname $0`
test -z "$srcdir" && srcdir=.

ORIGDIR=`pwd`
cd $srcdir

mkdir -p m4

autoreconf -v --install || exit 1

cd $ORIGDIR || exit $?
