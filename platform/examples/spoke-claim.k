# Example spoke claim (user/claims/*.yaml),

_name = "my-spoke"

items = [
    {
        apiVersion = "kro.run/v1alpha1"
        kind = "VPCNetwork"
        metadata = {
            name = _name
            namespace = "default"
        }
        spec = {
            name = _name
            vpcCIDR = "10.0.0.0/16"
            az1 = "us-east-1a"
            az2 = "us-east-1b"
        }
    }
    {
        apiVersion = "kro.run/v1alpha1"
        kind = "EKSCluster"
        metadata = {
            name = _name
            namespace = "default"
        }
        spec = {
            name = _name
            version = "1.36"
            networkName = _name 
            amiType = "BOTTLEROCKET_x86_64"
            capacityType = "ON_DEMAND"
            diskSize = 20
            instanceTypes = ["t3.medium"]
            desiredSize = 1
            minSize = 1
            maxSize = 3
        }
    }
]
