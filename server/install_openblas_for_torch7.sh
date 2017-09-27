#!/bin/bash
set -e

######################################################################
# This script installs required dependencies for Torch7
######################################################################
{

install_openblas() {
    # Get and build OpenBlas (Torch is much better with a decent Blas)
    cd /tmp/
    rm -rf OpenBLAS
    git clone https://github.com/xianyi/OpenBLAS.git
    cd OpenBLAS
    if [ $(getconf _NPROCESSORS_ONLN) == 1 ]; then
        make NO_AFFINITY=1 USE_OPENMP=0 USE_THREAD=0
    else
        make NO_AFFINITY=1 USE_OPENMP=1
    fi
    RET=$?;
    if [ $RET -ne 0 ]; then
        echo "Error. OpenBLAS could not be compiled";
        exit $RET;
    fi
    sudo make install
    RET=$?;
    if [ $RET -ne 0 ]; then
        echo "Error. OpenBLAS could not be installed";
        exit $RET;
    fi
}

install_openblas_AUR() {
    # build and install an OpenBLAS package for Archlinux
    cd /tmp && \
    curl https://aur.archlinux.org/cgit/aur.git/snapshot/openblas-lapack.tar.gz | tar zxf - && \
    cd openblas-lapack
    makepkg -csi --noconfirm
    RET=$?;
    if [ $RET -ne 0 ]; then
        echo "Error. OpenBLAS could not be installed";
        exit $RET;
    fi
}

checkupdates_archlinux() {
    # checks if archlinux is up to date
    if [[ -n $(checkupdates) ]]; then
        echo "It seems that your system is not up to date."
        echo "It is recommended to update your system before going any further."
        read -p "Continue installation ? [y/N] " yn
            case $yn in
                Y|y ) echo "Continuing...";;
                * ) echo "Installation aborted."
                    echo "Relaunch this script after updating your system with 'pacman -Syu'."
                    exit 0
            esac
    fi
}

# Based on Platform:
if [[ `uname` == 'Darwin' ]]; then
    # GCC?
    if [[ `which gcc` == '' ]]; then
        echo "MacOS doesn't come with GCC: please install XCode and the command line tools."
        exit 1
    fi

    # Install Homebrew (pkg manager):
    if [[ `which brew` == '' ]]; then
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi

    # Install dependencies:
    brew update
    brew install git readline cmake wget qt
    brew install libjpeg imagemagick zeromq graphicsmagick openssl
    brew link readline --force
    brew cask install xquartz
    brew list -1 | grep -q "^gnuplot\$" && brew remove gnuplot
    brew install gnuplot --with-wxmac --with-cairo --with-pdflib-lite --with-x11 --without-lua

