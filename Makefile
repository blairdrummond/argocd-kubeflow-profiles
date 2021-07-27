# Config

DISTRIBUTION := distribution
KUBE_TEMPLATE := kubectl create --dry-run=client -o yaml

KIND_NAME := argocd-profiles

#===========================================

.DEFAULT: all
.PHONY: all clean kind


delete:
	kind delete clusters $(KIND_NAME)

kind:
	kind create cluster --name $(KIND_NAME) --config kind/kind-cluster.yaml
	kubectl cluster-info --context kind-$(KIND_NAME)
	kubectl create namespace kubeflow

### Local git server,
### For private ArgoCD in kind
gitserver: $(DISTRIBUTION)
	docker build . -t gitserver:latest -f kind/gitserver.Dockerfile
	kind load docker-image gitserver:latest --name $(KIND_NAME)

	kubectl create namespace git || true
	kubectl apply -f kind/gitserver/Deployment.yaml
	kubectl apply -f kind/gitserver/Service.yaml
	kubectl rollout restart deployment -n git gitserver

profile-crd:
	kubectl apply -f https://raw.githubusercontent.com/kubeflow/kubeflow/master/components/profile-controller/config/crd/bases/kubeflow.org_profiles.yaml

deploy-argocd: $(DISTRIBUTION)
	kustomize build $(DISTRIBUTION)/argocd/ | kubectl apply -f -

	while ! kubectl get secrets \
		-n argocd | grep -q argocd-initial-admin-secret; do \
		echo "Waiting for ArgoCD to start..."; \
		sleep 5; \
	done

	$(MAKE) argo-get-pass

argo-get-pass:
	@echo "ArgoCD Login"
	@echo "=========================="
	@echo "ArgoCD Username is: admin"
	@printf "ArgoCD Password is: %s\n" $$(kubectl -n argocd \
		get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d)
	@echo "=========================="

deploy-profiles:
	kubectl apply -f distribution/daaas.yaml

deploy: kind gitserver profile-crd deploy-argocd deploy-profiles
