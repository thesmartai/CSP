# Immich
## Helm-Chart
https://github.com/immich-app/immich-charts/tree/main

```helm install --create-namespace --namespace immich immich oci://ghcr.io/immich-app/immich-charts/immich -f values.yaml```

## PVC
[Doku](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)

Persistent Volume -> persistentVolume.yaml
Persistent Volume Claim-> persistentVolumeClaim.yaml

Einbindung des Storages in den Pod (Immich):
```
spec:
  volumes:
    - name: task-pv-storage
      persistentVolumeClaim:
        claimName: task-pv-claim
```
# CloudnativePG with vectorchord

# Redis

helm install redis oci://registry-1.docker.io/bitnamicharts/redis

# Ablauf
## Storage (PV & PVC)
kubectl apply -f ./kubernetes-objects/persistentVolume.yaml

kubectl apply -f ./kubernetes-objects/persistentVolumeClaim.yaml

helm install redis oci://registry-1.docker.io/bitnamicharts/redis

kubectl apply -f ./kubernetes-objects/immich-db-secret.yaml

helm repo add cnpg https://cloudnative-pg.github.io/charts/
helm repo update
helm install cnpg cnpg/cloudnative-pg --namespace cnpg-system --create-namespace
(kubectl get crd clusters.postgresql.cnpg.io)

kubectl apply -f ./kubernetes-objects/cloudnative-pg.yaml

helm install immich oci://ghcr.io/immich-app/immich-charts/immich -f ./kubernetes-objects/values.yaml

kubectl -n default port-forward svc/immich-server 2283:2283

// ingress-controller und ingress(-resource?) -> funktioniert nicht

helm repo add traefik https://traefik.github.io/charts

helm repo update

helm install traefik traefik/traefik

kubectl apply -f ingress-ressource.yaml