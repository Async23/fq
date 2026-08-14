SWIFT ?= swift
PREFIX ?= $(HOME)/.local
BINARY = .build/release/fq

.PHONY: build release test format format-check check install

build:
	$(SWIFT) build

release:
	$(SWIFT) build -c release

test:
	$(SWIFT) test

format:
	$(SWIFT) format format --in-place --recursive Sources Tests Package.swift

format-check:
	$(SWIFT) format lint --recursive --strict Sources Tests Package.swift

check: format-check test release

install: release
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 0755 "$(BINARY)" "$(DESTDIR)$(PREFIX)/bin/fq"
