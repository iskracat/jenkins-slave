image:
	docker build -t iskra/jenkins-slave:15 . --platform linux/amd64
	docker push iskra/jenkins-slave:15

push:
	docker push iskra/jenkins-slave:14
