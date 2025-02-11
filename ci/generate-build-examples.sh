#!/usr/bin/env bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

cat <<'_EOF_'
# WARNING: DO NOT EDIT THIS FILE
# This file is automatically generated by ci/generate-build-examples.sh
timeout: 3600s
options:
  machineType: 'N1_HIGHCPU_32'
  diskSizeGb: '512'

steps:
  # Generally we prefer to create container images with local names, to avoid
  # polluting the repository and/or having conflicts with other builds. The
  # exception are images created by kaniko and any images pushed to GCR
  # to deploy on Cloud Run.
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'pack', '-f', 'build_scripts/pack.Dockerfile', 'build_scripts']

  # Create the docker images for the buildpacks builder.
  - name: 'gcr.io/kaniko-project/executor:v1.6.0-debug'
    args: [
        "--context=dir:///workspace/",
        "--dockerfile=build_scripts/Dockerfile",
        "--cache=true",
        "--cache-repo=gcr.io/${PROJECT_ID}/ci/cache",
        "--target=gcf-cpp-runtime",
        "--destination=gcr.io/${PROJECT_ID}/ci/run-image:${BUILD_ID}",
    ]
    waitFor: ['-']
    timeout: 1800s
  - name: 'gcr.io/cloud-builders/docker'
    args: ['pull', 'gcr.io/${PROJECT_ID}/ci/run-image:${BUILD_ID}']

  - name: 'gcr.io/kaniko-project/executor:v1.6.0-debug'
    args: [
        "--context=dir:///workspace/",
        "--dockerfile=build_scripts/Dockerfile",
        "--cache=true",
        "--cache-repo=gcr.io/${PROJECT_ID}/ci/cache",
        "--target=gcf-cpp-ci",
        "--destination=gcr.io/${PROJECT_ID}/ci/build-image:${BUILD_ID}",
    ]
    waitFor: ['-']
    timeout: 1800s
  - name: 'gcr.io/cloud-builders/docker'
    args: ['pull', 'gcr.io/${PROJECT_ID}/ci/build-image:${BUILD_ID}']

    # Setup local names for the builder images.
  - name: 'gcr.io/cloud-builders/docker'
    args: ['tag', 'gcr.io/${PROJECT_ID}/ci/build-image:${BUILD_ID}', 'ci-build-image:latest']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['tag', 'gcr.io/${PROJECT_ID}/ci/run-image:${BUILD_ID}', 'ci-run-image:latest']

  # Create the buildpacks builder, and make it the default.
  - name: 'pack'
    args: ['builder', 'create', 'gcf-cpp-builder:bionic', '--config', 'ci/pack/builder.toml', ]
  - name: 'pack'
    args: ['config', 'trusted-builders', 'add', 'gcf-cpp-builder:bionic', ]
  - name: 'pack'
    args: ['config', 'default-builder', 'gcf-cpp-builder:bionic', ]
    id: 'gcf-builder-ready'

  # Build the examples using the builder. Keep these in alphabetical order.
_EOF_

