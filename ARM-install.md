# 🔹 Overview: CSI Driver + OCI Provider Installation (ARM64 / MicroK8s)

---

## 1. Install CSI Driver (Helm)

The Secrets Store CSI Driver is the generic CNCF project.
On MicroK8s via Helm:

```bash
sudo microk8s helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
sudo microk8s helm repo update

sudo microk8s helm install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true
```

✅ Now the CSI Driver is running in the cluster.

---

## 2. Build OCI Provider Image for ARM64 (GitHub Actions)

The official Oracle image is **amd64 only** → you need your own.

1. **Create your own repo** (e.g. `oci-provider-arm64`).

2. In the repo: Fork the code from [oracle/oci-secrets-store-csi-driver-provider](https://github.com/oracle/oci-secrets-store-csi-driver-provider) or add it as a submodule.

3. Add a `Dockerfile` at the root (simplified):

```dockerfile
# Stage 1: Build provider
FROM golang:1.24 AS builder

WORKDIR /workspace

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o provider ./cmd/server

# Stage 2: Runtime
FROM gcr.io/distroless/static:nonroot

WORKDIR /
COPY --from=builder /workspace/provider /opt/provider/bin/provider

USER nonroot:nonroot

ENTRYPOINT ["/opt/provider/bin/provider"]
```

4. Create a workflow `.github/workflows/build.yaml`:

```yaml
name: Build & Push OCI Provider (ARM64)

on: workflow_dispatch

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: docker/setup-qemu-action@v3
    - uses: docker/setup-buildx-action@v3
    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.<TOKEN> }}
    - uses: docker/build-push-action@v5
      with:
        context: .
        file: Dockerfile
        platforms: linux/arm64
        push: true
        tags: ghcr.io/${{ github.repository }}/oci-secrets-provider:arm64
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

5. Start the workflow in the GitHub Actions UI → the image will be available at
   `ghcr.io/<YOUR_GITHUB_USER>/oci-secrets-provider:arm64`.

---

## 3. Install OCI Provider in the Cluster

Use the Helm chart from Oracle repo, but set your own image:

```bash
sudo microk8s helm repo add oci-provider https://oracle.github.io/oci-secrets-store-csi-driver-provider/charts
sudo microk8s helm repo update

sudo microk8s helm upgrade oci-provider \
  oci-provider/oci-secrets-store-csi-driver-provider \
  --set secrets-store-csi-driver.install=false \
  --set provider.image.repository=ghcr.io/valormex/oci-secrets-store-csi-driver-provider/oci-secrets-provider \
  --set provider.image.tag=arm64 \
  --set provider.imagePullSecrets[0].name=ghcr-secret \
  -n kube-system
```

✅ Now the OCI Provider is running in the cluster.

---

## 4. Define SecretProviderClass

In your GitOps/repo you define which secrets are retrieved from OCI Vault:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: db-secrets
  namespace: default
spec:
  provider: oci
  parameters:
    secrets: |
      - name: "db-password"
        vaultOcid: "<VAULT_OCID>"
        secretOcid: "<SECRET_OCID>"
```

**Note:** Authentication is handled via **Oracle Cloud Instance Principals**.  
It is assumed that you are running inside an Oracle Cloud instance, and the provider uses that identity for authentication.

---

## 5. Test Deployment

Simple Nginx pod mounting the secret:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-secrets-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-secrets-test
  template:
    metadata:
      labels:
        app: nginx-secrets-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
      volumes:
      - name: secrets-store
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: "db-secrets"
```

Check inside the pod:

```bash
sudo microk8s kubectl exec -it deploy/nginx-secrets-test -- cat /mnt/secrets/db-password
```

---

# ✅ Summary

1. **Install CSI Driver** → Helm from CNCF repo.
2. **Build your own ARM64 OCI Provider image** → GitHub Actions + Dockerfile.
3. **Install OCI Provider** → Helm Chart with `--set image.repository` + `--set image.tag`.
4. **SecretProviderClass** + Deployment → secrets are fetched live from OCI Vault via Instance Principals.