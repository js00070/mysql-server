#!/bin/bash
#
# Script for Dev's daily work.  It is a good idea to use the exact same
# build options as the released version.

get_os_type()
{
  if [ "$(uname)" == "Darwin" ]; then
    # Mac OS X
    os_type="OSX"
  elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    # GNU/Linux
    os_type="Linux"
  elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
    # Windows NT
    os_type="WIN"
  fi
}

get_key_value()
{
  echo "$1" | sed 's/^--[a-zA-Z_-]*=//'
}

usage()
{
cat <<EOF
Usage: $0 [-t debug|release] [-d <dest_dir>] [-s <server_suffix>] [-g asan|tsan]
       Or
       $0 [-h | --help]
  -t                      Select the build type.
  -d                      Set the destination directory.
  -s                      Set the server suffix.
  -g                      Enable the sanitizer of compiler, asan for AddressSanitizer, tsan for ThreadSanitizer
  -c                      Enable GCC coverage compiler option
  -h, --help              Show this help message.

Note: this script is intended for internal use by MySQL developers.
EOF
}

parse_options()
{
  while test $# -gt 0
  do
    case "$1" in
    -t=*)
      build_type=`get_key_value "$1"`;;
    -t)
      shift
      build_type=`get_key_value "$1"`;;
    -d=*)
      dest_dir=`get_key_value "$1"`;;
    -d)
      shift
      dest_dir=`get_key_value "$1"`;;
    -s=*)
      server_suffix=`get_key_value "$1"`;;
    -s)
      shift
      server_suffix=`get_key_value "$1"`;;
    -g=*)
      san_type=`get_key_value "$1"`;;
    -g)
      shift
      san_type=`get_key_value "$1"`;;
    -c=*)
      enable_gcov=`get_key_value "$1"`;;
    -c)
      shift
      enable_gcov=`get_key_value "$1"`;;
    -h | --help)
      usage
      exit 0;;
    *)
      echo "Unknown option '$1'"
      exit 1;;
    esac
    shift
  done
}

dump_options()
{
  echo "Dumping the options used by $0 ..."
  echo "build_type=$build_type"
  echo "dest_dir=$dest_dir"
  echo "server_suffix=$server_suffix"
  echo "Sanitizer=$san_type"
  echo "GCOV=$enable_gcov"
}

if test ! -f sql/mysqld.cc
then
  echo "You must run this script from the MySQL top-level directory"
  exit 1
fi

build_type="debug"
dest_dir="/u01/mysql"
server_suffix="rds-dev"
os_type="Linux"
san_type=""
asan=0
tsan=0
enable_gcov=0
allocator=1

parse_options "$@"
dump_options
get_os_type

if [ x"$build_type" = x"debug" ]; then
  build_type="Debug"
  debug=1
  if [ $enable_gcov -eq 1 ]; then
    gcov=1
  else
    gcov=0
  fi
elif [ x"$build_type" = x"release" ]; then
  # Release CMAKE_BUILD_TYPE is not compatible with mysql 8.0
  # build_type="Release"
  build_type="RelWithDebInfo"
  debug=0
  gcov=0
else
  echo "Invalid build type, it must be \"debug\" or \"release\"."
  exit 1
fi

server_suffix="-""$server_suffix"

if [ x"$build_type" = x"RelWithDebInfo" ]; then
  COMMON_FLAGS="-O3 -g -fexceptions -fno-omit-frame-pointer -fno-strict-aliasing"
  COMMON_FLAGS="${COMMON_FLAGS} -D_GLIBCXX_USE_CXX11_ABI=0"
  CFLAGS="$COMMON_FLAGS"
  CXXFLAGS="$COMMON_FLAGS"
elif [ x"$build_type" = x"Debug" ]; then
  COMMON_FLAGS="-O0 -g3 -gdwarf-2 -fexceptions -fno-omit-frame-pointer -fno-strict-aliasing"
  COMMON_FLAGS="${COMMON_FLAGS} -D_GLIBCXX_USE_CXX11_ABI=0"
  CFLAGS="$COMMON_FLAGS"
  CXXFLAGS="$COMMON_FLAGS"
fi

if [ x"$san_type" = x"" ]; then
    asan=0
    tsan=0
elif [ x"$san_type" = x"asan" ]; then
    asan=1
    tsan=0
    ## gcov is conflicting with gcc sanitizer (at least for devtoolset-7),
    ## disable gcov if sanitizer is requested
    gcov=0
    ## asan conflict with jemalloc in memory allocation, disable when use asan
    allocator=0
elif [ x"$san_type" = x"tsan" ]; then
    asan=0
    tsan=1
    ## gcov is conflicting with gcc sanitizer (at least for devtoolset-7),
    ## disable gcov if sanitizer is requested
    gcov=0
    allocator=0
else
  echo "Invalid sanitizer type, it must be \"asan\" or \"tsan\"."
  exit 1
fi

export CC CFLAGS CXX CXXFLAGS

rm -rf CMakeCache.txt
make clean

cmake .                                \
    -DCMAKE_BUILD_TYPE="$build_type"   \
    -DSYSCONFDIR="$dest_dir"           \
    -DCMAKE_INSTALL_PREFIX="$dest_dir" \
    -DMYSQL_DATADIR="$dest_dir/data"   \
    -DWITH_DEBUG=$debug                \
    -DINSTALL_LAYOUT=STANDALONE        \
    -DWITH_EXTRA_CHARSETS=all          \
    -DENABLED_PROFILING=1              \
    -DENABLED_LOCAL_INFILE=1           \
    -DENABLE_EXPERIMENT_SYSVARS=1      \
    -DWITH_BOOST="extra" \
    -DMYSQL_SERVER_SUFFIX="$server_suffix" \

if [ x"$os_type" = x"Linux" ]; then
  make -j `cat /proc/cpuinfo | grep processor| wc -l`
elif [ x"$os_type" = x"OSX" ]; then
  make -j8
fi
# end of file
