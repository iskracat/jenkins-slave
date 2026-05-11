IMAGE ?= iskra/jenkins-slave
TAG ?= 18

image:
	docker build -t $(IMAGE):$(TAG) . --platform linux/amd64
	docker push $(IMAGE):$(TAG)

push:
	docker push $(IMAGE):$(TAG)
