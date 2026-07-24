# user/claims — self-service claims (plain YAML, git-direct)
## How to request a spoke

1. Copy the platform's rendered template:  `examples/spoke-claim.yaml`
2. Rename it here (e.g. `my-spoke.yaml`) and edit the names/sizes.
3. Commit + push → ArgoCD applies it → KRO/ACK provision your spoke and
   auto-register it into the hub.

To remove it: delete your YAML file and push (ArgoCD prunes the claim → KRO/ACK
cascade-delete the spoke).
