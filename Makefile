image:
	docker build -t iskra/jenkins-slave:13 . --platform linux/amd64
	docker push iskra/jenkins-slave:13

push:
	docker push iskra/jenkins-slave:13
