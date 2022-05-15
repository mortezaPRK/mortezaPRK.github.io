gFROM debian:stable-slim


RUN apt update && \
    apt install -y \
       texlive-latex-recommended \
       texlive-fonts-recommended \
       texlive-latex-extra \
       texlive-fonts-extra \
       texlive-lang-all \
       biber && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

