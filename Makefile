image:
	docker build -t iskra/jenkins-slave:14 . --platform linux/amd64
	docker push iskra/jenkins-slave:14

push:
	docker push iskra/jenkins-slave:14
