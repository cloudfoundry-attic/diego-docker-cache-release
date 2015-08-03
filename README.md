# diego-docker-cache
BOSH release for Diego Docker Cache

---
## Initial Setup

This BOSH release doubles as a `$GOPATH`. It will automatically be set up for
you if you have [direnv](http://direnv.net) installed.

    # fetch release repo
    mkdir -p ~/workspace
    cd ~/workspace
    git clone https://github.com/cloudfoundry-incubator/diego-docker-cache.git
    cd diego-docker-cache/

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
          ~/workspace/diego-docker-cache/stubs-for-diego-release/bosh-lite-property-overrides.yml \
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

1. Generate and target Diego Docker Cache's manifest:

        cd ~/workspace/diego-docker-cache
        ./scripts/generate-deployment-manifest ~/deployments/bosh-lite/director.yml \
            manifest-generation/bosh-lite-stubs/property-overrides.yml \
            manifest-generation/bosh-lite-stubs/instance-count-overrides.yml \
            manifest-generation/bosh-lite-stubs/persistent-disk-overrides.yml \
            manifest-generation/bosh-lite-stubs/iaas-settings.yml \
            manifest-generation/bosh-lite-stubs/additional-jobs.yml \
            ~/deployments/bosh-lite \
            > ~/deployments/bosh-lite/docker-cache.yml
        bosh deployment ~/deployments/bosh-lite/docker-cache.yml

1. Deploy the Docker Cache:

        bosh create release --force
        bosh -n upload release
        bosh -n deploy

## Configuring registry

### Backend storage

You can configure the [Docker Registry](https://docs.docker.com/registry/) backend storage in [property-overrides.yml](manifest-generation/bosh-lite-stubs/property-overrides.yml). Here is what you have to include for each supported storage type:

#### Filesystem
This is the default storage type. You can simply omit the property overrides or explicitly add:

```
docker_registry:
  storage:
    name: filesystem
```

#### AWS S3

```
docker_registry:
  storage:
    name: s3
    s3:
      bucket: <bucket name>
      accesskey: <access key>
      secretkey: <secret key>
      region: <region name, i.e. us-east-1>
```


Save the property changes and then [generate the manifest and deploy](https://github.com/cloudfoundry-incubator/diego-docker-cache-release#deploying-to-a-local-bosh-lite-instance) the Diego Docker Cache release.

### TLS

Docker Registry can be configured to use TLS for secure communication. To do this:
1. Obtain a certificate and key. This can be done with OpenSSL:
```
openssl genrsa -out server.key 1024
openssl req -new -key server.key -out server.csr
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt
```
1. Edit [property-overrides.yml](manifest-generation/bosh-lite-stubs/property-overrides.yml). You have to add the generated certificate and key:
```
docker_registry:
  tls:
    enabled: true
    certificate: |
      -----BEGIN CERTIFICATE-----
      ... content of server.crt file ...
      -----END CERTIFICATE-----
    key: |
      -----BEGIN RSA PRIVATE KEY-----
      ... content of server.key file ...
      -----END RSA PRIVATE KEY-----
```
  
Save the property changes and then [generate the manifest and deploy](https://github.com/cloudfoundry-incubator/diego-docker-cache-release#deploying-to-a-local-bosh-lite-instance) the Diego Docker Cache release.

## Running Acceptance Tests
See [docker-cache-acceptance-tests](https://github.com/cloudfoundry-incubator/docker-cache-acceptance-tests/)

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
        
