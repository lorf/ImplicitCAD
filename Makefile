# ImplicitCAD Makefile. Build and test Implicitcad.


## Locations of binaries used when running tests, or generating the images to go along with our README.md.
# the location of stl2ps, from stltools, available from https://github.com/rsmith-nl/stltools/tree/develop
stl2ps=/disk4/faikvm.com/stltools/stltools/stl2ps.py
# the location of convert, from imagemagick
convert=convert
# the location of GHC, used to compile .hs examples.
GHC=ghc
# the location of the created extopenscad binary, for running shell based test cases.
EXTOPENSCAD=dist/build/extopenscad/extopenscad
# the location of the benchmark binary, for benchmarking some implicitcad internals.
BENCHMARK=dist/build/Benchmark/Benchmark
# the location of the parser benchmark binary, specifically for benchmarking implicitcad's parser.
PARSERBENCH=dist/build/parser-bench/parser-bench
# the location of the created test binary, for running haskell test cases.
TESTSUITE=dist/build/test-implicit/test-implicit
# the location of it's source.
TESTFILES=$(shell find tests/ParserSpec -name '*.hs')
# the location of the documentation generator. for documenting (some of) the extopenscad language.
DOCGEN=dist/build/docgen/docgen

## options used when calling ImplicitCAD. for testing, and for image generation.
# enable multiple CPU usage.
RTSOPTS=+RTS -N
# the resolution to generate objects at. FIXME: what does this mean in human terms? 
RESOPTS=-r 50

#uncomment for profiling support. Note that you will need to recompile all of the libraries, as well.
#PROFILING= --enable-library-profiling --enable-executable-profiling

LIBFILES=$(shell find Graphics -name '*.hs')
LIBTARGET=dist/build/Graphics/Implicit.o

EXECTARGETS=$(EXTOPENSCAD) $(BENCHMARK) $(TESTSUITE) $(PARSERBENCH) $(DOCGEN)
TARGETS=$(EXECTARGETS) $(LIBTARGET)

# mark the below fake targets as unrean, so make will not get choked up if a file with one of these names is created.
.PHONY: build install clean distclean nukeclean docs dist examples tests

# empty out the default suffix list, to make debugging output cleaner.
.SUFFIXES:

# allow for us to (ab)use $$* in dependencies of rules.
.SECONDEXPANSION:

# disable make's default builtin rules, to make debugging output cleaner.
MAKEFLAGS += --no-builtin-rules

# build implicitcad binaries.
build: $(TARGETS)

# install implicitcad.
install: build
	cabal install

# cleanup from using the rules in this file.
clean: Setup
	rm -f Examples/*.stl
	rm -f Examples/*.svg
	rm -f Examples/*.ps
	rm -f Examples/*.png
	rm -f Examples/example[0-9][0-9]
	rm -f Examples/*.hi
	rm -f Examples/*.o
	rm -f tests/*.stl
	rm -rf docs/parser.md
	rm -f $(TARGETS)
	rm -rf dist/build/Graphics
	rm -f dist/build/libHS*

# clean up before making a release.
distclean: clean Setup
	./Setup clean
	rm -f Setup Setup.hi Setup.o
	rm -rf dist/
	rm -f `find ./ -name *~`
	rm -f `find ./ -name \#*\#`

# destroy the current user's cabal/ghc environment.
nukeclean: distclean
	rm -rf ~/.cabal/ ~/.ghc/

# Generate documentation.
docs: $(DOCGEN)
	./Setup haddock
	$(DOCGEN) > docs/escad.md

# Upload to hackage?
dist: $(TARGETS)
	./Setup sdist

# generate examples.
examples: $(EXTOPENSCAD)
	cd Examples && for each in `find ./ -name '*scad' -type f | sort`; do { valgrind --tool=cachegrind  --cachegrind-out-file=$$each.cachegrind.`date +%s` ../$(EXTOPENSCAD) $$each ${RTSOPTS}; } done
	cd Examples && for each in `find ./ -name '*.hs' -type f | sort`; do { filename=$(basename "$$each"); filename="$${filename%.*}"; $(GHC) $$filename.hs -o $$filename; $$filename; } done

# generate images from the examples, so we can upload the images to our website.
images: examples
	cd Examples && for each in `find ./ -name '*.stl' -type f | sort`; do { filename=$(basename "$$each"); filename="$${filename%.*}"; if [ -e $$filename.transform ] ; then echo ${stl2ps} $$each $$filename.ps `cat $$filename.transform`; else ${stl2ps} $$each $$filename.ps; fi; ${convert} $$filename.ps $$filename.png; } done

# hspec parser tests.
tests: $(TESTSUITE) $(TESTFILES)
#	cd tests && for each in `find ./ -name '*scad' -type f | sort`; do { ../$(EXTOPENSCAD) $$each ${RESOPTS} ${RTSOPTS}; } done
	$(TESTSUITE)

# The ImplicitCAD library.
$(LIBTARGET): $(LIBFILES)
	cabal build implicit

# the test suite, since it's source is stored in a different location than the other binaries we build:
dist/build/test-implicit/test-implicit: $(TESTFILES) Setup dist/setup-config $(LIBTARGET) $(LIBFILES)
	cabal build test-implicit


# build a binary target with cabal.
dist/build/%: programs/$$(word 2,$$(subst /, ,%)).hs Setup dist/setup-config $(LIBTARGET) $(LIBFILES)
	cabal build $(word 2,$(subst /, ,$*))

# prepare to build.
dist/setup-config: Setup implicit.cabal
	cabal update
	cabal install --only-dependencies --upgrade-dependencies
	cabal configure --enable-tests --enable-benchmarks $(PROFILING)

# the setup command, used to perform administrative tasks (haddock, upload to hackage, clean, etc...).
Setup: Setup.*hs
	ghc -O2 -Wall --make Setup

