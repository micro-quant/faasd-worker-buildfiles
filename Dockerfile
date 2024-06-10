FROM europe-west1-docker.pkg.dev/mqplatform/external/faasd-worker:76553fd449d721932356cf815bdf58dec27d1c49 as base
WORKDIR /server

ARG APP_NAME
# this does NOT run a unit test.  This throws an error if the build-arg 'APP_NAME' is not defined
RUN test -n ${APP_NAME:?}

# copy files, (optionally) install dependencies, remove unnecessary files
COPY . functions/${APP_NAME}/.
RUN if [-f "functions/${APP_NAME}/requirements.txt"]; then pip install -r functions/${APP_NAME}/requirements.txt ; fi
RUN (cd functions/${APP_NAME}/ && rm -f Dockerfile requirements.txt README.md)