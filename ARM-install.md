# 🔹 Overview: CSI Driver + OCI Provider Installation (ARM64 / MicroK8s)

**Note:** Authentication is handled via **Oracle Cloud Instance Principals**.  
It is assumed that you are running inside an Oracle Cloud instance, and the provider uses that identity for authentication.

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

The official Oracle image is **amd64 only**

1. Fork the code from [oracle/oci-secrets-store-csi-driver-provider](https://github.com/oracle/oci-secrets-store-csi-driver-provider) or add it as a submodule to control versioning and other configuration details.

2. `Dockerfile` is available in `/build`

3. Create a workflow `.github/workflows/build.yaml` and run it:

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

---

## 3. Install OCI Provider in the Cluster

Create GHCR docker-registry Secret in Kubernetes to pull private image:

```bash
sudo microk8s kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<USERNAME> \
  --docker-password=<TOKEN> \
  -n kube-system
```

Use the Helm chart from Oracle repo, but set your own image:

```bash
sudo microk8s helm repo add oci-provider https://oracle.github.io/oci-secrets-store-csi-driver-provider/charts
sudo microk8s helm repo update

sudo microk8s helm upgrade oci-provider \
  oci-provider/oci-secrets-store-csi-driver-provider \
  --set secrets-store-csi-driver.install=false \
  --set provider.image.repository=ghcr.io/<USER_OR_ORGA>/oci-secrets-store-csi-driver-provider/oci-secrets-provider \
  --set provider.image.tag=arm64 \
  --set provider.imagePullSecrets[0].name=ghcr-secret \
  -n kube-system
```

✅ Now the OCI Provider is running in the cluster.

---

## 4. Define SecretProviderClass

In your GitOps/repo you define which secrets are retrieved from OCI Vault, for example:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: minio-secret-bundle
  namespace: minio
spec:
  provider: oci
  parameters:
    authType: instance
    vaultId: "ocid1.vault.oc1.eu-frankfurt-1.enukrh6baabfgt..."
    secrets: |
      - name: "minio-access-key"
        fileName: "minio-access-key"
      - name: "minio-secret-key"
        fileName: "minio-secret-key"
  secretObjects:
    - secretName: minio-secret
      type: Opaque
      data:
        - objectName: "minio-access-key"
          key: MINIO_ACCESS_KEY
        - objectName: "minio-secret-key"
          key: MINIO_SECRET_KEY
```
