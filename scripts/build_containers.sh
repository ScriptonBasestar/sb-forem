#!/bin/bash

set -euo pipefail

: ${CONTAINER_REPO:="ghcr.io/scriptonbasestar"}
: ${CONTAINER_APP:=forem}

echo "CONTAINER_REPO: ${CONTAINER_REPO}"
echo "CONTAINER_APP: ${CONTAINER_APP}"

export DOCKER_BUILDKIT=1

DEPLOY_IMAGE=false

BUILDKITE_COMMIT=$(git rev-parse --short HEAD)
BUILDKITE_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Branch: $BUILDKITE_BRANCH"
echo "Commit: $BUILDKITE_COMMIT"
if [[ -n "${BUILDKITE_PULL_REQUEST:-}" ]]; then
  echo "PR    : $BUILDKITE_PULL_REQUEST"
fi
if [[ -n "${BUILDKITE_TAG:-}" ]]; then
  echo "Tag   : $BUILDKITE_TAG"
fi

function create_pr_containers {
  echo 'create_pr_containers'

  PULL_REQUEST=$1

  # Pull images if available for caching
  echo "Pulling pull request #${PULL_REQUEST} containers from registry..."
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":builder ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":builder-"${PULL_REQUEST}" ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":pr-"${PULL_REQUEST}" ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":testing-"${PULL_REQUEST}" ||:

  # Build the builder image
  echo "Building builder-${PULL_REQUEST} container..."
  docker build --target builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder-"${PULL_REQUEST}" \
               --label quay.expires-after=8w \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":builder-"${PULL_REQUEST}" .

  # Build the pull request image
  echo "Building pr-${PULL_REQUEST} container..."
  docker build --target production \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder-"${PULL_REQUEST}" \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":pr-"${PULL_REQUEST}" \
               --label quay.expires-after=8w \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":pr-"${PULL_REQUEST}" .

  # Build the testing image
  echo "Building testing-$"${PULL_REQUEST}" container..."
  docker build --target testing \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder-"${PULL_REQUEST}" \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":pr-"${PULL_REQUEST}" \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":testing-"${PULL_REQUEST}" \
               --label quay.expires-after=8w \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":testing-"${PULL_REQUEST}" .

  # Push images to Quay
  echo "Pushing pull request #${PULL_REQUEST} containers to registry..."
  if [[ -n "${DEPLOY_IMAGE}" ]]; then
    docker push "${CONTAINER_REPO}/${CONTAINER_APP}:builder-${PULL_REQUEST}"
    docker push "${CONTAINER_REPO}/${CONTAINER_APP}:pr-${PULL_REQUEST}"
    docker push "${CONTAINER_REPO}/${CONTAINER_APP}:testing-${PULL_REQUEST}"
  fi
}

function create_production_containers {
  echo 'create_production_containers'

  # Pull images if available for caching
  echo "Pulling production containers from registry..."
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":builder ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":production ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":testing ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":development ||:

  # Build the builder image
  docker build --target builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":builder .

  # Build the production image
  docker build --target production \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":production \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":$(date +%Y%m%d) \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":production \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":latest .

#  docker build --target production \
#               --label quay.expires-after=8w \
#               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
#               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":production \
##               --build-arg "VCS_REF=${BUILDKITE_COMMIT}" \
#               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":${BUILDKITE_COMMIT:0:7} .

  # Build the testing image
  docker build --target testing \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":production \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":testing \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":testing .

  # Build the development image
  docker build --target development \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":production \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":testing \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":development \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":development .

  # Push images to Quay
  if [[ -n "${DEPLOY_IMAGE}" ]]; then
   docker push "${CONTAINER_REPO}/${CONTAINER_APP}":builder
   docker push "${CONTAINER_REPO}/${CONTAINER_APP}":production
   docker push "${CONTAINER_REPO}/${CONTAINER_APP}":testing
   docker push "${CONTAINER_REPO}/${CONTAINER_APP}":development
   docker push "${CONTAINER_REPO}/${CONTAINER_APP}":$(date +%Y%m%d)
   docker push "${CONTAINER_REPO}/${CONTAINER_APP}":${BUILDKITE_COMMIT:0:7}
   docker push "${CONTAINER_REPO}/${CONTAINER_APP}":latest
 fi
}

function create_release_containers {
  echo 'create_release_containers'

  BRANCH=$1

  # Pull images if available for caching
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":builder ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":production ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":testing ||:
  docker pull --quiet "${CONTAINER_REPO}/${CONTAINER_APP}":development ||:

  # Build the builder image
  docker build --target builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
#               --build-arg "VCS_REF=${BUILDKITE_COMMIT}" \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":builder .

  # Build the production image
  docker build --target production \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":production \
#               --build-arg "VCS_REF=${BUILDKITE_COMMIT}" \
#               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":${BUILDKITE_COMMIT:0:7} \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":${BRANCH} .

  # Build the testing image
  docker build --target testing \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":production \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":testing \
#               --build-arg "VCS_REF=${BUILDKITE_COMMIT}" \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":testing-${BRANCH} .

  # Build the development image
  docker build --target development \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":production \
               --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":testing \
#               --build-arg "VCS_REF=${BUILDKITE_COMMIT}" \
               --tag "${CONTAINER_REPO}/${CONTAINER_APP}":development-${BRANCH} .

  # If the env var for the git tag doesn't exist or is an empty string, then we
  # won't build a container image for a cut release.
#  if [ -v BUILDKITE_TAG ] && [ ! -z "${BUILDKITE_TAG}" ]; then
#    echo "Buildkite Tag: ${BUILDKITE_TAG}"
#    docker build --target production \
#                 --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":builder \
#                 --cache-from="${CONTAINER_REPO}/${CONTAINER_APP}":production \
#                 --build-arg "VCS_REF=${BUILDKITE_TAG}" \
#                 --tag "${CONTAINER_REPO}/${CONTAINER_APP}":${BUILDKITE_TAG} .
#  fi

  # Push images to Quay
  if [[ -n "${DEPLOY_IMAGE}" ]]; then
    docker push "${CONTAINER_REPO}/${CONTAINER_APP}":${BRANCH}
    docker push "${CONTAINER_REPO}/${CONTAINER_APP}":development-${BRANCH}
    docker push "${CONTAINER_REPO}/${CONTAINER_APP}":testing-${BRANCH}
  fi
}

function prune_containers {
  echo 'prune_containers'

  docker image prune -f
}

trap prune_containers ERR INT EXIT

if [[ -n "${BUILDKITE_PULL_REQUEST:-}" ]]; then
  echo "if 1 ..."
  echo "Building containers for pull request #${BUILDKITE_PULL_REQUEST}..."
  create_pr_containers "${BUILDKITE_PULL_REQUEST}"
elif [[ "${BUILDKITE_BRANCH}" = "master" || "${BUILDKITE_BRANCH}" = "main" ]]; then
  echo "elif 2 ..."
  echo "Building Production Containers..."
  create_production_containers
elif [[ ${BUILDKITE_BRANCH} = stable* ]]; then
  echo "elif 3 ..."
  echo "Building Production Containers for ${BUILDKITE_BRANCH}..."
  create_release_containers "${BUILDKITE_BRANCH}"
else
  echo "else 4 ..."
fi
