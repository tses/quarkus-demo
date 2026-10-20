# ocp-demo-app — GitOps repository (dev)

Desired state of **ocp-demo-app** in the `ocp-demo-dev` project, synced by
**OpenShift GitOps (Argo CD)**.

```
base/                  Deployment, Service, Route (environment-independent)
overlays/dev/          namespace, image (by digest), traceability annotations,
                       env-patch.yaml (APP_COLOUR — app config for dev)
```

- Change the app config by editing `overlays/dev/env-patch.yaml` (e.g.
  `APP_COLOUR: green`) — Argo CD rolls out new pods; `/api/info` shows it.

- The image in `overlays/dev/kustomization.yaml` is updated by the CI pipeline
  (`kustomize edit set image ocp-demo-app=<repo>@<digest>`) after the ACS gate.
  The file is kept in kustomize's own format (no comments) so pipeline diffs
  show only the digest.
- Do not change the cluster by hand: Argo CD reverts drift (self-heal).
- Roll back with `git revert` of the image commit.
