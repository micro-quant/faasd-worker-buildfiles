FROM europe-west1-docker.pkg.dev/mqplatform/external/faasd-worker:7fb256cc7f313df710dc74d42632c361d3950a75 as base
WORKDIR /server

ARG APP_NAME
# this does NOT run a unit test.  This throws an error if the build-arg 'APP_NAME' is not defined
RUN test -n ${APP_NAME:?}

# copy files, (optionally) install dependencies, remove unnecessary files
COPY . functions/${APP_NAME}/.
RUN if [-f "functions/${APP_NAME}/requirements.txt"]; then pip install -r functions/${APP_NAME}/requirements.txt ; fi
RUN (cd functions/${APP_NAME}/ && rm -f Dockerfile README.md)