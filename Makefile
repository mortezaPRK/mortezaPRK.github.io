.PHONY: build_hugo run docker_cv_build
.DEFAULT_GOAL := build

STATIC_DIR := static
RESUME_DIR := resume
RESUME_DIR_ABS := $(abspath $(RESUME_DIR))
RESUME_OUT_PATH := $(RESUME_DIR)/out/cv.pdf
RESUME_OUT_STATIC_PATH := $(STATIC_DIR)/cv.pdf


docker_cv_build:
	@echo "Building resume with docker"
	@docker run \
		--rm \
		--workdir="/app" \
		--network=none \
		-v "$(RESUME_DIR_ABS):/app" \
		leplusorg/latex \
		pdflatex -halt-on-error -output-directory=out -output-format=pdf -recorder cv.tex > /dev/null

$(RESUME_OUT_PATH): $(RESUME_DIR)/cv.tex $(RESUME_DIR)/me.jpeg
	@echo "Building resume"
	@rm -rf $(RESUME_DIR)/out
	@mkdir -p $(RESUME_DIR)/out
	@$(MAKE) docker_cv_build
	@$(MAKE) docker_cv_build
	

$(RESUME_OUT_STATIC_PATH): $(RESUME_OUT_PATH)
	@echo "Copying resume to static"
	@cp $(RESUME_OUT_PATH) $(RESUME_OUT_STATIC_PATH)

build_resume: $(RESUME_OUT_STATIC_PATH)

build_hugo:
	@echo "Building hugo"
	hugo

build: build_resume build_hugo

run: build_resume
	@echo "Running hugo"
	@hugo server -D
