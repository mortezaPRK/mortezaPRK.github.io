## TODO
* Missing
   * Soft skill,
   * Summary statement,
   * Design,
   * High level
   * Measurable impact
     > We found 1 mentions of measurable results in your resume. Consider adding at least 5 specific achievements or 

## Running
```shell
# clone AltaCV
git clone --depth 1 --branch "2023.12.31" https://github.com/mortezaPRK/AltaCV.git altacv
# Create output dir
mkdir out
# Run pdflatex twice to compile
docker run --rm --workdir="/app" --network=none -v "$(pwd):/app" leplusorg/latex pdflatex -halt-on-error -output-directory=out -output-format=pdf -recorder cv.tex
docker run --rm --workdir="/app" --network=none -v "$(pwd):/app" leplusorg/latex pdflatex -halt-on-error -output-directory=out -output-format=pdf -recorder cv.tex
```