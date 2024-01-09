image:
	docker build -t iskra/jenkins-slave:12 . --platform linux/amd64
	docker push iskra/jenkins-slave:12

push:
	docker push iskra/jenkins-slave:12
