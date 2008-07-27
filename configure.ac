AC_INIT
AC_CONFIG_SRCDIR([ebb.c])

AM_INIT_AUTOMAKE(libebb,0.1)
AC_CONFIG_HEADERS([config.h])
AM_MAINTAINER_MODE

AC_PROG_INSTALL
AC_PROG_LIBTOOL

if test "x$GCC" = xyes ; then
  CFLAGS="$CFLAGS -O3"
fi

AC_MSG_CHECKING(for Ragel)
AC_CHECK_PROGS(RAGEL, [ragel], yes)
AC_SUBST(RAGEL)
AM_CONDITIONAL(HAVE_RAGEL, [test "x$RAGEL" != "x"])
dnl If we don't have Ragel make sure appid.c is already built.
if test "x$RAGEL" == "x"; then
  AC_CHECK_FILE(ebb_request_parser.c, , [AC_ERROR(Ragel required to build from current state)])
fi



 
AC_CHECK_HEADERS(ev.h, [], [
    echo "error you need libev! http://libev.schmorp.de/"
    exit -1
    ]) 
AC_CHECK_LIB([ev] , [ev_loop], [], [
    echo "error you need libev! http://libev.schmorp.de/"
    exit -1
    ])

AC_ARG_WITH(gnutls, AS_HELP_STRING([--without-gnutls], [build without HTTPS support (if you don't have gnutls installed)]))
if test "$without_gnutls"; then
  echo "*** GnuTLS support (for HTTPS) will be disabled"
else
  dnl ---------------------------------------------
  dnl Find pkg-config
  dnl ---------------------------------------------
  AC_PATH_PROG(PKG_CONFIG, pkg-config, no)
  if test x$PKG_CONFIG = xno ; then
    echo "*** pkg-config not found. See http://pkgconfig.sourceforge.net"
    echo "*** GnuTLS support (for HTTPS) will be disabled"
  else
    dnl ---------------------------------------------
    dnl Check for DirectFB
    dnl ---------------------------------------------
    DIRECTFB_REQUIRED_VERSION=0.9.9

    AC_MSG_CHECKING(for GnuTLS)
    if $PKG_CONFIG --exists gnutls ; then
          AC_MSG_RESULT(found)

          AC_DEFINE(HAVE_GNUTLS, 1, [Define to 1 if you have GNU tls.])

          CPPFLAGS="$CPPFLAGS `$PKG_CONFIG --cflags gnutls`"
          NETWORK_LIBS="$NETWORK_LIBS `$PKG_CONFIG --libs gnutls`"

          have_gnutls="yes"
    else
      AC_MSG_RESULT([*** All of GnuTLS dependent parts will be disabled ***])
    fi
  fi
fi


AC_CONFIG_FILES([ Makefile ])
AC_OUTPUT
