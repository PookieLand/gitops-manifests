# How to use Istio overlays for staging and production

## Staging
```
kustomize build overlays/staging/istio/networking | kubectl apply -f -
kustomize build overlays/staging/istio/namespace | kubectl apply -f -
```

## Production
```
kustomize build overlays/production/istio/networking | kubectl apply -f -
kustomize build overlays/production/istio/namespace | kubectl apply -f -
```

- These overlays will deploy Istio resources into the `staging` and `production` namespaces.
- The base resources remain DRY and reusable.
- You can add further patches in the overlays if you need to customize per environment.
