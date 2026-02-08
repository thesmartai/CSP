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


# Hinweise zu nicht selbst erstellten Teilen

Da einige Helm-Charts zu groß für einen einfachen Import sind, werden diese als pre-built eingebunden. Die folgenden Dateien im pre-built-Ordner sind nicht selbst erstellt, aber teilweise eigenständig modifiziert worden:
- contour.yaml für ArgoCD
- grafana-loki.yaml für Grafana und Loki
- prometheus-stack.yaml für Prometheus

Die Datei prometheus-grafana-dashboards.yaml wurde größtenteils durch den Export und das Zusammenfügen der in Grafana erstellten Dashboards erstellt. Selbst erstellt wurde dabei alles außer der eingefügten umfassenden json-Inhalte. Außerdem wurden nachträgliche Änderungen, sowohl zur Ergänzung der Dashboards, als auch zur Beseitigung von Fehlern, an den Dashboards direkt im json-Inhalt vorgenommen.

Damit alle notwendigen Dateien für den Monitoring-Stack in einem Ordner zu finden sind, ist dort ebenfalls die selbsterstellte Datei prometheus-grafana.yaml abgelegt, welche übergeordnet für die Bereitstellung des Monitoring-Stacks sorgt.