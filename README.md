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

### Running a single Fuseki server with GeoSPARQL support

```
task fuseki:build

task fuseki:up
```

This will enable the Fuseki UI at http://localhost:3030/

### Running multple Fuseki servers with RDF Delta


## Entrypoints

## Adding Fuseki extensions to the classpath

## Local Development

See [Taskfile.yml](Taskfile.yml) for local development commands.

## Jena patches/expansions

We can build patches for Jena ourselves by developing on a specific version of the Jena source code, and including patches in `/docker/patches`.
A simple example of this is the addition of the GeoSPARQL dependency in `/docker/patches/enable-geosparql.diff` as inspired by the zazuko docker image.

The process to add these to our own jena deployment is to check out the current Jena version tag from https://github.com/apache/jena , e.g. using `git checkout jena-5.2.0`

Then make the necessary changes, and run `git diff > my-patch.diff` and add `my-patch.diff` to `/docker/patches` and in the `Dockerfile`.
