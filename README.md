# AWS EKS SSL Certificate Generation & Renewal via ECR & K8s Cronjob

Use the files from this repo to build a Docker image that will generate Let's Encrypt certificates and store them in Kubernetes Secrets.

These Secrets can be loaded as volumes in other K8s entities to use them for SSL, periodic renewal can be controlled via a K8s CronJob.

## Sample files
These files can be customized to generate all entities needed for the K8s Job to work correctly.

### Publish Docker image to ECR
```
#!/usr/bin/env bash

# use this to get login credentials before pusing an ecr image
aws ecr get-login-password --region region | docker login --username AWS --password-stdin aws_account_id.dkr.ecr.region.amazonaws.com

# to build a multi-arch image:
docker buildx create --use
# docker buildx build --platform linux/amd64,linux/arm64 --tag aws_account_id.dkr.ecr.region.amazonaws.com/my-repository:latest --push .
```

### Role
```
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: certs-generator
rules:
- apiGroups: [""] # "" indicates the core API group
  resources: ["secrets"]
  verbs: ["get", "list", "update", "patch"]
```

### RoleBinding
```
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: generate-certs
  namespace: default
subjects:
- kind: ServiceAccount
  name: certs-gen-account
  apiGroup: ""
roleRef:
  kind: Role #this must be Role or ClusterRole
  name: certs-generator # this must match the name of the Role or ClusterRole you wish to bind to
  apiGroup: rbac.authorization.k8s.io
```

### ServiceAccount
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: certs-gen-account
  namespace: default
```

### Secret
```
apiVersion: v1
kind: Secret
metadata:
  name: letsencrypt-certs
type: Opaque
immutable: false
```

### Service
```
apiVersion: v1
kind: Service
metadata:
  name: letsencrypt
spec:
  type: ClusterIP
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  selector:
    app: letsencrypt
```

### Job
Before deploying the job, remember to build and publish your image to ECR.

```
apiVersion: batch/v1
kind: Job
metadata:
  name: letsencrypt-job
  labels:
    app: letsencrypt
spec:
  template:
    metadata:
      name: letsencrypt
      labels:
        app: letsencrypt
    spec:
      containers:
      # Bash script that starts an http server and launches certbot
      - image: aws_account_id.dkr.ecr.region.amazonaws.com/my-repository:latest
        name: letsencrypt
        imagePullPolicy: Always
        ports:
        - name: letsencrypt
          containerPort: 80
        env:
        - name: DOMAINS
          # wildcard certificates require a different approach to validate with letsencrypt
          # it is currently unsupported with this image, please use a subdomain
          value: 'sub.mydomain.com'
        - name: EMAIL
          value: my@mail.com
        - name: SECRET
          value: letsencrypt-certs
          # time to sleep before sending the request for new certificates, use this to
          # tail logs or debug an issue in the container before it finishes
        - name: SLEEP
          value: '20'
          # overwrite the current secret? most of the time: yes
        - name: OVERWRITE
          value: 'true'
      restartPolicy: Never
      serviceAccountName: certs-gen-account
```
