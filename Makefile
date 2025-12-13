.PHONY: build_hugo run clean cv-all build_static
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

YAMLRESUME_IMAGE := ghcr.io/yamlresume/yamlresume:v0.8.1
RESUME_DIR := resume
RESUME_OUT_DIR := $(RESUME_DIR)/out
CV_VARIANTS := general startup scaleup enterprise freelance

CV_SOURCES := $(addprefix $(RESUME_DIR)/cv-,$(addsuffix .yml,$(CV_VARIANTS)))
CV_OUTPUTS := $(addprefix $(RESUME_OUT_DIR)/cv-,$(addsuffix .pdf,$(CV_VARIANTS)))
CV_STATIC := $(addprefix $(STATIC_DIR)/cv-,$(addsuffix .pdf,$(CV_VARIANTS)))

# Build a CV: make resume/out/cv-general.pdf
$(RESUME_OUT_DIR)/cv-%.pdf: $(RESUME_DIR)/cv-%.yml
	@echo "Building CV: $*"
	@mkdir -p $(RESUME_OUT_DIR)
	@docker run \
		--rm \
		--network=none \
		--workdir="/app" \
		-u "$(UID):$(GID)" \
		-v "$(abspath $(RESUME_DIR)):/app:z" \
		$(YAMLRESUME_IMAGE) \
		build cv-$*.yml -o out

$(STATIC_DIR)/cv-%.pdf: $(RESUME_OUT_DIR)/cv-%.pdf
	@cp $< $@

# Build all CV variants
cv-all: $(CV_OUTPUTS)

#
# End Resume
#

build: $(CV_STATIC)
	@cp $(STATIC_DIR)/cv-general.pdf $(STATIC_DIR)/cv.pdf
	@echo "Building hugo"
	@docker run \
		--rm \
		--network=none \
		--env HUGO_ENVIRONMENT=production \
		--env HUGO_ENV=production \
		-u "$(UID):$(GID)" \
		-v "$(WORKDIR):/project:z" \
		$(HUGO_IMAGE) \
		build --minify $(if $(BASE_URL),--baseURL $(BASE_URL),) $(if $(CI),--noBuildLock, --gc)

run: $(CV_STATIC)
	@echo "Running hugo"
	@docker run \
		--rm \
		-p 1313:1313 \
		-u "$(UID):$(GID)" \
		-v "$(WORKDIR):/project:z" \
		$(HUGO_IMAGE) \
		server --bind 0.0.0.0 --buildDrafts --watch --disableFastRender

clean:
	@git clean -xdf
