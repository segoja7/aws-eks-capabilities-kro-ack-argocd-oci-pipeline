import json
import blueprints

# EKS cluster as a KRO API, provisioned by ACK (iam + eks controllers).

_cluster_assume_role = json.encode({
    Version = "2012-10-17"
    Statement = [{
        Effect = "Allow"
        Principal = {Service = "eks.amazonaws.com"}
        Action = "sts:AssumeRole"
    }]
})

_node_assume_role = json.encode({
    Version = "2012-10-17"
    Statement = [{
        Effect = "Allow"
        Principal = {Service = "ec2.amazonaws.com"}
        Action = "sts:AssumeRole"
    }]
})

_addon = lambda id: str, addonName: str -> {str:} {
    {
        id = id
        template = {
            apiVersion = "eks.services.k8s.aws/v1alpha1"
            kind = "Addon"
            metadata.name = r"${schema.spec.name}-" + addonName
            spec = {
                name = addonName
                clusterName = r"${cluster.spec.name}"
                resolveConflicts = "OVERWRITE"
            }
        }
    }
}


_addons = [
    _addon("addonPodIdentity", "eks-pod-identity-agent")
    _addon("addonVpcCni", "vpc-cni")
    _addon("addonCoredns", "coredns")
    _addon("addonKubeProxy", "kube-proxy")
]


_privateSubnetRefs = [
    {from = {name = r"${schema.spec.networkName}-private-subnet-1"}}
    {from = {name = r"${schema.spec.networkName}-private-subnet-2"}}
]

rgd = blueprints.ResourcegraphdefinitionBlueprint {
    _metadataName = "eks-cluster"
    _schema = {
        apiVersion = "v1alpha1"
        kind = "EKSCluster"
        group = "kro.run"
        spec = {
            name = "string | required=true"
            version = 'string | default="1.36"'
            networkName = "string | required=true"
            amiType = 'string | default="BOTTLEROCKET_x86_64"'
            capacityType = 'string | default="ON_DEMAND"'
            diskSize = "integer | default=20"
            instanceTypes = "[]string"
            desiredSize = "integer | default=1"
            minSize = "integer | default=1"
            maxSize = "integer | default=3"
            authenticationMode = 'string | default="API_AND_CONFIG_MAP"'
            endpointPublicAccess = "boolean | default=true"
            endpointPrivateAccess = "boolean | default=true"
        }
        status = {
            clusterARN = r"${cluster.status.ackResourceMetadata.arn}"
        }
    }
    _resources = [
        {
            id = "clusterRole"
            template = {
                apiVersion = "iam.services.k8s.aws/v1alpha1"
                kind = "Role"
                metadata.name = r"${schema.spec.name}-cluster-role"
                spec = {
                    name = r"${schema.spec.name}-cluster-role"
                    assumeRolePolicyDocument = _cluster_assume_role
                    policies = [
                        "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
                        "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
                    ]
                }
            }
        }
        {
            id = "nodeRole"
            template = {
                apiVersion = "iam.services.k8s.aws/v1alpha1"
                kind = "Role"
                metadata.name = r"${schema.spec.name}-node-role"
                spec = {
                    name = r"${schema.spec.name}-node-role"
                    assumeRolePolicyDocument = _node_assume_role
                    policies = [
                        "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
                        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
                        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
                    ]
                }
            }
        }
        {
            id = "cluster"
            template = {
                apiVersion = "eks.services.k8s.aws/v1alpha1"
                kind = "Cluster"
                metadata.name = r"${schema.spec.name}"
                spec = {
                    name = r"${schema.spec.name}"
                    roleARN = r"${clusterRole.status.ackResourceMetadata.arn}"
                    version = r"${schema.spec.version}"
                    accessConfig = {
                        authenticationMode = r"${schema.spec.authenticationMode}"
                        bootstrapClusterCreatorAdminPermissions = True
                    }
                    resourcesVPCConfig = {
                        subnetRefs = _privateSubnetRefs
                        endpointPublicAccess = r"${schema.spec.endpointPublicAccess}"
                        endpointPrivateAccess = r"${schema.spec.endpointPrivateAccess}"
                    }
                    tags = {
                        ManagedBy = "kro"
                        Project = "platform-engineering-from-scratch"
                    }
                }
            }
        }
        {
            id = "nodegroup"
            template = {
                apiVersion = "eks.services.k8s.aws/v1alpha1"
                kind = "Nodegroup"
                metadata.name = r"${schema.spec.name}-ng"
                spec = {
                    name = r"${schema.spec.name}-ng"
                    clusterName = r"${cluster.spec.name}"
                    nodeRole = r"${nodeRole.status.ackResourceMetadata.arn}"
                    subnetRefs = _privateSubnetRefs
                    amiType = r"${schema.spec.amiType}"
                    capacityType = r"${schema.spec.capacityType}"
                    diskSize = r"${schema.spec.diskSize}"
                    instanceTypes = r"${schema.spec.instanceTypes}"
                    scalingConfig = {
                        desiredSize = r"${schema.spec.desiredSize}"
                        minSize = r"${schema.spec.minSize}"
                        maxSize = r"${schema.spec.maxSize}"
                    }
                }
            }
        }
        # --- Hub-Spoke GitOps hook: auto-register this spoke into the hub ArgoCD ---
        {
            id = "hubConfig"
            externalRef = {
                apiVersion = "v1"
                kind = "ConfigMap"
                metadata = {
                    name = "platform-config"
                    namespace = "kube-system"
                }
            }
        }
        {
            # Grant the hub's ArgoCD capability role access to THIS spoke. 
            # The principal ARN is read from the hubConfig ConfigMap (externalRef).
            
            id = "argocdAccessEntry"
            template = {
                apiVersion = "eks.services.k8s.aws/v1alpha1"
                kind = "AccessEntry"
                metadata.name = r"${schema.spec.name}-argocd-access"
                spec = {
                    clusterName  = r"${cluster.spec.name}"
                    principalARN = r"${hubConfig.data.argocdRoleArn}"
                    type = "STANDARD"
                    accessPolicies = [{
                        policyARN = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
                        accessScope = {
                            type = "cluster"
                        }
                    }]
                }
            }
        }
        {
            # Register this spoke in the hub's ArgoCD as a target cluster. 
            id = "argocdClusterSecret"
            template = {
                apiVersion = "v1"
                kind = "Secret"
                metadata = {
                    name = r"${schema.spec.name}"
                    namespace = "argocd"
                    labels = {
                        "argocd.argoproj.io/secret-type" = "cluster"
                    }
                }
                stringData = {
                    name = r"${schema.spec.name}"
                    server = r"${cluster.status.ackResourceMetadata.arn}"
                    project = "default"
                }
            }
        }
    ] + _addons
}
