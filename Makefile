# NIMBIX CONFIDENTIAL
# -------------------
#
# Copyright (c) 2016 Nimbix, Inc.  All Rights Reserved.
#
# NOTICE:  All information contained herein is, and remains the property of
# Nimbix, Inc. and its suppliers, if any.  The intellectual and technical
# concepts contained herein are proprietary to Nimbix, Inc.  and its suppliers
# and may be covered by U.S. and Foreign Patents, patents in process, and are
# protected by trade secret or copyright law.  Dissemination of this
# information or reproduction of this material is strictly forbidden unless
# prior written permission is obtained from Nimbix, Inc.
#
# Author: Stephen Fox (stephen.fox@nimbix.net)

image: Dockerfile
	docker build -t openfoam .

tag: image
	docker tag openfoam jarvice/openfoam:latest && docker tag openfoam jarvice/openfoam:4

all : tag
	docker push jarvice/openfoam:latest && docker push jarvice/openfoam:4
