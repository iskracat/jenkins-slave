image:
	docker build -t iskra/jenkins-slave:6 . --platform linux/amd64
	docker push iskra/jenkins-slave:6
