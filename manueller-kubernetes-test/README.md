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

# Ablauf
## Storage (PV & PVC)
kubectl apply -f persistentVolume.yaml

kubectl apply -f persistentVolumeClaim.yaml