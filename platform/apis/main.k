import rgds.eks
import rgds.vpc

# Layer 1 — the platform's self-service APIs (KRO RGDs). Scoped to the hub-spoke

items = [vpc.rgd, eks.rgd]
