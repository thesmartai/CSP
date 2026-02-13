# Cloud Services Project (CSP)

Automatisierte Bereitstellung von **Immich** auf einem **RKE2 Kubernetes-Cluster** in der OpenStack-Cloud. 
Das Projekt nutzt **Terraform** für die Infrastruktur und **Argo CD** für das App-Management.

## Aufbau kurz erklärt

Terraform baut die OpenStack-VMs, das Netzwerk und installiert den RKE2 Cluster sowie Argo CD. Sobald Argo läuft, zieht es sich den Rest der Konfiguration direkt aus diesem Git-Repo.

Verwendete Komponenten:
*   **Ingress:** Contour (Envoy)
*   **Datenbank:** CloudNativePG (Postgres inkl. Vektor-Support)
*   **Storage:** Cinder (OpenStack Volumes)
*   **Monitoring:** Prometheus & Grafana

## Ordner & Zuständigkeiten

Hier ein kurzer Überblick, wo was liegt:

*   `argo_cd/applications/`: Die Haupt-Definitionen. Nur wenn sich hier Dateien ändern, muss Terraform neu laufen.
*   `argo_cd/values/`: Unsere eigenen Configs für die Helm Charts (z.B. Immich Settings).
*   `argo_cd/pre-built/`: Statische Manifeste (z.B. Contour), als Workaround da die CRDs sonst zu groß für einen normalen Sync wären.
*   `manifests/`: Selber geschriebene Dateien wie Secrets, PVCs oder Ingress-Regeln.

### Terraform vs. Argo CD

Damit die sich nicht in die Quere kommen:

1.  **Terraform** macht das Fundament (Server, IPs, initiales Setup). Es triggert nur neu, wenn sich die Application-Files ändern oder der Server weg ist.
2.  **Argo CD** übernimmt danach den Betrieb. Es überwacht die Ordner `manifests` und `values`. Wenn man da was ändert und pusht, zieht Argo das Update automatisch, ohne das Terraform was machen muss.

### Bekanntes Problem: Gleiche IP beim Neu-Erstellen
Wenn man den Cluster löscht und neu erstellt, vergibt OpenStack manchmal zufällig exakt die gleiche Floating-IP wieder ("bad luck").
Da das verwendete Terraform-Modul leider keine eindeutige `instance_id` in den Outputs zurückgibt, triggert unser Skript (das nur auf IP-Änderung prüft) in diesem Fall nicht. Der Server ist zwar neu, aber Terraform denkt, es sei der alte, und installiert nichts.

**Fix:** Einfach Terraform zwingen, das Setup nochmal zu machen:
`terraform apply -replace=null_resource.deploy_k8s_stack`

### Terraform Destroy löscht nicht alles
Wenn man `terraform destroy` macht, bleiben oft Sachen in OpenStack liegen (z.B. Volumes oder LoadBalancer).
Das liegt daran, dass Kubernetes die selbst erstellt hat und Terraform die nicht kennt. Terraform löscht nur, was es selbst in `.tf` Files hat.

**Todo:** Man bräuchte eigentlich den Kubernetes-Provider in Terraform, damit der auch das Zeug im Cluster sauber mit abräumt. Aktuell muss man in OpenStack manchmal von Hand nachwischen.

## Deployment starten

Im Normalfall erledigt der **GitHub Runner** das Deployment automatisch via Pipeline.
Falls man es manuell lokal ausführen möchte:

1.  **VPN:** Sicherstellen, dass man im VPN der Hochschule ist.
2.  **Init:** Initialisiere Terraform:
    ```bash
    terraform init
    ```
3.  **Apply:** Starte das Deployment:
    ```bash
    terraform apply
    ```
    *Auf der OpenStack-Umgebung der HS Fulda dauert das komplette Deployment ca. 16 Minuten, bis die Infrastruktur steht.*

Am Ende wird die **Externe IP** des LoadBalancers angezeigt. Das ist die Adresse, unter der Immich erreichbar ist.

## Debugging

Falls was klemmt, ab auf den Server per SSH:

`ssh ubuntu@[deine-floating-ip]`

Damit `kubectl` in deiner manuellen SSH-Sitzung funktioniert (Der Terraform-Runner hat die `rke2.yaml` bereits angelegt und die Rechte angepasst, nur die Umgebungsvariable fehlt in deiner Session):

```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
```

Nützliche Befehle:
```bash
# Alles von Immich anzeigen (Pods, Services, PVCs)
kubectl get all -n immich

# Ingress Controller checken
kubectl get all -n projectcontour

# Argo CD Status prüfen
kubectl get applications -n argocd
```

# Hinweise zu nicht selbst erstellten Teilen

Da einige Helm-Charts zu groß für einen einfachen Import sind, werden diese als pre-built eingebunden. Die folgenden Dateien im pre-built-Ordner sind nicht selbst erstellt, aber teilweise eigenständig modifiziert worden:
- contour.yaml für ArgoCD
- grafana-loki.yaml für Grafana und Loki
- prometheus-stack.yaml für Prometheus

Die Datei prometheus-grafana-dashboards.yaml wurde größtenteils durch den Export und das Zusammenfügen der in Grafana erstellten Dashboards erstellt. Selbst erstellt wurde dabei alles außer der eingefügten umfassenden json-Inhalte. Außerdem wurden nachträgliche Änderungen, sowohl zur Ergänzung der Dashboards, als auch zur Beseitigung von Fehlern, an den Dashboards direkt im json-Inhalt vorgenommen.

Damit alle notwendigen Dateien für den Monitoring-Stack in einem Ordner zu finden sind, ist dort ebenfalls die selbsterstellte Datei prometheus-grafana.yaml abgelegt, welche übergeordnet für die Bereitstellung des Monitoring-Stacks sorgt.
