<p align="center">
<a href="https://datashare.icij.org/">
  <img src="https://datashare.icij.org/android-chrome-512x512.png" width="158px">
</a>
</p>
<h1 align="center">Datashare Playground</h1>

A series of bash utilities to perform common operations on Datashare documents stored in ElasticSearch.

## Setup

To run those scripts only needs to have access to the ElasticSearch URL which must be stored in an 
environement variable called `ELASTICSEARCH_URL`. To avoid setting up this variable everytime you
use those script, you can store in a `.env` at the root of this directory:

```
ELASTICSEARCH_URL=http://localhost:9200
```

## Scripts

Here are the main scripts available in this repository:

```bash
.
├── document
│   ├── count.sh # Count documents under a given path
│   ├── move.sh # Move documents from a directory to another
│   └── reindex.sh # Reindex files from an index and under a specific directory
├── index
│   ├── clone.sh # Clone a given index into another
│   └── list.sh # List all indices
├── lib
│   └── sync.sh # Sync this directory with another location with rsync
└── task
    ├── cancel.sh # Cancel a given task
    ├── get.sh # Get a given task status
    └── watch.sh # Watch a given task status
```

## Cookbook

This cookbook list real-life examples of how to use those scripts.

### Copy documents from an index to another

An example showing how to copy documents from the `kimchi` index to the `miso` while taking care of updating the path.

**1. Create a clone of the "miso" index to avoid messing up with data:**

```
./index/clone.sh miso miso-tmp
```

**2. Reindex documents from `kimchi` under the folder `/disk/kimchi/tofu` onto `miso-tmp`:**

```
./index/reindex.sh kimchi miso-tmp /disk/kimchi/tofu
```

**2bis. While the reindex is being done, we can watch it's progress using the return task id from the last command:**

```
./task/watch.sh 8UnTR-67T8y0idkyndf77Q:36041259
```

**3. The document moved to `miso-tmp` might used the wrong path so we update it as well:**

```
./document/move.sh miso-tmp /disk/kimchi/tofu /disk/miso/tofu
```

**4. Finally, after checking everything is fine, we substitue the `miso` index by `miso-tmp`:**

```
curl -XDELETE http;//localhost:9200/miso
./index/clonse.sh miso-tmp miso
```