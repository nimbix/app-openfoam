org:
	DOCKER_BUILDKIT=1 docker build --pull --rm -f "Dockerfile.org" -t us-docker.pkg.dev/jarvice/images/app-openfoam:10 "."

com:
	DOCKER_BUILDKIT=1 docker build --pull --rm -f "Dockerfile.com" -t us-docker.pkg.dev/jarvice/images/app-openfoam:2212 --build-arg OBJ=v2212 "."

push-com: com
	docker push us-docker.pkg.dev/jarvice/images/app-openfoam:2212
