.PHONY: build_hugo build_static run docker_cv_build
.DEFAULT_GOAL := build

STATIC_DIR := static
RESUME_DIR := resume
RESUME_DIR_ABS := $(abspath $(RESUME_DIR))
RESUME_OUT_PATH := $(RESUME_DIR)/out/cv.pdf
RESUME_OUT_STATIC_PATH := $(STATIC_DIR)/cv.pdf
PORTRAIT_OUT_PATH := $(RESUME_DIR)/me.jpeg
PORTRAIT_OUT_STATIC_PATH := $(STATIC_DIR)/me.jpeg


docker_cv_build:
	@echo "Building resume with docker"
	@docker run \
		--rm \
		--workdir="/app" \
		--network=none \
		-u "0:0" \
		-v "$(RESUME_DIR_ABS):/app" \
		leplusorg/latex \
		pdflatex -halt-on-error -output-directory=out -output-format=pdf -recorder cv.tex > /dev/null

$(RESUME_OUT_PATH): $(RESUME_DIR)/cv.tex $(PORTRAIT_OUT_PATH)
	@echo "Building resume"
	@rm -rf $(RESUME_DIR)/out
	@mkdir -p $(RESUME_DIR)/out
	@$(MAKE) docker_cv_build
	@$(MAKE) docker_cv_build


$(RESUME_OUT_STATIC_PATH): $(RESUME_OUT_PATH)
	@echo "Copying resume to static"
	@cp $(RESUME_OUT_PATH) $(RESUME_OUT_STATIC_PATH)

$(PORTRAIT_OUT_STATIC_PATH): $(PORTRAIT_OUT_PATH)
	@echo "Copying portrait to static"
	@cp $(PORTRAIT_OUT_PATH) $(PORTRAIT_OUT_STATIC_PATH)


build_static: $(RESUME_OUT_STATIC_PATH) $(PORTRAIT_OUT_STATIC_PATH)

build_hugo: build_static
	@echo "Building hugo"
	hugo --gc --minify $(if $(BASE_URL),--baseURL $(BASE_URL),)

build: build_static build_hugo

run: build_static
	@echo "Running hugo"
	@hugo server -D
