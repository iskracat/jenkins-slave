IMAGE ?= iskra/jenkins-slave
TAG ?= 20
PLATFORM ?= linux/amd64

.DEFAULT_GOAL := help

.PHONY: help build image push test

help:
	@echo 'targets:'
	@echo '  build   build $(IMAGE):$(TAG) for $(PLATFORM) locally, never pushes'
	@echo '  image   legacy: build and push $(IMAGE):$(TAG)'
	@echo '  push    push an existing $(IMAGE):$(TAG)'
	@echo '  test    behaviour tests of iskra-toolchain with fixture directories'

build:
	docker build -t $(IMAGE):$(TAG) --platform $(PLATFORM) .

image:
	docker build -t $(IMAGE):$(TAG) --platform $(PLATFORM) .
	docker push $(IMAGE):$(TAG)

push:
	docker push $(IMAGE):$(TAG)

test:
	bash tests/selector.test.sh
