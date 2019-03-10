##
##  LibreSignage makefile
##

# Note: This makefile assumes that $(ROOT) always has a trailing
# slash. (which is the case when using the makefile $(dir ...)
# function) Do not use the shell dirname command here as that WILL
# break things since it doesn't add the trailing slash to the path.
ROOT := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))

SASS_IPATHS := $(ROOT) $(ROOT)src/common/css $(ROOT)/src/node_modules
SASSFLAGS := --no-source-map

# Caller supplied build settings.
VERBOSE ?= Y
NOHTMLDOCS ?= N
CONF ?= ""
TARGET ?=
PASS ?=

# Production libraries.
LIBS := $(filter-out \
	$(shell echo "$(ROOT)"|sed 's:/$$::g'), \
	$(shell npm ls --prod --parseable|sed 's/\n/ /g') \
)

# Non-compiled sources.
SRC_NO_COMPILE := $(shell find src \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o \( -type f -path 'src/api/endpoint/*' -prune \) \
	-o \( \
		-type f ! -name '*.swp' \
		-a -type f ! -name '*.save' \
		-a -type f ! -name '.\#*' \
		-a -type f ! -name '\#*\#*' \
		-a -type f ! -name '*~' \
		-a -type f ! -name '*.js' \
		-a -type f ! -name '*.scss' \
		-a -type f ! -name '*.rst' -print \
	\) \
)

# RST sources.
SRC_RST := $(shell find src \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o -type f -name '*.rst' -print \
) README.rst CONTRIBUTING.rst

# SCSS sources.
SRC_SCSS := $(shell find src \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o -type f -name '*.scss' -a ! -name '_*' -print \
)

# JavaScript sources.
SRC_JS := $(shell find src \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o \( -type f -name 'main.js' -print \) \
)

# API endpoint sources.
SRC_ENDPOINT := $(shell find src/api/endpoint \
	\( -type f -path 'src/node_modules/*' -prune \) \
	-o \( -type f -name '*.php' -print \) \
)

# Generated PNG logo paths.
GENERATED_LOGOS := $(addprefix dist/assets/images/logo/libresignage_,16x16.png 32x32.png 96x96.png text_466x100.png)

status = \
	if [ "`echo '$(VERBOSE)'|cut -zc1|\
		tr '[:upper:]' '[:lower:]'`" = "y" ]; then \
		echo "$(1): $(2) >> $(3)"|tr -s ' '|sed 's/^ *$///g'; \
	fi
makedir = mkdir -p $(dir $(1))

ifeq ($(NOHTMLDOCS),$(filter $(NOHTMLDOCS),y Y))
$(info [Info] Not going to generate HTML documentation.)
endif

.PHONY: initchk configure dirs server js css api \
		config libs docs htmldocs install utest \
		clean realclean LOC
.ONESHELL:

all:: server docs htmldocs js css api libs logo; @:

server:: initchk $(subst src,dist,$(SRC_NO_COMPILE)); @:
js:: initchk $(subst src,dist,$(SRC_JS)); @:
api:: initchk $(subst src,dist,$(SRC_ENDPOINT)); @:
libs:: initchk dist/libs; @:
docs:: initchk $(addprefix dist/doc/rst/,$(notdir $(SRC_RST))) dist/doc/rst/api_index.rst; @:
htmldocs:: initchk $(addprefix dist/doc/html/,$(notdir $(SRC_RST:.rst=.html))); @:
css:: initchk $(subst src,dist,$(SRC_SCSS:.scss=.css)); @:
libs:: initchk $(subst $(ROOT)node_modules/,dist/libs/,$(LIBS)); @:
logo:: initchk $(GENERATED_LOGOS); @:

# Copy over non-compiled, non-PHP sources.
$(filter-out %.php,$(subst src,dist,$(SRC_NO_COMPILE))):: dist%: src%
	@:
	set -e
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

# Copy and prepare PHP files and check the syntax.
$(filter %.php,$(subst src,dist,$(SRC_NO_COMPILE))):: dist%: src%
	@:
	set -e
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@
	$(call status,prep.sh,<inplace>,$@)
	./build/scripts/prep.sh $(CONF) $@
	php -l $@ > /dev/null

