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

### Prerequisites

To make data loading an managing easier, it is recommended to install the [kurra](https://github.com/Kurrawong/kurra) CLI.

```
uv tool install kurra
```

### Running a single Fuseki server with GeoSPARQL support

```
task fuseki:build

task fuseki:up
```

This will enable the Fuseki UI at http://localhost:3030/

#### GeoSPARQL config and testing

A testdatabase is configured in `testdata/config-geosparql.ttl`. It has all features enabled by default. You can disable them by setting the following properties to `false`:

```
# some GeoSPARQL settings. See https://jena.apache.org/documentation/geosparql/geosparql-fuseki.html
geosparql:inference            true ; # GeoSPARQL RDFS schema and inferencing (adds additional statements to the dataset)
geosparql:queryRewrite         true ; # Simplifies queries, relies on applyDefaultGeometry
geosparql:applyDefaultGeometry true ; # Makes the dataset less dependent on one serialization. Adds additional geo:hasSerialization statements to the dataset
geosparql:indexEnabled         true ; # Enable caching of re-usable data to improve query performance
geosparql:validateGeometryLiterals true ; # Logs warnings when adding invalid geometry

```

With the fuseki up and running, you can create this dataset using the following command:

```
kurra db create http://localhost:3030 --config ./testdata/config-geosparql.ttl
```

You'll see a warning in the docker logs of the `fuseki` service:

```
WARN  GeoAssembler    :: Dataset empty. Spatial Index not constructed. Server will require restarting after adding data and any updates to build Spatial Index.
```

We can add some data and restart the server:
```
kurra db upload ./testdata/data-geosparql.ttl http://localhost:3030/test-geosparql

task fuseki:restart
```

Now you should see that the spatial index was created:

```
SpatialIndex    :: Saving Spatial Index - Completed: /fuseki/databases/test-geosparql/spatial.index
```

To verify that the dataset is working, go to http://localhost:3030/#/dataset/test-geosparql/query and try some GeoSPARQL queries.

#### Example queries using the testdata

Useful tools to construct and query WKT geometries: https://www.geometrymapper.com/ https://wktmap.com/

Find all addresses within a certain area:

```
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>

SELECT DISTINCT ?address
WHERE {
  BIND("POLYGON ((152.685242 -27.161808, 152.698975 -27.829361, 153.492737 -27.829361, 153.435059 -27.178912, 152.685242 -27.161808))"^^geo:wktLiteral AS ?polygon)
  ?address geo:hasGeometry / geo:asWKT ?point .
  FILTER(geof:sfWithin(?point, ?polygon))
}
# returns
# 1<https://linked.data.gov.au/dataset/qld-addr/address/65cb1e52-fc1d-5dee-a2d2-ea7882d12c7e>
# 2<https://linked.data.gov.au/dataset/qld-addr/address/beb30200-2988-5c0a-942b-36cd2138805a>
```

Note that thanks to the `applyDefaultGeometry` and `inference` options, the following also works:

```
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>

SELECT DISTINCT ?address
WHERE {
  BIND("POLYGON ((152.685242 -27.161808, 152.698975 -27.829361, 153.492737 -27.829361, 153.435059 -27.178912, 152.685242 -27.161808))"^^geo:wktLiteral AS ?polygon)
  ?address geo:hasDefaultGeometry / geo:hasSerialization ?point .
  FILTER(geof:sfWithin(?point, ?polygon))
}

# returns
# 1<https://linked.data.gov.au/dataset/qld-addr/address/65cb1e52-fc1d-5dee-a2d2-ea7882d12c7e>
# 2<https://linked.data.gov.au/dataset/qld-addr/address/beb30200-2988-5c0a-942b-36cd2138805a>
```

These queries are useful when dealing with dynamic, user-defined polygons. However, much more is possible when polygons are included in the dataset, and thus also in the spatial index.


The dataset also contains a broad bounding box of Australia, which then gets included in the spatial index.

Thanks to the query rewriting, it means we can use a much simpler query to list all addresses in Australia:

```
PREFIX addr:    <https://linked.data.gov.au/def/addr/>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>

SELECT DISTINCT ?address
WHERE {
  ?address a addr:Address .
  <https://example.org/australia> geo:sfContains ?address .
}

# returns all 4 addresses in the test dataset
```

Or in reverse, we can look up which country a certain address is located in:

```
PREFIX dbo: <http://dbpedia.org/ontology/>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>

SELECT DISTINCT ?country
WHERE {
  ?country a dbo:Country .
  <https://linked.data.gov.au/dataset/qld-addr/address/65cb1e52-fc1d-5dee-a2d2-ea7882d12c7e> geo:sfWithin ?country .
}

# returns <https://example.org/australia>
```

#### Property & filter functions

Note that there might be some confusion between the spatial property & filter functions in the Jena namespace ([spatial:](http://jena.apache.org/spatial#) and [spatialF:](http://jena.apache.org/function/spatial#)) and those specified in the [standard GeoSPARQL ontology namespace](https://docs.ogc.org/is/22-047r1/22-047r1.html#_ba86b43c-9cf4-fa58-f9b0-83d082598047) ([geo:](http://www.opengis.net/ont/geosparql#) and [geof:](http://www.opengis.net/def/function/geosparql/)).

Because of this, none of the [Non-topological Query Functions](https://docs.ogc.org/is/22-047r1/22-047r1.html#_32d62c99-ffc4-40b3-93ca-aeef5272b492) specified in the GeoSPARQL standard seem to work with the correct namespaces. Instead, there are equivalent implementations of these functions in the Jena namespace, sometimes under a different name.  

For example, `geof:distance` does not seem to work with Jena, whereas `spatialF:distance` does.

```
PREFIX spatialF: <http://jena.apache.org/function/spatial#>
PREFIX uom: <http://www.opengis.net/def/uom/OGC/1.0/>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

SELECT ?distance
WHERE {
  <https://linked.data.gov.au/dataset/qld-addr/address/65cb1e52-fc1d-5dee-a2d2-ea7882d12c7e> geo:hasDefaultGeometry / geo:hasSerialization ?point1 .
  <https://linked.data.gov.au/dataset/qld-addr/address/2fd46078-88c0-5f30-b43e-d2908d9445b6> geo:hasDefaultGeometry / geo:hasSerialization ?point2 .
  BIND(xsd:decimal(spatialF:distance(?point1, ?point2, uom:kilometre)) AS ?distance) .
}
# returns "129.601686"^^<http://www.w3.org/2001/XMLSchema#decimal>
```

That means when migrating from other systems that do implement the GeoSPARQL standard as-is, some query rewriting might be required to ensure a seamless transition.

Jena supports property & filter functions as specified in the documentation: https://jena.apache.org/documentation/geosparql/index

For example, find addresses less than 150 kilometres from a reference point using latitude -27.5 and longitude 152.5

```
PREFIX spatial: <http://jena.apache.org/spatial#>
PREFIX uom: <http://www.opengis.net/def/uom/OGC/1.0/>
PREFIX addr:    <https://linked.data.gov.au/def/addr/>

SELECT DISTINCT ?address
WHERE {
  ?address a addr:Address ;
           spatial:nearby(-27.5 152.5 100 uom:kilometre)
}

# returns
#<https://linked.data.gov.au/dataset/qld-addr/address/2fd46078-88c0-5f30-b43e-d2908d9445b6>
#<https://linked.data.gov.au/dataset/qld-addr/address/65cb1e52-fc1d-5dee-a2d2-ea7882d12c7e>
```

Find all addresses north of that same point:
```
PREFIX spatial: <http://jena.apache.org/spatial#>
PREFIX uom: <http://www.opengis.net/def/uom/OGC/1.0/>
PREFIX addr:    <https://linked.data.gov.au/def/addr/>

SELECT DISTINCT ?address
WHERE {
  ?address a addr:Address ;
           spatial:north(-27.5 152.5)
}

# returns <https://linked.data.gov.au/dataset/qld-addr/address/2fd46078-88c0-5f30-b43e-d2908d9445b6>
```

## Entrypoints

## Adding Fuseki extensions to the classpath

## Local Development

See [Taskfile.yml](Taskfile.yml) for local development commands.

## Jena patches/expansions

We can build patches for Jena ourselves by developing on a specific version of the Jena source code, and including patches in `/docker/patches`.
A simple example of this is the addition of the GeoSPARQL dependency in `/docker/patches/enable-geosparql.diff` as inspired by the zazuko docker image.

The process to add these to our own jena deployment is to check out the current Jena version tag from https://github.com/apache/jena , e.g. using `git checkout jena-5.2.0`

Then make the necessary changes, and run `git diff > my-patch.diff` and add `my-patch.diff` to `/docker/patches` and in the `Dockerfile`.
