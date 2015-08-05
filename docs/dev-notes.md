# Background
Diego Docker Cache aims to:
- guarantee that we fetch the same layers when the user scales an application up.
- guarantee uptime (if the [Docker Hub](https://hub.docker.com/) goes down we shall be able to start a new instance)
- support private docker images

# Image Caching

To guarantee predictable scaling and uptime we have to copy the Docker image from the public Docker Hub to a [private registry](https://docs.docker.com/registry/).

## Idea

The basic steps we need to perform are:
* pull image from public Docker Hub
* tag the image
* push the tagged image to a private docker registry
* clean up the pulled image

## Opt-in

Image caching in private docker registry will not be enabled by default. User can opt-in by:
```
cf set-env <app> DIEGO_DOCKER_CACHE true
```

---
# Implementation details

## Security

The Docker Registry can be run in 3 flavors with regards to security:
- HTTP
- HTTPS with self-signed certificate
- HTTPS with CA signed certificate

The first two are considered insecure by the docker registry client. The client needs additional configuration to allow access to insecure registries.

## Docker registry discovery

The Docker Registry is registered with Consul under the url `http://docker-registry.service.cf.internal:8080` so that it can be discovered by the Stager.

This will help us easily discover the service instances. We do not need to specify concrete IPs of the service nodes in the [BOSH](http://bosh.io/) manifests as well.

We can use the [Consul service nodes endpoint](http://www.consul.io/docs/agent/http.html#_v1_catalog_service_lt_service_gt_) (/v1/catalog/service/<service>) to get a list of all service instances:

```
bosh deployment ~/deployments/bosh-lite/diego.yml
bosh ssh cc_bridge_z1 0
curl http://localhost:8500/v1/catalog/service/docker-registry
[
  {
    "Node": "docker-cache-0",
    "Address": "10.244.2.6",
    "ServiceID": "docker-registry",
    "ServiceName": "docker-registry",
    "ServiceTags": [
      "docker-cache-0"
    ],
    "ServiceAddress": "",
    "ServicePort": 0
  }
]
```

To execute the above request we use `localhost:8500` which is the default URL for the Consul Agent running on the cc_bridge machine.

Currently `ServicePort` is always 0 since we do not register a concrete port and rely on hardcoded one (`8080`).

## Components
The following components are involved in the staging and running of Docker image:

- **Cloud Controller**: Initiates desire app request
- **Stager**: Launches staging container with [Docker Lifecycle](https://github.com/cloudfoundry-incubator/docker_app_lifecycle)
- **Builder**: Performs the caching of the image
- **Cloud Controller**: Stores the cached image URL for subsequent use

### Cloud Controller
The table `droplets` is extended with `cached_docker_image` that stores the image URL returned by the staging process.

When desire app request is generated, the `cached_docker_image` is sent, instead of the user provided `docker_image` in `app` table.

If the user opts-out of caching the image, on re-stage we have to nil the `cached_docker_image` since this will disable the caching on desire app request.

### Stager
The app environment is propagated to the stager, which activates the caching in the Docker lifecycle builder using its `-cacheDockerImage` command line flag.

The [Docker Lifecycle](https://github.com/cloudfoundry-incubator/docker_app_lifecycle)'s Builder runs inside a container. This container should allow access to internally hosted (in the protected isolated CF network) registry. The container is configured by the [Stager](https://github.com/cloudfoundry-incubator/stager) that requests launch of the Docker Lifecycle builder task.

To be able to access the private Docker Registry we have to open up the container. Stager fetches a list of all registered `docker-registry` service instances from Consul cluster. This returns all registered IPs and ports and we shall poke holes allowing access to all those IPs and ports. To do this Stager shall be provided with the URL of the Consul Agent with `-consulCluster=http://localhost:8500`.

There's a small race in that a new Docker registry may appear/disappear while we are staging. This may result in a staging failure but this should be very infrequent.

The Stager is instructed to add the registry service instances as insecure with the help of `-insecureDockerRegistry` flag. This flag shall be provided if the registry is accessed by either HTTP or HTTPS with self-signed certificate.

### Builder  
[Docker Lifecycle](https://github.com/cloudfoundry-incubator/docker_app_lifecycle)'s Builder pulls the image and stores it locally in the container. Then it tags and pushes it to the private registry to cache the image.

This approach ensures that the staging remains isolated with respect to disk and CPU usage and that we can easily scale the staging of Docker images. We also effectively limit the disk space that can be used in the staging container (by default 4096 MiB).

#### Configuration

The `-dockerRegistryAddresses` argument is used to provide a comma separated list of `<ip>:<port>` pairs to access all Docker Registry instances.

The Docker Lifecycle's builder needs to access the registry to fetch image meta data. To do this it makes use of some [Docker code](https://github.com/cloudfoundry-incubator/docker_app_lifecycle/tree/master/Godeps/_workspace/src/github.com/docker). The code has to be configured to allow insecure connections with the optional command line argument `-insecureDockerRegistries`. The argument accepts comma separated list of `<ip>:<port>` pairs. The list is available in Consul cluster, but Builder is running inside a container with no access to Consul Agent. That's why the `-insecureDockerRegistries` list is built by Stager.

As a side effect the docker app life-cycle builder may provide access to public registries that are insecure (either HTTP or self-signed cert HTTPS) if they are listed in `-insecureDockerRegistries`.

The `-dockerDaemonExecutablePath=<path>` is used to configure the correct path to the Docker executable in different environments (Inigo, different Cells, unit testing).

#### Processes

The caching process runs Docker daemon in privileged container. The daemon runs in parallel to the Docker Lifecycle's builder.

The Builder is responsible for:  
- waiting the daemon to start by reading the response from daemon's `_ping` access point  
- fetching metadata  
- caching image by invoking external `docker` CLI processes for:
   - logging
   - pulling image
   - tagging image
   - pushing image

The Docker daemon accepts requests made directly from Builder or triggered by the `docker` CLI.

The builder and daemon processes are launched as [ifrit](https://github.com/tedsuo/ifrit) group, which guarantees that if one of them exits or crashes the other one will be terminated. We also use ifrit to be able to terminate both of them if the parent process is signaled.

#### Cached image URL
The images that are pushed to the private registry are stored as `<ip>:<port>/<GUID>:latest`, where GUID is a generated [V4 uuid](https://tools.ietf.org/html/rfc4122). For example: `10.244.2.6:8080/ba8967eb-312e-4582-4dc6-4bfe0975472c`

To store the image in the private registry we have to tag them. The tagging has two purposes:
1. We target the private registry host (since the tag includes the host)
1. Associates the image to the desired application

The cached images are stored in `library/` with tag `latest`. This adds to the example above the `latest` suffix: `10.244.2.6:8080/ba8967eb-312e-4582-4dc6-4bfe0975472c:latest`

The URL is then sent back to CC as a URL pointing back to the private docker registry.

## Running Docker applications

Docker applications are run by Garden. The Garden Linux component takes care to fetch the docker image and run it inside a container.

We don't need to add egress rules to allow access to the Docker Registry instances since Garden fetches the image metadata and filesystem before the container is started.

However the insecure registry instances have to be known to Garden Linux, because it uses Docker code to download the image. We can override the Diego release properties ([bosh-lite example](https://github.com/cloudfoundry-incubator/diego-docker-cache-release/blob/develop/stubs-for-diego-release/bosh-lite-property-overrides.yml)) to add `-insecureDockerRegistryList=<ip:port list>` to Garden Linux parameters in its control script.

## Private images

Users need to provide credentials to access the Docker Hub private images. The default flow is as follows:
* user provides credentials to `docker login -u <user> -p <password> -e <email>`
* the login generates ~/.dockercfg file with the following content:
```
{
	"https://index.docker.io/v1/": {
		"auth": "bXlVc2VyOm15c2VjUmV0",
		"email": "<user email>"
	}
}
```
* `docker pull` can now use the authentication token in the configuration file

Therefore we can implement two possible flows in Diego using `docker login`:
* user provides user/password
* user provides authentication token and email

The second option should be safer since the authentication token is supposed to be temporary, while user/password credentials can be used to generate new token and gain access to Docker Hub account.

### Docker authentication token

The current (May 2015) authentication token contains base64 encoded `<user>:<password>`. For example the token `bXlVc2VyOm15c2VjUmV0` above is actually `myUser:mysecRet`. This compromises the idea to use token to prevent storing the user credentials.

The Cloud Controller models produce debug log entry with the arguments used to start the application. Since these arguments contain the authentication token this presents a security risk as operators or admins shall not be able to see the user's credentials.

### Docker email

`docker login` always requires email, although it is not used if user/password login succeeds. This is already reported as https://github.com/docker/docker/issues/6400 and may be fixed in the future.

### In memory storage of credentials or token

We cannot store application metadata in-memory since we may have more than one CC instance. The `create app` and `start app` requests to CC may reach different instances so the authentication info stored in-memory will be available only for the one that has received the create request, but the rest would not have the metadata.

### OAuth

Docker seems to support OAuth. To use OAuth one should either:
* programatically use Docker golang code
* use the Docker REST endpoints with custom client

Both approaches seems to bring too much overhead. We either have to adapt to Docker code changes or create a custom client that can login and pull.

### Design

Since we cannot use the Docker authentication token as a secure replacement of user/password we shall do the following on CC side:
* accept user, password & email as credentials needed to pull private Docker image
* encrypt the credentials in the database
* propagate the credentials to Diego via stage app request

On Diego side shall:
* propagate the credentials to `stager` and Docker `builder`
* Builder propagates the credentials to Docker golang API to fetch the private image metadata
* Builder performs `docker login` with the credentials to enable `docker pull` of private image
