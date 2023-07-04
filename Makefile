image:
	docker build -t iskra/jenkins-slave:4 . --platform linux/amd64
	docker push iskra/jenkins-slave:4
