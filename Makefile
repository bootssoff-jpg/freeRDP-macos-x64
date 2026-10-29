SHELL := /bin/bash

.PHONY: all freerdp app test run dist clean clean-vendor

all: app

freerdp:
	./scripts/build_freerdp.sh

app: freerdp
	./scripts/build_app.sh

test:
	./scripts/run_tests.sh

run: app
	open "build/RDP Mac.app"

dist: app
	@ls -lh build/dist
	@echo "Unsigned local build: build/RDP Mac.app"

clean:
	rm -rf build

clean-vendor:
	rm -rf vendor/FreeRDP-3.32.2 vendor/build-freerdp vendor/freerdp-install \
	       vendor/freerdp-*.tar.gz vendor/freerdp-build.log
