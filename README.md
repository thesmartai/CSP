# Ablauf

im VPN der HS anmelden

terraform init

terraform apply

am Ende, noch vor den Output-Variablen, sollte die Externe-IP-Adresse für den LoadBalancer ausgegeben werden.
Diese IP-Adresse leitet uns zu der Anwendung

# Debugging

im Cluster über ssh (ubuntu@[floating-ip]):

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
sudo chmod 644 /etc/rancher/rke2/rke2.yaml

kubectl get all -n immich //für immich
kubectl get all -n projectcontour //für ingress-controller (envoy)

#Pipeline
Die Pipeline in GitLab ist so konfiguriert, dass sie bei jedem Push auf den main-Branch ausgeführt wird.