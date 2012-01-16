#! /bin/bash
#

## 
# clear out whatever LSST software environment currently in the environment
#
function clearlsst {
    [ -n "$SETUP_EUPS" ] && {
        eval `$EUPS_DIR/bin/eups_setup --unsetup lsst`
    }
    setuppkgs=(`printenv | grep '^SETUP_' | sed -e 's/=.*$//'`)
    for var in ${setuppkgs[@]}; do
        pkghome=`echo $var | sed -e 's/SETUP_//' -e 's/$/_DIR/'`
        eval $var=
        eval $pkghome=
    done
    EUPS_PATH=
    LD_LIBRARY_PATH=
    PYTHONPATH=
}

##
# return the top directory for the source distribution given product
# @param 1  the product name
# @param 2  the product version
#   
function productDirName {
    echo "$1-$2"
}

##
# drop the build number extension from a given version string
#
function taggedVersion {
    echo $1 | sed -e 's/[\+\-].*$//'
}

##
# export the product source distribution from the code repository and 
# bundle it up into a tar-ball
#
function extractProductSource {
    local prod=$1 vers=$2
    local pdname=`productDirName $prod $vers`
    reposExtract $prod $vers $pdname || {
        echo "$prog: failed to extract source code"
        return 4
    }
    tar czf ${pdname}.tar.gz $pdname || { 
        echo "$prog: Problem creating tar-ball"
        return 5
    }
}

##
# build the product in a given directory
# @param 1    name of the product
# @param 2    the installed-as version (i.e. with build number, if desired)
# @param 3    product source directory
# @param 4    the number of threads to use (optional)
#
function buildProduct {
    # assume that our stack has current tags up to date

    local prod=$1 vers=$2 pdir=$3 tags=$4 threads=$5
    local oldpath=$EUPS_PATH

    tagarg=
    [ -n "$tags" ] && {
        for tag in `echo $tags|sed -e 's/,/ /g'`; do
           tagarg="$tagarg --tag=$tag" 
        done
    }
    tagarg="$tagarg --tag=current"

    cd $pdir
    local buildlog=build.log
    touch buildlog

    # get the dependency products tagged current whenever possible
    echo setup $tagarg -r . | tee -a $buildlog
    setup $tagarg -r .

    threadarg=
    [ -n "$threads" ] && threadarg="-j $threads"

    buildok=
    echo scons opt=3 version=$vers $threadarg | tee -a $buildlog
    scons opt=3 version=$vers $threadarg >> $buildlog 2>&1 && buildok=1
    if [ -n "$buildok" ]; then
        mkdir -p "tests/.tests"
    else
        tail -40 $buildlog
        echo "$prog: Product build failed; see $PWD/$buildlog for details"
        return 4
    fi
}

##
# check to see if the tests passed
# @param 1   build directory
#
function checkTests {
    local pdir=$1

    cd $pdir/tests/.tests || return 5
    ran=(`ls`)
    [ ${#ran[@]} -eq 0 ] && {
        echo "Note: Apparently no tests were provided"
        return 0
    }
    failed=(`ls *.failed 2> /dev/null`)
    [ ${#failed[@]} -gt 0 ] && {
        howmany="${#failed[@]} test"
        [ ${#failed[@]} -gt 1 ] && howmany="${howmany}s"
        echo $howmany failed: ${failed[@]}
        return 5
    }
    echo "All tests passed"
}

##
# install a built product.  
# @param 1    name of the product
# @param 2    the version to install as (i.e. with build number, if desired)
# @param 3    product source directory
# @param 4    install stack
#
function installProduct {
    local prod=$1 vers=$2 pdir=$3 teststack=$4
    local buildlog=build.log
    touch buildlog

    EUPS_PATH=${teststack}:$EUPS_PATH
    flavor=`eups flavor`

    cd $pdir
    echo setup -r . | tee -a $buildlog
    setup -r .
    echo scons opt=3 version=$vers install | tee -a $buildlog
    { scons opt=3 version=$vers install >> $buildlog 2>&1 && \
      [ -d "$teststack/$flavor/$prod/$vers" ]; } || {
        echo "${prog}: Product failed to install into test stack; see $buildlog"
        tail -40 $buildlog
        return 6
    }
    echo scons -j 1 opt=3 version=$vers declare | tee -a $buildlog
    scons -j 1 opt=3 version=$vers declare >> $buildlog 2>&1
}

##
# create the distribution artifacts.  Modifies EUPS_PATH
# @param 1    name of the product
# @param 2    the installed-as version (i.e. with build number, if desired)
# @param 3    the server distribution directory to create into
# @param 4    the directory containing the tarball
# @param 5    the software stack where the product is installed (optional)
#
function distribcreate {
    local prod=$1 vers=$2 serverstage=$3 builddir=$4 stack=$5
    [ -n "$stack" ] && EUPS_PATH=${stack}:$EUPS_PATH

    echo eups distrib create -j -f generic -d lsstbuild -s $serverstage \
                 -S srctardir=$builddir $prod $vers
    eups distrib create -j -f generic -d lsstbuild -s $serverstage      \
                 -S srctardir=$builddir $prod $vers                  || \
    {
        echo "${prog}: Problem packaging product via eups distrib create"
        return 7
    }
    local taggedas=`taggedVersion $version`
    [ -f "$serverstage/$prodname/$taggedas/$prodname-${taggedas}.tar.gz" ] || {
        echo "${prog}: Failed to stage tarball"
        return 7
    }
}

##
# print the highest build number in use 
# @param 1   product name
# @param 2   version of the product not including the build extension
#
function latestBuildFromStack {
    local prod=$1 vers=$2
    eups list $prod ${vers}'+*' > /dev/null 2>&1 || {
        echo 0
        return 1
    }
    eups list $prod ${vers}'+*' | tail -1 | awk '{print $1}' | sed -e 's/.*+//'
}

## 
# return the next appropriate build number for a product
# @param 1   product name
# @param 2   version of the product not including the build extension
#
function recommendBuildNumber {
    local prod=$1 vers=$2
    expr `latestBuildFromStack $prod $vers` + 1
}

##
# create a directory to take the output from eups distrib create
#
function makeStageServer {
    local serverdir
    serverdir=$1
    mkdir -p "$serverdir/manifests" || return 1
    [ -f "$serverdir/config.txt" ] || \
       cp $DEVENV_SERVERTOOLS_DIR/conf/lsstserver_config.txt "$serverdir/config.txt" || return 1
}