# Copy API endpoint PHP files and generate corresponding docs.
$(subst src,dist,$(SRC_ENDPOINT)):: dist%: src%
	@:
	set -e
	php -l $< > /dev/null

	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		# Generate reStructuredText documentation.
		mkdir -p dist/doc/rst
		mkdir -p dist/doc/html
		$(call status,\
			gendoc.sh,\
			<generated>,\
			dist/doc/rst/$(notdir $(@:.php=.rst))\
		)
		./build/scripts/gendoc.sh $(CONF) $@ dist/doc/rst/

		# Compile rst docs into HTML.
		$(call status,\
			pandoc,\
			dist/doc/rst/$(notdir $(@:.php=.rst)),\
			dist/doc/html/$(notdir $(@:.php=.html))\
		)
		pandoc -f rst -t html \
			-o dist/doc/html/$(notdir $(@:.php=.html)) \
			dist/doc/rst/$(notdir $(@:.php=.rst))
	fi

# Generate the API endpoint documentation index.
dist/doc/rst/api_index.rst:: $(SRC_ENDPOINT)
	@:
	set -e
	$(call status,makefile,<generated>,$@)
	$(call makedir,$@)

	. build/scripts/conf.sh
	echo "LibreSignage API documentation (Ver: $$API_VER)" > $@
	echo '########################################################' >> $@
	echo '' >> $@
	echo "This document was automatically generated by the"\
		"LibreSignage build system on `date`." >> $@
	echo '' >> $@
	for f in $(SRC_ENDPOINT); do
		echo "\``basename $$f` </doc?doc=`basename -s '.php' $$f`>\`_" >> $@
		echo '' >> $@
	done

	# Compile into HTML.
	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		$(call status,pandoc,$(subst /rst/,/html/,$($:.rst=.html)),$@)
		$(call makedir,$(subst /rst/,/html/,$@))
		pandoc -f rst -t html -o $(subst /rst/,/html/,$(@:.rst=.html)) $@
	fi

# Copy over RST sources. Try to find prerequisites from
# 'src/doc/rst/' first and then fall back to './'.
dist/doc/rst/%.rst:: src/doc/rst/%.rst
	@:
	set -e
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

dist/doc/rst/%.rst:: %.rst
	@:
	set -e
	$(call status,cp,$<,$@)
	$(call makedir,$@)
	cp -p $< $@

# Compile RST sources into HTML. Try to find prerequisites
# from 'src/doc/rst/' first and then fall back to './'.
dist/doc/html/%.html:: src/doc/rst/%.rst
	@:
	set -e
	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		$(call status,pandoc,$<,$@)
		$(call makedir,$@)
		pandoc -o $@ -f rst -t html $<
	fi

dist/doc/html/%.html:: %.rst
	@:
	set -e
	if [ ! "$$NOHTMLDOCS" = "y" ] && [ ! "$$NOHTMLDOCS" = "Y" ]; then
		$(call status,pandoc,$<,$@)
		$(call makedir,$@)
		pandoc -o $@ -f rst -t html $<
	fi

# Generate JavaScript deps.
dep/%/main.js.dep: src/%/main.js
	@:
	set -e
	$(call status,deps-js,$<,$@)
	$(call makedir,$@)

	# Echo dependency makefile contents.
	echo "$(subst src,dist,$<):: `npx browserify --list $<|\
		tr '\n' ' '|\
		sed 's:$(ROOT)::g'`" > $@

	echo "\t@:" >> $@
	echo "\t\$$(call status,"\
		"compile-js,"\
		"$<,"\
		"$(subst src,dist,$<))" >> $@
	echo "\t\$$(call makedir,$(subst src,dist,$<))" >> $@
	echo "\tnpx browserify $< -o $(subst src,dist,$<)" >> $@

# Generate SCSS deps.
dep/%.scss.dep: src/%.scss
	@:
	set -e
	# Don't create deps for partials.
	if [ ! "`basename '$(<)' | cut -c 1`" = "_" ]; then
		$(call status,deps-scss,$<,$@)
		$(call makedir,$@)

		# Echo dependency makefile contents.
		echo "$(subst src,dist,$(<:.scss=.css)):: $< `\
			./build/scripts/sassdep.py -l $< $(SASS_IPATHS)|\
			sed 's:$(ROOT)::g'`" > $@
		echo "\t@:" >> $@
		echo "\t\$$(call status,"\
			"compile-scss,"\
			"$<,"\
			"$(subst src,dist,$(<:.scss=.css)))" >> $@
		echo "\t\$$(call makedir,$(subst src,dist,$<))" >> $@
		echo "\tnpx sass"\
			"$(addprefix -I,$(SASS_IPATHS))"\
			"$(SASSFLAGS)"\
			"$<"\
			"$(subst src,dist,$(<:.scss=.css))" >> $@
		echo "\tnpx postcss"\
			"$(subst src,dist,$(<:.scss=.css))"\
			"--config postcss.config.js"\
			"--replace"\
			"--no-map" >> $@
	fi

