ARG BUILD_BASE=ubuntu:26.04
FROM $BUILD_BASE
MAINTAINER Jamie Iles <jamie@jamieiles.com>
ENV DEBIAN_FRONTEND=noninteractive
ARG VERILATOR_VERSION=5.048
ARG RISCV_TOOLCHAIN_MIRROR=https://static.dev.sifive.com/dev-tools
ARG RISCV_TOOLCHAIN_ARCHIVE=riscv64-unknown-elf-gcc-8.3.0-2019.08.0-x86_64-linux-ubuntu14.tar.gz
RUN apt-get update && apt-get install --no-install-recommends -y \
    autoconf \
    bison \
    build-essential \
    ca-certificates \
    ccache \
    clang \
    clang-c++ \
    cmake \
    cpp \
    curl \
    device-tree-compiler \
    flatbuffers-compiler \
    flex \
    gawk \
    git \
    gperf \
    graphviz \
    haskell-stack \
    help2man \
    libboost-program-options-dev \
    libboost-python-dev \
    libboost-serialization-dev \
    libclang-dev \
    libffi-dev \
    libfl-dev \
    libfl-dev \
    libfl2 \
    libflatbuffers-dev \
    libfmt-dev \
    libfmt-dev \
    libftdi-dev \
    libgmp-dev \
    libnuma-dev \
    libnuma1 \
    libreadline-dev \
    libsdl2-2.0-0 \
    libsdl2-dev \
    libusb-1.0-0-dev \
    llvm \
    llvm-dev \
    locales \
    mercurial \
    ninja-build \
    pkg-config \
    python3 \
    python3-click \
    python3-dev \
    python3-distorm3 \
    python3-lxml \
    python3-pip \
    python3-pystache \
    python3-pystache \
    python3-yaml \
    python3-yaml \
    ruby \
    ruby-dev \
    tcl-dev \
    unzip \
    wget \
    xdot \
    xxd \
    zip \
    zlib1g \
    zlib1g-dev
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
RUN cd /tmp && \
    git clone https://github.com/zachjs/sv2v.git && \
    cd sv2v && \
    make && \
    cp bin/sv2v /usr/bin && \
    cd .. && \
    rm -rf sv2v
RUN cd /tmp && \
    wget https://github.com/verilator/verilator/archive/refs/tags/v$VERILATOR_VERSION.tar.gz && \
    tar xf v$VERILATOR_VERSION.tar.gz && \
    cd verilator-$VERILATOR_VERSION && \
    autoconf && \
    ./configure --prefix=/usr && \
    make -j$(nproc) && \
    make install && \
    cd /tmp && rm -r verilator-$VERILATOR_VERSION

RUN cd /tmp && \
    git clone https://github.com/YosysHQ/yosys.git -b v0.64 --recurse-submodules yosys && \
    cd yosys && \
    make -j$(nproc) && \
    make install && \
    cd /tmp && \
    rm -rf yosys
RUN cd /tmp && \
    git clone https://github.com/YosysHQ/SymbiYosys.git -b v0.64 --recurse-submodules SymbiYosys && \
    cd SymbiYosys && \
    make install && \
    cd /tmp && \
    rm -rf SymbiYosys
RUN apt-get install -y curl meson libmpfr-dev
RUN git clone https://github.com/SRI-CSL/yices2.git yices2 && \
    cd yices2 && \
    autoconf && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf yices2
RUN cd /tmp && \
    wget $RISCV_TOOLCHAIN_MIRROR/$RISCV_TOOLCHAIN_ARCHIVE && \
    mkdir -p /opt/riscv && \
    tar -C /usr --strip-components=1 -xf $RISCV_TOOLCHAIN_ARCHIVE && \
    rm *.tar.gz
RUN mkdir -p /build
WORKDIR /build
RUN rm /usr/bin/gcov; ln -s /usr/bin/llvm-cov /usr/bin/gcov
