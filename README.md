# Faasd Worker Dockerfile

This repo is solely used for containing public build files (Dockerfile and deployment.yaml) that are read by GCP Cloud Build to build and deploy the faasd-worker images to GKE.

## Why?

There are several ways to automate the build and deployment of an app to GKE using CloudBuild (see below) but there are several reasons that we do it using an inline cloudbuild file.

Requirements we have:
- The repos that trigger a build+deploy cannot own the Dockerfile b/c then developers can make potentially malicious changes that affect the cloud env
- The build and deployment to be cloud-agnostic
- Scalable


We could (and actually did at one point - [see here](https://github.com/micro-quant/faasd-worker/tree/74b9c4a4d57f3840bf91f29087731730016b2b0a)) use a custom Cloud Builder to build and deploy the images but this is more complex and requires more maintenance than an inline cloudbuild file and this also is not cloud agnostic

The current approach we use, an inline cloudbuild.yaml, is not _cloud agnostic_ but it is very simple (albeit, might be more challenging at scale) and simple means we could remove it if ever needed

We can't use a Dockerfile deployment alone b/c GCP requires the Dockerfile is in the same repo as the repo that triggers the build

We can't use a cloudbuild.yaml in the parent repo b/c the parent repo is not the repo that triggers the build

We could use buildpack (and some research was done to actually get a working example) but this is currently more complex.  However, this is a good option for the future because it is both cloud agnostic and scalable

## Other ways to automate the build and deployment of an app to GKE using CloudBuild

- Dockerfile
- cloudbuild.yaml (inline or a cloudbuild.yaml in the parent repo)
  - yaml file
  - custom Cloud Builder
- buildpack

## Fassd Worker Repo Cloud Build Config

This config is the cloudbuild config used to build and deploy the faasd-worker images to GKE.

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
      sed -i "s#@IMAGE_NAME@#$_IMAGE_NAME#g" deployment.yaml
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
  - name: gcr.io/cloud-builders/gke-deploy
    args:
      - apply
      - '--filename=deployment.yaml'
      - '--cluster=$_GKE_CLUSTER'
      - '--location=$_GKE_LOCATION'
    id: Apply deploy
images:
  - '$_IMAGE_NAME:$_IMAGE_VERSION'
options:
  substitutionOption: ALLOW_LOOSE
  dynamicSubstitutions: true
substitutions:
  _K8S_YAML_PATH: >-
    https://raw.githubusercontent.com/micro-quant/faasd-worker-dockerfile/main/deployment.yaml
  _GKE_CLUSTER: default-cluster
  _GKE_LOCATION: europe-west1-b
  _DOCKERFILE_PATH: >-
    https://raw.githubusercontent.com/micro-quant/faasd-worker-dockerfile/main/Dockerfile
  _IMAGE_NAME: 'europe-west1-docker.pkg.dev/${PROJECT_ID}/artifacts/${REPO_NAME}'
  _IMAGE_VERSION: '${COMMIT_SHA}'

```

## References

This is the old cloudbuild.yaml we used to use when we used a custom cloud builder

```yaml
steps:
  - name: >-
	  europe-west1-docker.pkg.dev/mqplatform/external/faasd-worker:fcbefbe8289d3fb8eddd371fd50c297b9a6b41f8
	args:
	  - $PROJECT_ID
	  - 'europe-west1-docker.pkg.dev/$PROJECT_ID/artifacts/$REPO_NAME:$COMMIT_SHA'
	  - $REPO_NAME
```