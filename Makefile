.PHONY: build_hugo run docker_cv_build
.DEFAULT_GOAL := build

STATIC_DIR := static


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
		-u "0:0" \
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
	@hugo --gc --minify $(if $(BASE_URL),--baseURL $(BASE_URL),)

build: build_hugo

run: build_static
	@echo "Running hugo"
	@hugo server -D

clean:
	@git clean -xdf
