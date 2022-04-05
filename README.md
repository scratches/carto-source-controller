# Simple Supply Chain with Cartographer

The aim is to create a supply chain that makes k8s deployments from pre-built images. The simplest way that could possibly work would be with a hard-coded image in the workload. To make it slightly more interesting we want to monitor the image repository and update the deployment if the image changes. There is an closed source Tanzu [source-controller](https://github.com/vmware-tanzu/source-controller) that meets that need.

## Setting up a Cluster

The example here works on [Kind](https://github.com/kubernetes-sigs/kind) with a local registry on `localhost:5000`. The Kind docs show you how to do that, or you can use the `kind-setup.sh` script in this project. To make sure it is working:

```
$ kubctl get all
NAME                                READY   STATUS    RESTARTS   AGE

NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/kubernetes     ClusterIP   10.96.0.1       <none>        443/TCP   21h

NAME                           READY   UP-TO-DATE   AVAILABLE   AGE

NAME                                      DESIRED   CURRENT   READY   AGE
```

and

```
$ curl localhost:5000/v2/
{}
```

We also put an application in the repo with docker push. It doesn't matter what it does because it's only there so we can see something wiggle. E.g.

```
$ docker pull nginx
$ docker tag nginx localhost:5000/apps/demo
$ docker push localhost:5000/apps/demo
```

## Installing the Source Controller

You can follow the [instructions](https://github.com/vmware-tanzu/source-controller/blob/main/docs/installing-release.md) in the `source-controller` repo. It will be successful if you can list the image repositories:

```
$ kubectl get imagerepositories
No resources found in default namespace.
```

## Example Workload

Here is a minimal workload:

```yaml
apiVersion: carto.run/v1alpha1
kind: Workload
metadata:
  name: demo
  labels:
    workload-intent: image-prebuilt
spec:
  serviceAccountName: admin
  source:
    image: localhost:5000/apps/demo
```

The two things any workload really needs are a label, which matches a supply-chain, and a source, so that it can kick things off. This one is quite common in that it also needs a service account because it is going to manage two kinds of resource (image repoitories and deployments). 

## The Supply Chain

### Service Account

There is an `admin/service-account.yaml` that sets the service account up for workloads to use. It has to have these permissions (at least):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: admin-permissions
rules:
- apiGroups: ['apps', '']
  resources: ['deployments', 'pods', 'replicasets']
  verbs: ['*']
- apiGroups:
  - source.apps.tanzu.vmware.com
  resources: ['imagerepositories']
  verbs: ['*']
```

Those are bound to the `admin` account using a `RoleBinding`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: admin-permissions
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: admin-permissions
subjects:
  - kind: ServiceAccount
    name: admin
```

### The Supply Chain

Here's the extremely minimal supply chain:

```yaml
apiVersion: carto.run/v1alpha1
kind: ClusterSupplyChain
metadata:
  name: supply-chain
spec:
  selector:
    workload-intent: image-prebuilt
  resources:
    - name: image-builder
      templateRef:
        kind: ClusterImageTemplate
        name: prebuilt-image

    - name: deployer
      templateRef:
        kind: ClusterTemplate
        name: deployment
      images:
        - resource: image-builder
          name: image
```

It has a selector matching the label in our workload, and 2 resources, one each of 

* A `ClusterImageTemplate` named `prebuilt-image`. This creates an `imagerepository`, which is the source of an image path for the deployment. It is also monitoring the source repository for changes because of the way the `source-controller` is implemented.
* A `ClusterTemplate` named `deployment`. This creates a deployment for the image. It has a reference back to the image via the resource identifier and the name of a reference `imagePath` in the template, which in turn directs to a field in the actual `imagerepository`.

The templates are defined in `admin/*-template.yaml`. You can apply thos along with the other admin resources:

```
$ kubectl apply -f admin

$ kubectl get clusterimagetemplates.carto.run 
NAME             AGE
prebuilt-image   39m

$ kubectl get clustertemplates.carto.run 
NAME         AGE
deployment   16h

$ kubectl get clustersupplychains.carto.run 
NAME           READY   REASON   AGE
supply-chain   True    Ready    16h
```

### See it Working

Apply the workload resource and see what happens:

```
$ kubectl apply -f workload.yaml

$ kubectl describe imagerepositories
Name:         demo
Namespace:    default
...
Spec:
  Image:     localhost:5000/apps/demo
  Interval:  1m0s
Status:
  Conditions:
    Last Transition Time:  2022-04-05T05:45:38Z
    Message:               
    Reason:                Initializing
    Status:                Unknown
    Type:                  ArtifactAvailable
    Last Transition Time:  2022-04-05T05:51:05Z
    Message:               unable to resolve image "localhost:5000/apps/demo": Get "https://localhost:5000/v2/": dial tcp [::1]:5000: connect: connection refused; Get "http://localhost:5000/v2/": dial tcp [::1]:5000: connect: connection refused
    Reason:                RemoteError
    Status:                False
    Type:                  ImageResolved
    Last Transition Time:  2022-04-05T05:51:05Z
    Message:               unable to resolve image "localhost:5000/apps/demo": Get "https://localhost:5000/v2/": dial tcp [::1]:5000: connect: connection refused; Get "http://localhost:5000/v2/": dial tcp [::1]:5000: connect: connection refused
    Reason:                RemoteError
    Status:                False
    Type:                  Ready
  Observed Generation:     3
Events:
  Type    Reason         Age                 From             Message
  ----    ------         ----                ----             -------
  Normal  StatusUpdated  2s (x3 over 5m29s)  ImageRepository  Updated status
```

That's broken because `source-controller` doesn't know that `localhost:5000` is a local unsecure registry. The container manager inside Kubernetes knows about it, but `source-controller` isn't able to make use of that fact. It would work if the `source-controller` was running on the host machine instead of in the cluster. Sigh.