elif [[ "$(uname)" == 'Linux' ]]; then

    if [[ -r /etc/os-release ]]; then
        # this will get the required information without dirtying any env state
        DIST_VERS="$( ( . /etc/os-release &>/dev/null
                        echo "$ID $VERSION_ID") )"
        DISTRO="${DIST_VERS%% *}" # get our distro name
        VERSION="${DIST_VERS##* }" # get our version number
    elif [[ -r /etc/redhat-release ]]; then
        DIST_VERS=( $( cat /etc/redhat-release ) ) # make the file an array
        DISTRO="${DIST_VERS[0],,}" # get the first element and get lcase
        VERSION="${DIST_VERS[2]}" # get the third element (version)
    elif [[ -r /etc/lsb-release ]]; then
        DIST_VERS="$( ( . /etc/lsb-release &>/dev/null
                        echo "${DISTRIB_ID,,} $DISTRIB_RELEASE") )"
        DISTRO="${DIST_VERS%% *}" # get our distro name
        VERSION="${DIST_VERS##* }" # get our version number
    else # well, I'm out of ideas for now
        echo '==> Failed to determine distro and version.'
        exit 1
    fi

    # Detect fedora
    if [[ "$DISTRO" = "fedora" ]]; then
        distribution="fedora"
        fedora_major_version="$VERSION"
    # Detect archlinux
    elif [[ "$DISTRO" = "arch" ]]; then
        distribution="archlinux"
    # Detect Ubuntu
    elif [[ "$DISTRO" = "ubuntu" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        distribution="ubuntu"
        ubuntu_major_version="${VERSION%%.*}"
    # Detect elementary OS
    elif [[ "$DISTRO" = "elementary" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        distribution="elementary"
        elementary_version="${VERSION%.*}"
    # Detect CentOS
    elif [[ "$DISTRO" = "centos" ]]; then
        distribution="centos"
        centos_major_version="$VERSION"
    # Detect AWS
    elif [[ "$DISTRO" = "amzn" ]]; then
        distribution="amzn"
        amzn_major_version="$VERSION"
    elif [[ "$DISTRO" == "raspbian" ]]; then
        distribution="raspbian"
        debian_major_version="$VERSION"
    else
        echo '==> Only Ubuntu, elementary OS, Fedora, Archlinux and CentOS distributions are supported.'
        exit 1
    fi

    # Install dependencies for Torch:
    if [[ $distribution == 'ubuntu' ]]; then
        if sudo apt-get update ; then
            echo "Updated successfully."
        else
            echo "Some portion of the update is failed"
        fi
        # python-software-properties is required for apt-add-repository
        sudo apt-get install -y python-software-properties
        echo "==> Found Ubuntu version ${ubuntu_major_version}.xx"
        if [[ $ubuntu_major_version -lt '12' ]]; then
            echo '==> Ubuntu version not supported.'
            exit 1
        elif [[ $ubuntu_major_version -lt '14' ]]; then # 12.xx
            sudo -E add-apt-repository -y ppa:chris-lea/zeromq
        elif [[ $ubuntu_major_version -lt '15' ]]; then # 14.xx
        sudo -E apt-get install -y software-properties-common
            sudo -E add-apt-repository -y ppa:jtaylor/ipython
        else
            sudo apt-get install -y software-properties-common \
                libgraphicsmagick1-dev libfftw3-dev sox libsox-dev \
                libsox-fmt-all
        fi

        if sudo apt-get update ; then
            echo "Updated successfully."
        else
            echo "Some portion of the update is failed"
        fi
        sudo apt-get install -y build-essential gcc g++ curl \
            cmake libreadline-dev git-core libqt4-dev libjpeg-dev \
            libpng-dev ncurses-dev imagemagick libzmq3-dev gfortran \
            unzip gnuplot gnuplot-x11 ipython

        gcc_major_version=$(gcc --version | grep ^gcc | awk '{print $4}' | \
                            cut -c 1)
        if [[ $gcc_major_version == '5' ]]; then
            echo '==> Found GCC 5, installing GCC 4.9.'
            sudo apt-get install -y gcc-4.9 libgfortran-4.9-dev g++-4.9
        fi

        if [[ $ubuntu_major_version -lt '15' ]]; then
            sudo apt-get install libqt4-core libqt4-gui
        fi

        install_openblas || true

    elif [[ $distribution == 'raspbian' ]]; then
        echo "==> Found Raspbian version ${debian_major_version}.xx"
        if sudo apt-get update ; then
            echo "Updated successfully."
        else
            echo "Some portion of the update is failed"
        fi
        sudo apt-get install -y build-essential gcc g++ curl \
            cmake libreadline-dev git-core libqt4-dev libjpeg-dev \
            libpng-dev ncurses-dev imagemagick libzmq3-dev gfortran \
            unzip gnuplot gnuplot-x11 ipython

        install_openblas || true

    elif [[ $distribution == 'elementary' ]]; then
        declare -a target_pkgs
        target_pkgs=( build-essential gcc g++ curl \
                      cmake libreadline-dev git-core libqt4-core libqt4-gui \
                      libqt4-dev libjpeg-dev libpng-dev ncurses-dev \
                      imagemagick libzmq3-dev gfortran unzip gnuplot \
                      gnuplot-x11 ipython )
        if sudo apt-get update ; then
            echo "Updated successfully."
        else
            echo "Some portion of the update is failed"
        fi
        # python-software-properties is required for apt-add-repository
        sudo apt-get install -y python-software-properties
        if [[ $elementary_version == '0.3' ]]; then
            echo '==> Found Ubuntu version 14.xx based elementary installation, installing dependencies'
            sudo apt-get install -y software-properties-common \
                libgraphicsmagick1-dev libfftw3-dev sox libsox-dev \
                libsox-fmt-all

            sudo -E add-apt-repository -y ppa:jtaylor/ipython
        else
            sudo -E add-apt-repository -y ppa:chris-lea/zeromq
        fi
        if sudo apt-get update ; then
            echo "Updated successfully."
        else
            echo "Some portion of the update is failed"
        fi
        sudo apt-get install -y "${target_pkgs[@]}"

        install_openblas || true

    elif [[ $distribution == 'archlinux' ]]; then
        echo "Archlinux installation"
        checkupdates_archlinux
        sudo pacman -S --quiet --noconfirm --needed \
            cmake curl readline ncurses git \
            gnuplot unzip libjpeg-turbo libpng libpng \
            imagemagick graphicsmagick fftw sox zeromq \
            ipython qt4 qtwebkit || exit 1
        pacman -Sl multilib &>/dev/null
        if [[ $? -ne 0 ]]; then
            gcc_package="gcc"
        else
            gcc_package="gcc-multilib"
        fi
        sudo pacman -S --quiet --noconfirm --needed \
            ${gcc_package} gcc-fortran || exit 1
        # if openblas is not installed yet
        pacman -Qs openblas &> /dev/null
        if [[ $? -ne 0 ]]; then
            install_openblas_AUR || true
        else
            echo "OpenBLAS is already installed"
        fi

    elif [[ $distribution == 'fedora' ]]; then
        if [[ $fedora_major_version == '20' ]]; then
            sudo yum install -y cmake curl readline-devel ncurses-devel \
                                gcc-c++ gcc-gfortran git gnuplot unzip \
                                libjpeg-turbo-devel libpng-devel \
                                ImageMagick GraphicsMagick-devel fftw-devel \
                                sox-devel sox zeromq3-devel \
                                qt-devel qtwebkit-devel sox-plugins-freeworld \
                                ipython
            install_openblas || true
        elif [[ $fedora_major_version == '22' ||  $fedora_major_version == '23' ]]; then
            #using dnf - since yum has been deprecated
            #sox-plugins-freeworld is not yet available in repos for F22
            sudo dnf install -y make cmake curl readline-devel ncurses-devel \
                                gcc-c++ gcc-gfortran git gnuplot unzip \
                                libjpeg-turbo-devel libpng-devel \
                                ImageMagick GraphicsMagick-devel fftw-devel \
                                sox-devel sox qt-devel qtwebkit-devel \
                                python-ipython czmq czmq-devel
            install_openblas || true
        elif [[ $fedora_major_version == '24' ]]; then
            sudo dnf install -y make cmake curl readline-devel ncurses-devel \
                                gcc-c++ gcc-gfortran git gnuplot unzip \
                                libjpeg-turbo-devel libpng-devel \
                                ImageMagick GraphicsMagick-devel fftw-devel \
                                sox-devel sox qt-devel qtwebkit-devel \
                                python-ipython czmq czmq-devel
            install_openblas || true
        else
            echo "Only Fedora 20-24 are supported for now, aborting."
            exit 1
        fi
    elif [[ $distribution == 'centos' ]]; then
        if [[ $centos_major_version == '7' ]]; then
            sudo yum install -y epel-release # a lot of things live in EPEL
            sudo yum install -y make cmake curl readline-devel ncurses-devel \
                                gcc-c++ gcc-gfortran git gnuplot unzip \
                                libjpeg-turbo-devel libpng-devel \
                                ImageMagick GraphicsMagick-devel fftw-devel \
                                sox-devel sox zeromq3-devel \
                                qt-devel qtwebkit-devel sox-plugins-freeworld
            sudo yum install -y python-ipython
            install_openblas || true
        else
            echo "Only CentOS 7 is supported for now, aborting."
            exit 1
        fi
    elif [[ $distribution == 'amzn' ]]; then
        sudo yum install -y cmake curl readline-devel ncurses-devel \
                            gcc-c++ gcc-gfortran git gnuplot unzip \
                            libjpeg-turbo-devel libpng-devel \
                            ImageMagick GraphicsMagick-devel fftw-devel \
                            libgfortran python27-pip git openssl-devel

        #
        # These libraries are missing from amzn linux
        # sox-devel sox sox-plugins-freeworld qt-devel qtwebkit-devel
        #

        sudo yum --enablerepo=epel install -y zeromq3-devel
        sudo pip install ipython

        install_openblas || true
    fi

elif [[ "$(uname)" == 'FreeBSD' ]]; then
    pkg install ImageMagick cmake curl fftw3 git gnuplot libjpeg-turbo \
        libzmq3 ncurses openblas openssl png py27-ipython \
        py27-pip qt4-corelib qt4-gui readline unzip

else
    # Unsupported
    echo '==> platform not supported, aborting'
    exit 1
fi

ipython_exists=$(command -v ipython) || true
if [[ $ipython_exists ]]; then {
    ipython_version=$(ipython --version|cut -f1 -d'.')
    if [[ $ipython_version -lt 2 ]]; then {
        echo 'WARNING: Your ipython version is too old.  Type "ipython --version" to see this.  Should be at least version 2'
    } fi
} fi

# Done.
echo "==> Torch7's dependencies have been installed"

}