generic_example() {
  local example="${1}"
  local function="${2}"
  local signature="${3}"
  local container=${example//_/-}
  if [[ $# -eq 4 ]]; then
    container="${4}"
  fi

  cat <<_EOF_
  - name: 'pack'
    waitFor: ['gcf-builder-ready']
    id: '${container}'
    args: ['build',
_EOF_
  if [[ "${signature}" != "declarative" ]] && [[ "${signature}" != "" ]]; then
    echo "      '--env', 'GOOGLE_FUNCTION_SIGNATURE_TYPE=${signature}',"
  fi
  cat <<_EOF_
      '--env', 'GOOGLE_FUNCTION_TARGET=${function}',
      '--path', 'examples/${example}',
      '${container}',
    ]

_EOF_
}

site_example() {
  local example="${1}"
  local function
  function="$(basename "${example}")"
  local signature="http"
  if grep -E -q 'gcf::CloudEvent|google::cloud::functions::CloudEvent' ${example}/*; then
    signature="cloudevent"
  fi
  local container="site-${function}"

  cat <<_EOF_
  - name: 'pack'
    waitFor: ['gcf-builder-ready']
    id: '${container}'
    args: ['build',
_EOF_
  if [[ "${signature}" != "declarative" ]] && [[ "${signature}" != "" ]]; then
    echo "      '--env', 'GOOGLE_FUNCTION_SIGNATURE_TYPE=${signature}',"
  fi
  cat <<_EOF_
      '--env', 'GOOGLE_FUNCTION_TARGET=${function}',
      '--path', '${example}',
      '${container}',
    ]
_EOF_
}

generic_example hello_cloud_event HelloCloudEvent declarative
generic_example hello_from_namespace hello_from_namespace::HelloWorld declarative
generic_example hello_from_namespace ::hello_from_namespace::HelloWorld declarative hello-from-namespace-rooted
generic_example hello_from_nested_namespace hello_from_nested_namespace::ns0::ns1::HelloWorld declarative
generic_example hello_multiple_sources HelloMultipleSources declarative
generic_example hello_gcs HelloGcs declarative
generic_example hello_with_third_party HelloWithThirdParty declarative
generic_example hello_world HelloWorld declarative
generic_example hello_world ::HelloWorld declarative hello-world-rooted
generic_example howto_use_legacy_code HowtoUseLegacyCode declarative howto-use-legacy-code

cat <<_EOF_
  # Build the cloud site examples.
_EOF_

for example in examples/site/*; do
  case "${example}" in
    examples/site/howto_*)
      # There is no code to compile in these directories
      continue;
      ;;
    examples/site/testing_*)
      # These directories do not contain functions, they
      # contain standalone examples for unit, integration,
      # and system tests.
      continue;
      ;;
    *)
      ;;
  esac
  site_example "${example}"
done

cat <<_EOF_

  # Verify generated images are deployable
  - name: 'gcr.io/cloud-builders/docker'
    waitFor: ['hello-world']
    args: ['tag', 'hello-world', 'gcr.io/\${PROJECT_ID}/ci/hello-world:\${BUILD_ID}']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/\${PROJECT_ID}/ci/hello-world:\${BUILD_ID}']
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'gcloud'
    args: [
      'run', 'deploy',
      'hello-world-\${BUILD_ID}',
      '--platform', 'managed',
      '--project', '\${PROJECT_ID}',
      '--region', 'us-central1',
      '--image', 'gcr.io/\${PROJECT_ID}/ci/hello-world:\${BUILD_ID}',
      '--allow-unauthenticated',
    ]
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        URL=\$\$(gcloud run services list \\
            --project=\${PROJECT_ID} \\
            --platform managed \\
            --filter=SERVICE:hello-world-\${BUILD_ID} \\
            '--format=csv[no-heading](URL)')
        echo "Pinging service at \$\${URL}"
        curl -sSL --retry 3 "\$\${URL}"
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'gcloud'
    args: [
      'run', 'services', 'delete',
      'hello-world-\${BUILD_ID}',
      '--platform', 'managed',
      '--project', '\${PROJECT_ID}',
      '--region', 'us-central1',
      '--quiet',
    ]

  # Remove the images created by this build.
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        set +e
        gcloud container images delete -q gcr.io/\${PROJECT_ID}/ci/run-image:\${BUILD_ID}
        gcloud container images delete -q gcr.io/\${PROJECT_ID}/ci/build-image:\${BUILD_ID}
        gcloud container images delete -q gcr.io/\${PROJECT_ID}/ci/hello-world:\${BUILD_ID}
        exit 0

  # The previous step may not run if the build fails. Garbage collect any
  # images created by this script more than 4 weeks ago. This step should
  # not break the build on error, and it can start running as soon as the
  # build does.
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    waitFor: ['-']
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        set +e
        for image in hello-world build-image run-image cache; do
          gcloud --project=\${PROJECT_ID} container images list-tags gcr.io/\${PROJECT_ID}/ci/\$\${image} \\
              --format='get(digest)' --filter='timestamp.datetime < -P4W' | \\
          xargs printf "gcr.io/\${PROJECT_ID}/\$\${image}@\$\$1\n"
        done | \\
        xargs -P 4 -L 32 gcloud container images delete -q --force-delete-tags
        exit 0
_EOF_
