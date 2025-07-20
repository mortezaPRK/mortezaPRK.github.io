.PHONY: build_hugo run docker_cv_build
.DEFAULT_GOAL := build

HUGO_VERSION := 0.148.1
HUGO_IMAGE := ghcr.io/gohugoio/hugo:v$(HUGO_VERSION)
STATIC_DIR := static
WORKDIR := $(abspath .)
UID ?= 0
GID ?= 0

#
# Resume
#

YAMLRESUME_IMAGE := ghcr.io/yamlresume/yamlresume:v0.5.1
RESUME_DIR := resume
RESUME_OUT_DIR := $(RESUME_DIR)/out
RESUME_SRC := $(RESUME_DIR)/cv.yml
RESUME_PDF := $(RESUME_OUT_DIR)/cv.pdf
RESUME_STATIC_PDF := $(STATIC_DIR)/cv.pdf

$(RESUME_PDF): $(RESUME_SRC)
	@echo "Building resume"
	@docker run \
		--rm \
		--network=none \
		--workdir="/app/out" \
		-u "$(UID):$(GID)" \
		-v "$(abspath $(RESUME_DIR)):/app" \
		$(YAMLRESUME_IMAGE) \
		build ../cv.yml

$(RESUME_STATIC_PDF): $(RESUME_PDF)
	@cp $(RESUME_PDF) $(RESUME_STATIC_PDF)

#
# End Resume
#

build_static: $(RESUME_STATIC_PDF)

build_hugo: build_static
	@echo "Building hugo"
	@docker run \
		--rm \
		--network=none \
		--env HUGO_ENVIRONMENT=production \
        --env HUGO_ENV=production \
		-u "$(UID):$(GID)" \
		-v "$(WORKDIR):/project" \
		$(HUGO_IMAGE) \
		build --minify $(if $(BASE_URL),--baseURL $(BASE_URL),) $(if $(CI),--noBuildLock, --gc)

build: build_hugo

run: build_static
	@echo "Running hugo"
	@docker run \
		--rm \
		--workdir="/app" \
		-p 1313:1313 \
		-u "$(UID):$(GID)" \
		-v "$(WORKDIR):/project" \
		$(HUGO_IMAGE) \
		server --bind 0.0.0.0 --buildDrafts --watch --disableFastRender

clean:
	@git clean -xdf
