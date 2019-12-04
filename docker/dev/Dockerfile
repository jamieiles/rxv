FROM rxv-build:latest
MAINTAINER Jamie Iles <jamie@jamieiles.com>
RUN apt-get install -y gpg curl
RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg && \
        install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/ && \
        sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
RUN apt-get update && apt-get install -y runit \
        gtkwave \
        gdb \
        sudo \
        code
ADD rxv-dev /usr/bin/rxv-dev
ENV CTEST_OUTPUT_ON_FAILURE=1
ENV GTEST_COLOR=1
ENTRYPOINT ["/usr/bin/rxv-dev"]
