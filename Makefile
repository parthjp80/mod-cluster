# ---------------------------------------------------------------------------
# mod_cluster home-lab demo
#   make build            build both images for the cluster (linux/amd64) and push
#   make set-image        write REGISTRY/TAG into k8s/kustomization.yaml
#   make deploy           kubectl apply -k k8s
#   make status|traffic|demo
#   make local-up         run the same images locally with docker compose
# ---------------------------------------------------------------------------
REGISTRY ?= ghcr.io/parthjp80
TAG      ?= 1.0.0
PLATFORM ?= linux/amd64
NS       ?= modcluster

HTTPD_IMAGE := $(REGISTRY)/modcluster-httpd:$(TAG)
JBOSS_IMAGE := $(REGISTRY)/modcluster-jboss:$(TAG)

.PHONY: build build-httpd build-jboss set-image deploy undeploy wait status traffic demo logs local-up local-down

build: build-httpd build-jboss

build-httpd:
	docker buildx build --platform $(PLATFORM) -f apache/Dockerfile -t $(HTTPD_IMAGE) --push .

build-jboss:
	docker buildx build --platform $(PLATFORM) -f jboss/Dockerfile -t $(JBOSS_IMAGE) --push .

set-image:
	sed -i.bak -E \
	  -e '/name: modcluster-httpd/{n;s#newName: .*#newName: $(REGISTRY)/modcluster-httpd#;n;s#newTag: .*#newTag: "$(TAG)"#;}' \
	  -e '/name: modcluster-jboss/{n;s#newName: .*#newName: $(REGISTRY)/modcluster-jboss#;n;s#newTag: .*#newTag: "$(TAG)"#;}' \
	  k8s/kustomization.yaml && rm -f k8s/kustomization.yaml.bak
	@grep -A2 'name: modcluster-' k8s/kustomization.yaml

deploy:
	kubectl apply -k k8s

wait:
	kubectl -n $(NS) rollout status statefulset/httpd --timeout=180s
	kubectl -n $(NS) rollout status statefulset/jboss --timeout=300s
	kubectl -n $(NS) get pods,svc -o wide

undeploy:
	kubectl delete -k k8s --ignore-not-found

status:
	NS=$(NS) scripts/status.sh

traffic:
	NS=$(NS) scripts/traffic.sh

demo:
	NS=$(NS) scripts/demo.sh

logs:
	kubectl -n $(NS) logs -l app=httpd --tail=50 --prefix
	kubectl -n $(NS) logs -l app=jboss --tail=50 --prefix

local-up:
	docker compose -f local/compose.yaml up -d --build

local-down:
	docker compose -f local/compose.yaml down
