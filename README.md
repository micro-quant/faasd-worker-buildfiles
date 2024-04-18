# Faasd Worker Buildfiles

This repo is solely used for containing public build files (Dockerfile and deployment.yaml) that are read by GCP Cloud Build to build and deploy the faasd-worker images to GKE.

## Ways to automate the build and deployment of an app to GKE using CloudBuild

- Dockerfile
- cloudbuild.yaml (inline or a cloudbuild.yaml in the parent repo)
  - in here, we could use a custom cloud-builder or even buildpack
- buildpack

## Why?

There are several ways to automate the build and deployment of an app to GKE using CloudBuild (see below) but there are several reasons that we do it using an inline cloudbuild file.

Requirements we have:
- The repos that trigger a build+deploy cannot own the Dockerfile b/c then developers can make potentially malicious changes that affect the cloud env
- The build and deployment should be cloud-agnostic
- Build and Deployment management should be scalable


We could (and actually did at one point - [see here](https://github.com/micro-quant/faasd-worker/tree/74b9c4a4d57f3840bf91f29087731730016b2b0a)) use a custom Cloud Builder to build and deploy the images but this is more complex and requires more maintenance than an inline cloudbuild file and this also is not cloud agnostic.  Switching off of this, we went from a faasd-worker build time of ~7min to ~1:30min and an examples build time of ~4min to ~1:30min

The current approach we use, an inline cloudbuild.yaml, is not _cloud agnostic_ but it is very simple (albeit, might be more challenging at scale) and simple - which means we could remove it if ever needed

We can't use a Dockerfile deployment alone b/c GCP requires the Dockerfile is in the same repo as the repo that triggers the build

We can't use a cloudbuild.yaml in the parent repo b/c the parent repo is not the repo that triggers the build

We could use buildpack (and some research was done to actually get a [working example](https://github.com/micro-quant/faasd-worker-buildpack)) but this is more complex.  However, this is a good option for the future because it is both cloud agnostic and scalable

## Fassd Worker Repo Cloud Build Config

This config is the cloudbuild config used to build and deploy the faasd-worker images to GKE.

There is 1 _major_ issue with this because the kube cluster is private so a default builder cannot access it.  To get around it, we could create a private pool (see References at the bottom) but this costs (by my best estimates) an additional $2/day due to the machine, and vpc costs - but more imporantly; [I couldnt get this to work](https://github.com/micro-quant/faasd-worker-buildfiles/build_to_private_gke.sh)...  So instead, the below cloudbuild.yaml has a hack which whitelists the IP of the machine it is run on - this eventually needs to be replaced, probably with the private pool VPC method.

```yaml
steps:
  - name: gcr.io/cloud-builders/wget
    args:
      - $_DOCKERFILE_PATH
  - name: gcr.io/cloud-builders/wget
    args:
      - $_K8S_YAML_PATH
  - name: bash
    script: |
      #!/bin/sh
      sed -i "s#@IMAGE_NAME@#$IMG_NAME_AND_VER#g" deployment.yaml
	env:
    - IMG_NAME_AND_VER="$_IMAGE_NAME:$_IMAGE_VERSION"
  - name: gcr.io/cloud-builders/docker
    args:
      - build
      - '-t'
      - '$_IMAGE_NAME:$_IMAGE_VERSION'
      - '--build-arg'
      - APP_NAME=$REPO_NAME
      - .
    id: Build
  - name: gcr.io/cloud-builders/docker
    args:
      - push
      - '$_IMAGE_NAME:$_IMAGE_VERSION'
    id: Push
  - name: "gcr.io/cloud-builders/gcloud"
    script: |
      #!/usr/bin/env bash
      apt-get update
      apt-get install dnsutils -y
      my_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
      gcloud container clusters get-credentials --project=test-clientmq --region=$_GKE_LOCATION $_GKE_CLUSTER
      ips_sep_by_comma=$(gcloud container clusters describe $_GKE_CLUSTER --project=test-clientmq --zone=$_GKE_LOCATION --format='value(masterAuthorizedNetworksConfig.cidrBlocks[].cidrBlock.list())')
      gcloud container clusters update $_GKE_CLUSTER --project=$PROJECT_ID --zone=$_GKE_LOCATION --enable-master-authorized-networks --master-authorized-networks "$ips_sep_by_comma,$my_ip/32"
      kubectl apply -f deployment.yaml
      gcloud container clusters update $_GKE_CLUSTER --project=$PROJECT_ID --zone=$_GKE_LOCATION --enable-master-authorized-networks --master-authorized-networks "$ips_sep_by_comma"
    id: Apply deploy
images:
  - '$_IMAGE_NAME:$_IMAGE_VERSION'
options:
  substitutionOption: ALLOW_LOOSE
  dynamicSubstitutions: true
substitutions:
  _IMAGE_NAME: 'europe-west1-docker.pkg.dev/${PROJECT_ID}/artifacts/${REPO_NAME}'
  _IMAGE_VERSION: '${COMMIT_SHA}'
  _K8S_YAML_PATH: >-
    https://raw.githubusercontent.com/micro-quant/faasd-worker-dockerfile/main/deployment.yaml
  _GKE_CLUSTER: default-cluster
  _GKE_LOCATION: europe-west1-b
  _DOCKERFILE_PATH: >-
    https://raw.githubusercontent.com/micro-quant/faasd-worker-dockerfile/main/Dockerfile
```

## References

- old cloudbuild.yaml we used to use when we used a [custom cloud builder](https://github.com/micro-quant/faasd-worker/tree/74b9c4a4d57f3840bf91f29087731730016b2b0a)

```yaml
steps:
  - name: >-
	  europe-west1-docker.pkg.dev/mqplatform/external/faasd-worker:fcbefbe8289d3fb8eddd371fd50c297b9a6b41f8
	args:
	  - $PROJECT_ID
	  - 'europe-west1-docker.pkg.dev/$PROJECT_ID/artifacts/$REPO_NAME:$COMMIT_SHA'
	  - $REPO_NAME
```

- [Deploying to a private GKE cluster](https://cloud.google.com/build/docs/private-pools/accessing-private-gke-clusters-with-cloud-build-private-pools)