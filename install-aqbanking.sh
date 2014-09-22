#!/bin/bash

set -e
function on_error() {
  echo "An error occurred, exiting."
}
trap on_error ERR

# Required by gwenhywfar: Some recent gnutls
GNUTLS_VERSION="2.12.22" #"3.1.26"
GNUTLS_URL="ftp://ftp.gnutls.org/gcrypt/gnutls/v2.12/gnutls-${GNUTLS_VERSION}.tar.bz2"

## online banking: gwenhywfar+aqbanking
GWENHYWFAR_VERSION="4.12.0beta"
GWENHYWFAR_URL="http://www2.aquamaniac.de/sites/download/download.php?package=01&release=76&file=01&dummy=gwenhywfar-${GWENHYWFAR_VERSION}.tar.gz"

AQBANKING_VERSION="5.5.0.2git"
AQBANKING_URL="http://www2.aquamaniac.de/sites/download/download.php?package=03&release=117&file=01&dummy=aqbanking-${AQBANKING_VERSION}.tar.gz"

EXTRA_MAKE_ARGS="-j2"

GLOBAL_DIR=/opt/hbci
if [ ! -d $GLOBAL_DIR ] ; then
    GLOBAL_DIR=$HOME/tmpa
else
    echo "You must call:"
    echo "yum install libgcrypt-devel p11-kit-devel gcc-g++ gmp-devel"
fi
GNUTLS_DIR=$GLOBAL_DIR/gnutls-${GNUTLS_VERSION}
GWENHYWFAR_DIR=$GLOBAL_DIR/gwenhywfar-${GWENHYWFAR_VERSION}
AQBANKING_DIR=$GLOBAL_DIR/aqbanking-${AQBANKING_VERSION}

DOWNLOAD_DIR=downloads
TMP_DIR=tmp
mkdir -p $TMP_DIR


PKG_CONFIG=pkg-config
export PKG_CONFIG_PATH="$GNUTLS_DIR/lib/pkgconfig:$GWENHYWFAR_DIR/lib/pkgconfig:$AQBANKING_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"

function die() { echo "$@"; exit 1; }
function qpushd() { pushd "$@" >/dev/null; }
function qpopd() { popd >/dev/null; }
function unix_path() { echo "$*" | sed 's,^\([A-Za-z]\):,/\1,;s,\\,/,g'; }

