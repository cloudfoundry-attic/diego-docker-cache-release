# docker-registry-release
BOSH release for Docker Registry

---
## Initial Setup

This BOSH release doubles as a `$GOPATH`. It will automatically be set up for
you if you have [direnv](http://direnv.net) installed.

    # fetch release repo
    mkdir -p ~/workspace
    cd ~/workspace
    git clone https://github.com/cloudfoundry-incubator/docker-registry-release.git
    cd docker-registry-release/

    # automate $GOPATH and $PATH setup
    direnv allow

    # initialize and sync submodules
    ./scripts/update

If you do not wish to use direnv, you can simply `source` the `.envrc` file in the root
of the release repo.  You may manually need to update your `$GOPATH` and `$PATH` variables
as you switch in and out of the directory.

---
## Deploying to a local BOSH-Lite instance

1. Follow the instructions in [Diego Release](https://github.com/cloudfoundry-incubator/diego-release) and install CF

1. When generating the Diego's manifest (step 9) use the following set of files instead: 

        cd ~/workspace/diego-release
        ./scripts/generate-deployment-manifest \
          ~/deployments/bosh-lite/director.yml \
          ~/workspace/docker-registry-release/stubs-for-diego-release/bosh-lite-property-overrides.yml \
          manifest-generation/bosh-lite-stubs/instance-count-overrides.yml \
          manifest-generation/bosh-lite-stubs/persistent-disk-overrides.yml \
          manifest-generation/bosh-lite-stubs/iaas-settings.yml \
          manifest-generation/bosh-lite-stubs/additional-jobs.yml \
          ~/deployments/bosh-lite \
          > ~/deployments/bosh-lite/diego.yml
        bosh deployment ~/deployments/bosh-lite/diego.yml

1. Deploy Diego:

        bosh create release --force
        bosh -n upload release
        bosh -n deploy

1. Generate and target Docker Registry's manifest:

        cd ~/workspace/docker-registry-release
        ./scripts/generate-deployment-manifest ~/deployments/bosh-lite/director.yml \
            manifest-generation/bosh-lite-stubs/property-overrides.yml \
            manifest-generation/bosh-lite-stubs/instance-count-overrides.yml \
            manifest-generation/bosh-lite-stubs/persistent-disk-overrides.yml \
            manifest-generation/bosh-lite-stubs/iaas-settings.yml \
            manifest-generation/bosh-lite-stubs/additional-jobs.yml \
            ~/deployments/bosh-lite \
            > ~/deployments/bosh-lite/docker-registry.yml
        bosh deployment ~/deployments/bosh-lite/docker-registry.yml

1. Deploy this Docker Registry:

        bosh create release --force
        bosh -n upload release
        bosh -n deploy
        
## Running Acceptance Tests
See [docker-registry-acceptance-tests](https://github.com/cloudfoundry-incubator/docker-registry-acceptance-tests/)

## Caching docker image with Diego

1. Install CF CLI v6.10.0+ (or follow the guide in [Migrating to Diego](https://github.com/cloudfoundry-incubator/diego-design-notes/blob/master/migrating-to-diego.md#installing-the-diego-beta-cli-plugin))
1. Install `diego-beta` CLI Plugin
 
        cf add-plugin-repo CF-Community http://plugins.cloudfoundry.org/
        cf install-plugin Diego-Beta -r CF-Community

1. Login to CF
 
        cf api --skip-ssl-validation api.10.244.0.34.xip.io
        cf auth admin admin

1. Push your docker application

        cf docker-push <application_name> <docker_image> --no-start 
   
1. Enable caching by setting `DIEGO_DOCKER_CACHE` boolean environment variable
 
        cf set-env <application_name> DIEGO_DOCKER_CACHE true
   
1. Start the application:

        cf start <application_name>
        
