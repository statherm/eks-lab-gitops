# TEMPLATE — rendered to web-deployment.yaml by scripts/render-gitops.sh
# (__ECR_URL__ = ecr_repository_url output of 00-account, __IMAGE_TAG__ = tag printed by build-push.sh).
#
# gunicorn web tier: 2 replicas behind the ALB (target-type ip -> pod IPs are the targets).
# Graceful shutdown story: preStop sleep 5 lets the ALB finish deregistering the pod IP before
# gunicorn receives SIGTERM; gunicorn then drains in-flight requests; the kubelet waits up to
# terminationGracePeriodSeconds 30 before SIGKILL.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: sample
  labels:
    app.kubernetes.io/name: web
    app.kubernetes.io/part-of: eks-lab
spec:
  replicas: 2
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: web
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels:
        app.kubernetes.io/name: web
        app.kubernetes.io/part-of: eks-lab
    spec:
      terminationGracePeriodSeconds: 30
      automountServiceAccountToken: false
      nodeSelector:
        kubernetes.io/arch: arm64
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: web
          image: __ECR_URL__:__IMAGE_TAG__
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8000
              protocol: TCP
          env:
            - name: MODE
              value: web
            - name: PORT
              value: "8000"
            - name: APP_VERSION
              value: "__IMAGE_TAG__"
            # Delivered by ESO (externalsecret.yaml) from Secrets Manager eks-lab/sample.
            # The app only reports secret_present=true/false; it never echoes the value.
            - name: SAMPLE_SECRET
              valueFrom:
                secretKeyRef:
                  name: sample-secret
                  key: SAMPLE_SECRET
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 3
          lifecycle:
            preStop:
              exec:
                command: ["sleep", "5"]
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          # gunicorn's worker heartbeat files go to /dev/shm (see Dockerfile) so the root fs can be read-only.
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 16Mi
