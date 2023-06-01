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
│   ├── create.sh # Create an index using default Datashare settings
│   ├── delete.sh # Delete an index
│   ├── list.sh # List all indices
│   └── replace.sh # Replace an index by another one
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

**3. While the reindex is being done, watch progress using the task id from the last command:**

```
./task/watch.sh 8UnTR-67T8y0idkyndf77Q:36041259
```

**4. The document moved to `miso-tmp` use the wrong path so we update it as well:**

```
./document/move.sh miso-tmp /disk/kimchi/tofu /disk/miso/tofu
```

**5. Finally, after checking everything is fine, we substitue the `miso` index by `miso-tmp`:**

```
./index/replace.sh miso-tmp miso
```

### Re-index an index

This opperation might be useful if mapping or settings of the index changed. 


**1. Create a `ricecake-tmp` empty index:**

```
./index/create.sh ricecake-tmp
```

**2. Reindex all documents (under "/" path) from `ricecake` under to `ricecake-tmp`:**

```
./index/reindex.sh ricecake ricecake-tmp /
```

**3. Replace the old `ricecake` by the new one:**

```
./index/replace.sh ricecake-tmp ricecake
```