# Copy production node modules to 'dist/libs/'.
dist/libs/%:: node_modules/%
	@:
	set -e
	mkdir -p $@
	$(call status,cp,$<,$@)
	cp -Rp $</* $@

# Convert the LibreSignage SVG logos to PNG logos of various sizes.
.SECONDEXPANSION:
$(GENERATED_LOGOS): dist/%.png: src/$$(shell echo '$$*' | rev | cut -f 2- -d '_' | rev).svg
	@:
	set -e
	. build/scripts/convert_images.sh
	SRC_DIR=`dirname $(@) | sed 's:dist:src:g'`
	DEST_DIR=`dirname $(@)`
	NAME=`basename $(lastword $^)`
	SIZE=`echo $(@) | rev | cut -f 2 -d '.' | cut -f 1 -d '_' | rev`
	svg_to_png "$$SRC_DIR" "$$DEST_DIR" "$$NAME" "$$SIZE"

##
##  PHONY targets
##

install:
	@:
	set -e
	./build/scripts/install.sh $(CONF)

configure:
	@:
	set -e
	if [ -z "$(TARGET)" ]; then
		echo "[Error] Specify a target using 'TARGET=[target]'."
		exit 1
	fi
	target="--target $(TARGET)"

	./build/scripts/configure_build.sh $$target $(PASS)
	./build/scripts/configure_system.sh

utest:
	@:
	set -e
	./utests/api/main.py

clean:
	@:
	set -e
	$(call status,rm,dist,none)
	rm -rf dist
	$(call status,rm,dep,none)
	rm -rf dep
	$(call status,rm,*.log,none)
	rm -f *.log

	for f in '__pycache__' '.sass-cache' '.mypy_cache'; do
		TMP="`find . -type d -name $$f -printf '%p '`"
		if [ ! -z "$$TMP" ]; then
			$(call status,rm,$$TMP,none)
			rm -rf $$TMP
		fi
	done

realclean:
	@:
	set -e
	$(call status,rm,build/*.iconf,none);
	rm -f build/*.iconf
	$(call status,rm,build/link,none);
	rm -rf build/link
	$(call status,rm,node_modules,none);
	rm -rf node_modules
	$(call status,rm,server,none)
	rm -rf server
	$(call status,rm,package-lock.json,none);
	rm -f package-lock.json

	# Remove temporary nano files.
	TMP="`find . \
		\( -type d -path './node_modules/*' -prune \) \
		-o \( \
			-type f -name '*.swp' -printf '%p ' \
			-o  -type f -name '*.save' -printf '%p ' \
		\)`"
	if [ ! -z "$$TMP" ]; then
		$(call status,rm,$$TMP,none)
		rm -f $$TMP
	fi

	# Remove temporary emacs files.
	TMP="`find . \
		\( -type d -path './node_modules/*' -prune \) \
		-o \( \
			 -type f -name '\#*\#*' -printf '%p ' \
			-o -type f -name '*~' -printf '%p ' \
		\)`"
	if [ ! -z "$$TMP" ]; then
		$(call status,rm,$$TMP,none)
		rm -f $$TMP
	fi


# Count the lines of code in LibreSignage.
LOC:
	@:
	set -e
	echo 'Lines Of Code: '
	wc -l `find . \
		\( \
			-path "./dist/*" -o \
			-path "./utests/api/.mypy_cache/*" -o \
			-path "./node_modules/*" \
		\) -prune \
		-o -name ".#*" \
		-o -name "*.py" -print \
		-o -name "*.php" -print \
		-o -name "*.js" -print \
		-o -name "*.html" -print \
		-o -name "*.css" -print \
		-o -name "*.scss" -print \
		-o -name "*.sh" -print \
		-o -name "Dockerfile" -print \
		-o -name "makefile" -print \
		-o ! -name 'package-lock.json' -name "*.json" -print \
		-o -name "*.py" -print`

LOD:
	@:
	set -e
	echo '[Info] Make sure your 'dist/' is up to date!'
	echo '[Info] Lines Of Documentation: '
	wc -l `find dist -type f -name '*.rst'`

initchk:
	@:
	set -e
	./build/scripts/ldconf.sh $(CONF)

%:
	@:
	set -e
	echo "[Info]: Ignore $@"

ifeq (,$(filter LOC LOD clean realclean configure initchk,$(MAKECMDGOALS)))
$(info [Info] Include dependency makefiles.)
-include $(subst src,dep,$(SRC_JS:.js=.js.dep))\
		$(subst src,dep,$(SRC_SCSS:.scss=.scss.dep))
endif
