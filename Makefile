SHELL := /bin/bash

.PHONY: all openssl freerdp app test run dist release clean clean-vendor

all: app

openssl:
	./scripts/build_openssl.sh

freerdp: openssl
	./scripts/build_freerdp.sh

app: freerdp
	./scripts/build_app.sh

test:
	./scripts/run_tests.sh

run: app
	open "build/RDP Mac.app"

dist: app
	./scripts/package_release.sh

release: dist
	@echo "Release artifacts are in build/dist"

clean:
	rm -rf build

clean-vendor:
	rm -rf vendor/FreeRDP-3.32.2 vendor/build-freerdp vendor/freerdp-install \
	       vendor/openssl-3.6.4 vendor/build-openssl vendor/openssl-install \
	       vendor/openssl-3.6.4.tar.gz vendor/openssl-3.6.4.tar.gz.part \
	       vendor/freerdp-*.tar.gz vendor/*-build.log
