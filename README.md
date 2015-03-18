# docker-registry-release
BOSH release for Docker Registry

## Deploying

1. Follow the instructions in [Diego Release](https://github.com/cloudfoundry-incubator/diego-release) and install CF

1. When generating the Diego's manifest (step 9) use the following set of files instead: 

        cd ~/workspace/diego-release
        ./scripts/generate-deployment-manifest bosh-lite ../cf-release \
             ~/deployments/bosh-lite/director.yml \
             ~/workspace/diego-release/templates/enable_diego_docker_in_cc.yml \
             ~/workspace/docker-registry-release/templates/diego-docker-registry-stub.yml > \
             ~/deployments/bosh-lite/diego.yml

1. Deploy Diego
1. Deploy this Docker Registry:

        cd ~/workspace/docker-registry-release
        bosh -d templates/bosh-lite.yml deploy 
