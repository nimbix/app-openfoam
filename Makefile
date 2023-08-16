SHELL := /bin/bash

appdef-com:
	sed "s,OPENFOAM_VERSION,v2306," NAE/AppDef.json > NAE/AppDef-com.json
	sed -i "s,OPENFOAM_AUTHOR,OpenCFD Ltd," NAE/AppDef-com.json
	sed -i "s,OPENFOAM_LOGO_GOES_HERE,$$(cat NAE/openfoam-com.png | base64 -w0)," NAE/AppDef-com.json

appdef-org:
	sed "s,OPENFOAM_VERSION,11," NAE/AppDef.json > NAE/AppDef-org.json
	sed -i "s,OPENFOAM_AUTHOR,OpenFOAM Foundation\, inc," NAE/AppDef-org.json
	sed -i "s,OPENFOAM_LOGO_GOES_HERE,$$(cat NAE/openfoam-org.png | base64 -w0)," NAE/AppDef-org.json

org: appdef-org
	DOCKER_BUILDKIT=1 docker build --pull --rm -f "Dockerfile.org" -t us-docker.pkg.dev/jarvice/images/app-openfoam:11-test --build-arg OPENFOAM_VERSION=11 "."

com: appdef-com
	DOCKER_BUILDKIT=1 docker build --pull --rm -f "Dockerfile.com" -t us-docker.pkg.dev/jarvice/images/app-openfoam:2306 --build-arg OPENFOAM_VERSION=v2306 "."

push-com: com
	docker push us-docker.pkg.dev/jarvice/images/app-openfoam:2306

push-org: org
	docker push us-docker.pkg.dev/jarvice/images/app-openfoam:11-test

all: org com

push-all: push-org push-com
