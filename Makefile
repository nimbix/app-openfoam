SHELL := /bin/bash

OPENFOAM_COM_VERSION := v2406
OPENFOAM_ORG_VERSION := 12

DATE := $(shell date +"%Y-%m-%d")

IMAGE_COM := us-docker.pkg.dev/jarvice/images/app-openfoam:$(OPENFOAM_COM_VERSION)-$(DATE)
IMAGE_ORG := us-docker.pkg.dev/jarvice/images/app-openfoam:$(OPENFOAM_ORG_VERSION)-$(DATE)

appdef-com:
	sed "s,OPENFOAM_VERSION,$(OPENFOAM_COM_VERSION)," NAE/AppDef.json > NAE/AppDef-com.json
	sed -i "s,OPENFOAM_AUTHOR,OpenCFD Ltd," NAE/AppDef-com.json
	sed -i "s,OPENFOAM_LOGO_GOES_HERE,$$(cat NAE/openfoam-com.png | base64 -w0)," NAE/AppDef-com.json

appdef-org:
	sed "s,OPENFOAM_VERSION,$(OPENFOAM_ORG_VERSION)," NAE/AppDef.json > NAE/AppDef-org.json
	sed -i "s,OPENFOAM_AUTHOR,OpenFOAM Foundation\, inc," NAE/AppDef-org.json
	sed -i "s,OPENFOAM_LOGO_GOES_HERE,$$(cat NAE/openfoam-org.png | base64 -w0)," NAE/AppDef-org.json

org: appdef-org
	podman build --jobs 0 --pull --format docker --rm -f "Dockerfile.org" -t $(IMAGE_ORG) --build-arg OPENFOAM_VERSION=$(OPENFOAM_ORG_VERSION) "."

com: appdef-com
	podman build --jobs 0 --pull --format docker --rm -f "Dockerfile.com" -t $(IMAGE_COM) --build-arg OPENFOAM_VERSION=$(OPENFOAM_COM_VERSION) "."

push-com: com
	podman push $(IMAGE_COM)

push-org: org
	podman push $(IMAGE_ORG)

all: org com

push-all: push-org push-com
