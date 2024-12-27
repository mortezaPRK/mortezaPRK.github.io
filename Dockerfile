FROM debian:bullseye-slim AS hugo

WORKDIR /app

RUN apt update && apt install -y wget

ARG HUGO_VERSION=0.140.1
ARG DART_SASS_VERSION=1.83.0

RUN wget -O hugo.tar.gz \
        https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz && \
    tar -xvf hugo.tar.gz && \
    wget -O /dart-sass.tar.gz \
        https://github.com/sass/dart-sass/releases/download/${DART_SASS_VERSION}/dart-sass-${DART_SASS_VERSION}-linux-x64.tar.gz && \
    tar -xvf /dart-sass.tar.gz

ARG LATEX_VERSION=sha-8a7948a
FROM leplusorg/latex:${LATEX_VERSION} AS latex

COPY --from=hugo /app/hugo /usr/local/bin/hugo
COPY --from=hugo /dart-sass /usr/local/bin/dart-sass

RUN ln -s /usr/local/bin/dart-sass/sass /usr/local/bin/sass && \
    chmod +x /usr/local/bin/hugo /usr/local/bin/sass

WORKDIR /resume

COPY ./resume .

