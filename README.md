# Fuseki Container Image

- Base Fuseki with Jena Commands
- GeoSPARQL
- RDF Delta Fuseki
- RDF Delta Server

## Container Image

The image is available as `ghcr.io/kurrawong/fuseki:<version>` where version is composed of the jena version and this container image's build version number.

For example, `ghcr.io/kurrawong/fuseki:5.2.0-0` is built on Jena Fuseki 5.2.0 and the `0` indicates the build number of this container image. If we release a new build that's still based on Jena 5.2.0, the build number will be incremented to 1 to form `ghcr.io/kurrawong/fuseki:5.2.0-1`.

See the tagged [images here](https://github.com/Kurrawong/fuseki-container-image/pkgs/container/fuseki).

## Usage

## Entrypoints

## Adding Fuseki extensions to the classpath

## Local Development

See [Taskfile.yml](Taskfile.yml) for local development commands.
