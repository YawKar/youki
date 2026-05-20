alias build := youki-release
alias youki := youki-dev

KIND_CLUSTER_NAME := 'youki'

cwd := justfile_directory()

# build

# build all binaries
build-all: youki-release contest

# build youki in dev mode
youki-dev:
    {{ cwd }}/scripts/build.sh -o {{ cwd }} -c youki

# build youki in release mode
youki-release:
    {{ cwd }}/scripts/build.sh -o {{ cwd }} -r -c youki

# build runtimetest binary
runtimetest:
    {{ cwd }}/scripts/build.sh -o {{ cwd }} -r -c runtimetest

# build contest
contest:
    {{ cwd }}/scripts/build.sh -o {{ cwd }} -r -c contest

# install youki to /usr/local/sbin
install:
    install -D -m 0755 {{ cwd }}/youki "${PREFIX-/usr/local/sbin}/youki"

# Tests

# run integration tests
test-integration: test-oci test-contest

# run all tests except rust-oci 
test-all: test-basic test-features test-oci containerd-test # currently not doing rust-oci here

# run basic tests
test-basic: test-unit test-doc

# run cargo unit tests
test-unit:
    {{ cwd }}/scripts/cargo.sh test --lib --bins --all --all-targets --all-features --no-fail-fast -- --test-threads=1

# run cargo doc tests
test-doc:
    {{ cwd }}/scripts/cargo.sh test --doc -- --test-threads=1

# run permutated feature compilation tests
test-features:
    {{ cwd }}/scripts/features_test.sh

# run oci integration tests through runtime-tools
test-oci:
    {{ cwd }}/scripts/oci_integration_tests.sh {{ cwd }}

# run rust oci integration tests
test-contest *TESTNAME: youki-release contest
    sudo {{ cwd }}/scripts/contest.sh {{ cwd }}/youki {{TESTNAME}}

# validate rust oci integration tests on runc
validate-contest-runc *TESTNAME: contest
    sudo RUNTIME_KIND="runc" {{ cwd }}/scripts/contest.sh runc {{TESTNAME}}

# test podman rootless works with youki
test-rootless-podman:
    {{ cwd }}/tests/rootless-tests/run.sh {{ cwd }}/youki

# test docker-in-docker works with youki
test-dind:
    {{ cwd }}/tests/dind/run.sh

# test runc compatibility
test-runc-comp *RUNTIME_BINARY:
    {{ cwd }}/tests/runc/runc_integration_test.sh {{RUNTIME_BINARY}}

# run containerd integration tests
containerd-test: youki-dev
    vagrant up containerd2youki
    vagrant provision containerd2youki --provision-with test

# run containerd integration tests
clean-containerd-test:
    vagrant destroy containerd2youki

[private]
kind-cluster: bin-kind
    #!/usr/bin/env bash
    set -euo pipefail

    mkdir -p tests/k8s/_out/
    docker buildx build -f tests/k8s/Dockerfile --iidfile=tests/k8s/_out/img --load .
    image=$(cat tests/k8s/_out/img)
    bin/kind create cluster --name {{ KIND_CLUSTER_NAME }} --image=$image

# run youki with kind
test-kind: kind-cluster
    kubectl --context=kind-{{ KIND_CLUSTER_NAME }} apply -f tests/k8s/deploy.yaml
    kubectl --context=kind-{{ KIND_CLUSTER_NAME }} wait deployment nginx-deployment --for condition=Available=True --timeout=90s
    kubectl --context=kind-{{ KIND_CLUSTER_NAME }} get pods -o wide
    kubectl --context=kind-{{ KIND_CLUSTER_NAME }} delete -f tests/k8s/deploy.yaml

# Bin

[private]
bin-kind:
	docker buildx build --output=bin/ -f tests/k8s/Dockerfile --target kind-bin .

# Clean

# Clean kind test env
clean-test-kind:
	kind delete cluster --name {{ KIND_CLUSTER_NAME }}

# misc

# run bpftrace hack
hack-bpftrace:
    BPFTRACE_STRLEN=120 ./hack/debug.bt

# a hacky benchmark method we have been using casually to compare performance
hack-benchmark:
    #!/usr/bin/env bash
    set -euo pipefail

    hyperfine \
        --prepare 'sudo sync; echo 3 | sudo tee /proc/sys/vm/drop_caches' \
        --warmup 10 \
        --min-runs 100 \
        'sudo {{ cwd }}/youki create -b tutorial a && sudo {{ cwd }}/youki start a && sudo {{ cwd }}/youki delete -f a'

# run linting on project
lint:
    {{ cwd }}/scripts/cargo.sh fmt --all -- --check
    {{ cwd }}/scripts/cargo.sh clippy --all --all-targets --all-features -- -D warnings

# run spellcheck
spellcheck:
    typos