# usage:  smart_wget URL DESTDIR [DESTFILE]
function smart_wget() {
    _FILE=`basename $1`
    # Remove url garbage from filename that would not be removed by wget
    _UFILE=${3:-${_FILE##*=}}
    _DLD=`unix_path $2`

    # If the file already exists in the download directory ($2)
    # then don't do anything.  But if it does NOT exist then
    # download the file to the tmpdir and then when that completes
    # move it to the dest dir.
    if [ ! -f $_DLD/$_UFILE ] ; then
    # If WGET_RATE is set (in bytes/sec), limit download bandwith
    if [ ! -z "$WGET_RATE" ] ; then
            wget --passive-ftp -c $1 -P $TMP_DIR --limit-rate=$WGET_RATE $WGET_EXTRA_OPTIONS
        else
            wget --passive-ftp -c $1 -P $TMP_DIR $WGET_EXTRA_OPTIONS
        fi
    mv $TMP_DIR/$_FILE $_DLD/$_UFILE
    fi
    LAST_FILE=$_DLD/$_UFILE
}

# usage:  wget_unpacked URL DOWNLOAD_DIR UNPACK_DIR [DESTFILE]
function wget_unpacked() {
    smart_wget $1 $2 $4
    _EXTRACT_DIR=`unix_path $3`
    _EXTRACT_SUBDIR=
    echo -n "Extracting $_UFILE ... "
    case $LAST_FILE in
        *.zip)
            unzip -q -o $LAST_FILE -d $_EXTRACT_DIR
            _PACK_DIR=$(zipinfo -1 $LAST_FILE '*/*' 2>/dev/null | head -1)
            ;;
        *.tar.gz|*.tgz)
            tar -xzpf $LAST_FILE -C $_EXTRACT_DIR
            _PACK_DIR=$(tar -ztf $LAST_FILE 2>/dev/null | head -1)
            ;;
        *.tar.bz2)
            tar -xjpf $LAST_FILE -C $_EXTRACT_DIR
            _PACK_DIR=$(tar -jtf $LAST_FILE 2>/dev/null | head -1)
            ;;
         *.tar.xz)
             tar -xJpf $LAST_FILE -C $_EXTRACT_DIR
             _PACK_DIR=$(tar -Jtf $LAST_FILE 2>/dev/null | head -1)
             ;;
        *.tar.lzma)
            lzma -dc $LAST_FILE |tar xpf - -C $_EXTRACT_DIR
            _PACK_DIR=$(lzma -dc $LAST_FILE |tar -tf - 2>/dev/null | head -1)
            ;;
        *)
            die "Cannot unpack file $LAST_FILE!"
            ;;
    esac

    # Get the path where the files were actually unpacked
    # This can be a subdirectory of the requested directory, if the
    # tarball or zipfile contained a relative path.
    _PACK_DIR=$(echo "$_PACK_DIR" | sed 's,^\([^/]*\).*,\1,')
    if (( ${#_PACK_DIR} > 3 ))    # Skip the bin and lib directories from the test
    then
        _EXTRACT_SUBDIR=$(echo $_UFILE | sed "s,^\($_PACK_DIR\).*,/\1,;t;d")
    fi
    _EXTRACT_DIR="$_EXTRACT_DIR$_EXTRACT_SUBDIR"
    echo "done"
}

function assert_one_dir() {
    counted=$(ls -d "$@" 2>/dev/null | wc -l)
    if [[ $counted -eq 0 ]]; then
        die "Exactly one directory is required, but detected $counted; please check why $@ wasn't created"
    fi
    if [[ $counted -gt 1 ]]; then
        die "Exactly one directory is required, but detected $counted; please delete all but the latest one: $@"
    fi
}

# #####################################################

mkdir -p $DOWNLOAD_DIR

# ##############################
# gnutls

echo "###"
echo "### Checking gnutls"
echo "###"

if ${PKG_CONFIG} --exact-version=${GNUTLS_VERSION} gnutls
then
    echo "GNUTLS already installed in $GNUTLS_DIR. skipping."
else
    wget_unpacked $GNUTLS_URL $DOWNLOAD_DIR $TMP_DIR
    assert_one_dir $TMP_DIR/gnutls-*
    cd $TMP_DIR/gnutls-*
    ./configure \
        --disable-cxx --disable-hardware-acceleration \
	--without-lzo --disable-guile \
	--with-libgcrypt \
        --without-libnettle-prefix \
        --without-libiconv-prefix \
        --without-libpth-prefix \
        --without-libintl-prefix \
        --prefix=${GNUTLS_DIR}
    make ${EXTRA_MAKE_ARGS}
    make install
   
    cd ..
    ${PKG_CONFIG} --exists gnutls || die "GNUTLS not installed correctly"
    assert_one_dir gnutls-*
    rm -rf gnutls-*
fi
GNUTLS_CPPFLAGS="-I${GNUTLS_DIR}/include"
GNUTLS_LDFLAGS="-L${GNUTLS_DIR}/lib"


# ##############################
# gwenhywfar

echo "###"
echo "### Checking gwenhywfar"
echo "###"

if ${PKG_CONFIG} --exact-version=${GWENHYWFAR_VERSION} gwenhywfar
then
    echo "Gwenhywfar already installed in $GWENHYWFAR_DIR. skipping."
else
    wget_unpacked $GWENHYWFAR_URL $DOWNLOAD_DIR $TMP_DIR
    assert_one_dir $TMP_DIR/gwenhywfar-*
    cd $TMP_DIR/gwenhywfar-*

    ./configure \
        --disable-binreloc \
        --disable-ssl \
        --prefix=$GWENHYWFAR_DIR \
        CPPFLAGS="${GNUTLS_CPPFLAGS}" \
        LDFLAGS="${GNUTLS_LDFLAGS}" \
        --with-guis=none
    make ${EXTRA_MAKE_ARGS}
    make install
    cd ..
    ${PKG_CONFIG} --exact-version=${GWENHYWFAR_VERSION} gwenhywfar || die "Gwenhywfar not installed correctly"
    assert_one_dir gwenhywfar-*
    rm -rf gwenhywfar-*
fi

# ##############################
# aqbanking

echo "###"
echo "### Checking aqbanking"
echo "###"

if ${PKG_CONFIG} --exact-version=${AQBANKING_VERSION} aqbanking
then
    echo "AqBanking already installed in $AQBANKING_DIR. skipping."
else
    wget_unpacked $AQBANKING_URL $DOWNLOAD_DIR $TMP_DIR
    assert_one_dir $TMP_DIR/aqbanking-*
    cd $TMP_DIR/aqbanking-*
    _AQ_BACKENDS="aqhbci"
    ./configure \
        --with-gwen-dir=${GWENHYWFAR_DIR} \
        --with-frontends="cbanking" \
        --with-backends="${_AQ_BACKENDS}" \
        --prefix=${AQBANKING_DIR} \
        CPPFLAGS="${GNUTLS_CPPFLAGS}" \
        LDFLAGS="${GNUTLS_LDFLAGS}"
    make
    make install
    cd ..
    ${PKG_CONFIG} --exists aqbanking || die "AqBanking not installed correctly"
    assert_one_dir aqbanking-*
    rm -rf aqbanking-*
fi
