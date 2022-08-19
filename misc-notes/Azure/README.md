## Apply a DNS label to the K8s service in AKS
[Azure docs link](https://docs.microsoft.com/en-us/azure/aks/static-ip#apply-a-dns-label-to-the-service)
Add following annotation to a K8s `LoadBalancer` type `Service`-
`service.beta.kubernetes.io/azure-dns-label-name: myserviceuniquelabel`

Azure will then automatically append a default suffix, such as `<location>.cloudapp.azure.com` 
Full URL- `<myserviceuniquelabel>.<location>.cloudapp.azure.com`

Verification: `dig <myserviceuniquelabel>.<location>.cloudapp.azure.com` should give Answer with IP of the LoadBalancer

To publish the service on your own domain, see [Azure DNS](https://azure.microsoft.com/en-us/services/dns/) and the [external-dns](https://github.com/kubernetes-sigs/external-dns) project.