# run format on project
format:
    {{ cwd }}/scripts/cargo.sh fmt --all

# cleans up generated artifacts
clean:
    {{ cwd }}/scripts/clean.sh {{ cwd }}

# install tools used in dev
dev-prepare:
    {{ cwd }}/scripts/cargo.sh install typos-cli

# setup dependencies in CI
ci-prepare:
    #!/usr/bin/env bash
    set -euo pipefail

    # Check if system is Ubuntu
    if [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        if [[ $DISTRIB_ID == "Ubuntu" ]]; then
            echo "System is Ubuntu"
            apt-get -y update
            apt-get install -y \
                pkg-config \
                libsystemd-dev \
                build-essential \
                libelf-dev \
                libseccomp-dev \
                libclang-dev \
                libssl-dev
            exit 0
        fi
    fi

    echo "Unknown system. The CI is only configured for Ubuntu. You will need to forge your own path. Good luck!"
    exit 1

ci-musl-prepare: ci-prepare
    #!/usr/bin/env bash
    set -euo pipefail

    # Check if system is Ubuntu
    if [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        if [[ $DISTRIB_ID == "Ubuntu" ]]; then
            echo "System is Ubuntu"
            apt-get -y update
            apt-get install -y \
                musl-dev \
                musl-tools
            exit 0
        fi
    fi

    echo "Unknown system. The CI is only configured for Ubuntu. You will need to forge your own path. Good luck!"
    exit 1

version-up version:
    #!/usr/bin/bash
    set -ex
    git grep -l "^version = .* # MARK: Version" | xargs sed -i 's/version = "[0-9]\.[0-9]\.[0-9]" # MARK: Version/version = "{{version}}" # MARK: Version/g'
    git grep -l "} # MARK: Version" | grep -v justfile | xargs sed -i 's/version = "[0-9]\.[0-9]\.[0-9]" } # MARK: Version/version = "{{version}}" } # MARK: Version/g'
    {{ cwd }}/scripts/release_tag.sh {{version}}
    NEXT_VERSION=$(echo {{version}} | awk -F. -v OFS=. '{$NF += 1 ; print}')
    sed -i "s/{{version}}/$NEXT_VERSION/g" .tagpr
    # Need to update the lockfile.
    cargo check

contest-list: contest
   {{ cwd }}/contest list


# ADDED ONLY FOR INVESTIGATION
studied_container := "__abracadabra_hard_name_not_to_collide"

delete-the-already-existing-container runtime:
    # Delete the old container if it already exists
    @# TODO(BUG): research: There's a strange behaviour: if we create a container but didn't run it, we cannot delete it even with --force flag
    @if sudo {{ runtime }} state {{ studied_container }} >/dev/null 2>&1; then \
        sudo {{ runtime }} start {{ studied_container }} || true; \
        sudo {{ runtime }} kill {{ studied_container }} 9 || true; \
        sudo {{ runtime }} delete --force {{ studied_container }}; \
    fi

generate-example-bundle runtime: youki-dev (delete-the-already-existing-container runtime)
    # Checking that required programs are in PATH
    @fail=0; \
    programs=("{{ runtime }}" "sponge" "jq" "wget" "chmod"); \
        for tocheck in "${programs[@]}"; do \
            if ! command -v $tocheck >/dev/null; then \
                echo "Please, install $tocheck to \$PATH"; \
                fail=1; \
            fi \
        done; \
    [ "$fail" -eq 0 ] || exit 1
    # Create the bone
    mkdir -p bundle/rootfs/bin
    @# There's an issue about `youki spec` doesn't respect the `--bundle` flag: https://github.com/youki-dev/youki/pull/3543
    @# ./youki spec --bundle ./bundle
    (cd ./bundle && ../youki spec)
    # Take the minimal alpine rootfs and just steal it :]
    podman export $(podman create alpine) | tar -xf - -C ./bundle/rootfs/
    # Patch .process.args to point to "/bin/busybox ash" inside rootfs
    jq '.process.args = ["busybox", "ash", "-c", "sleep 3600"]' ./bundle/config.json | sponge ./bundle/config.json
    # Patch the capabilities as prescribed in: https://github.com/youki-dev/youki/issues/3434
    jq --slurpfile studcaps ./studied_capabilities.json '.process.capabilities = $studcaps[0]' ./bundle/config.json | sponge ./bundle/config.json

run-example-bundle runtime: (generate-example-bundle runtime)
    # About to run the container that will sleep in detached mode
    sudo {{ runtime }} run -d --bundle ./bundle {{ studied_container }}
    # Now try to exec. You should see the "failed to drop capabilities"
    sudo {{ runtime }} exec {{ studied_container }} pwd || true
    sudo {{ runtime }} kill {{ studied_container }} 9
    sudo {{ runtime }} delete {{ studied_container }}
