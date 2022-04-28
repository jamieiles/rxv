FROM rxv-build:latest
MAINTAINER Jamie Iles <jamie@jamieiles.com>
ARG USERNAME=devuser
RUN apt-get install -y gpg curl
RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg && \
        install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/ && \
        sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" > /etc/apt/sources.list.d/vscode.list'
RUN wget https://github.com/chipsalliance/verible/releases/download/v0.0-1735-g0d1c9364/verible-v0.0-1735-g0d1c9364-Ubuntu-20.04-focal-x86_64.tar.gz && \
	tar xf verible-v0.0-1735-g0d1c9364-Ubuntu-20.04-focal-x86_64.tar.gz && \
	cp -r verible-v0.0-1735-g0d1c9364/* /usr/ && \
	rm -r verible*
RUN apt-get update && apt-get install -y runit \
        gtkwave \
        gdb \
        sudo \
        code \
        fzf \
        less \
	build-essential \
	libgtk-3-dev \
	autoconf \
	automake \
	libbz2-dev
ADD docker/dev/rxv-dev /usr/bin/rxv-dev
ENV CTEST_OUTPUT_ON_FAILURE=1
ENV GTEST_COLOR=1
RUN useradd -ms /bin/bash -G sudo,adm devuser
RUN echo "%sudo   ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
RUN mkdir -p /home/devuser/.vscode-server/extensions \
        /home/devuser/.vscode-server-insiders/extensions \
    && chown -R devuser \
        /home/devuser/.vscode-server \
        /home/devuser/.vscode-server-insiders
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
        && mkdir /commandhistory \
        && touch /commandhistory/.bash_history \
        && chown -R $USERNAME /commandhistory \
        && echo $SNIPPET >> "/home/$USERNAME/.bashrc"
RUN cd /tmp && \
	git clone https://github.com/gtkwave/gtkwave.git && \
	cd gtkwave/gtkwave3-gtk3/ && \
	./autogen.sh && \
	./configure --prefix=/usr --enable-gtk3 --disable-tcl && \
	make && \
	sudo make install && \
	cd /tmp && \
	rm -rf gtkwave
ENTRYPOINT ["/usr/bin/rxv-dev"]
