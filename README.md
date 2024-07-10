# Datashare Playground [![](https://img.shields.io/github/actions/workflow/status/icij/datashare-playground/main.yml)](https://github.com/ICIJ/datashare-playground/actions)

![Datashare: Better analyze information, in all its forms](https://i.imgur.com/9SPU1x2.png)

<p align="center">
A zero-dependencies series of bash scripts to interact with Datashare's index and queue.<br />
<a href="#setup">Setup</a> | <a href="#scripts">Scripts</a> | <a href="#test">Test</a> | <a href="#cookbook">Cookbook</a>
</p>

## Setup

To run those scripts only needs to have access to the ElasticSearch URL which must be stored in an 
environement variable called `ELASTICSEARCH_URL`. Same logic applies to `REDIS_URL`. To avoid setting up 
this variable everytime you use those script, you can store in a `.env` at the root of this directory:

```bash
ELASTICSEARCH_URL=http://localhost:9200
REDIS_URL=redis://redis
```

## Scripts

Here are the main scripts available in this repository:

```bash
.
├── elasticsearch
│   │
│   ├── document
│   │   ├── count.sh # Count documents under a given path
│   │   ├── delete.sh # Delete documents under a given path
│   │   ├── move.sh # Move documents from a directory to another
│   │   └── reindex.sh # Reindex documents from a given index and under a specific directory
│   │
│   ├── duplicate
│   │   ├── count.sh # Count duplicates
│   │   └── reindex.sh # Reindex duplicates from a given index
│   │
│   ├── index
│   │   ├── clone.sh # Clone a given index into another
│   │   ├── create.sh # Create an index using default Datashare settings
│   │   ├── delete.sh # Delete an index
│   │   ├── list.sh # Get all indices
│   │   ├── number_of_replicas.sh # Get or change number of replicas for a given index
│   │   ├── refresh_interval.sh # Get or change refresh interval for a given index
│   │   ├── refresh.sh # Refresh a given index
│   │   ├── reindex.sh # Reindex everything from a given index
│   │   └── replace.sh # Replace an index by another one
│   │
│   ├── named_entity
│   │   ├── count.sh # Count named entities
│   │   └── reindex.sh # Reindex named entities from a given index
│   │
│   └── task
│       ├── cancel.sh # Cancel a given task
│       ├── get.sh # Get a given task status
│       ├── list.sh # Get all tasks
│       └── watch.sh # Watch a given task status
│
├── redis
│   │
│   ├── queue
│   │   └── rpush.sh # Insert stdin rows to a given queue
│   │
│   └── report
│       ├── hdel.sh # Remove stdin rows from a given report map
│       └── hset.sh # Insert stdin rows to a given report map
│
└── lib
    └── sync.sh # Sync this directory with another location with rsync
```

## Test 

Developpers can run tests using [bats](https://github.com/bats-core/bats-core):

```bash
export ELASTICSEARCH_URL=http://localhost:9200 # Change this with the URL of ElasticSearch 
make tests
```

## Cookbook

This cookbook list real-life examples of how to use those scripts.

### Copy documents from a given index to another

An example showing how to copy documents from the `kimchi` index to the `miso` while taking care of updating the path.

**1. Create a clone of the "miso" index to avoid messing up with data:**

```bash
./elasticsearch/index/clone.sh miso miso-tmp
```

**2. Reindex documents from `kimchi` under the folder `/disk/kimchi/tofu` onto `miso-tmp`:**

```bash
./elasticsearch/index/reindex.sh kimchi miso-tmp /disk/kimchi/tofu
```

**3. While the reindex is being done, watch progress using the task id from the last command:**

```bash
./elasticsearch/task/watch.sh 8UnTR-67T8y0idkyndf77Q:36041259
```

**4. The document moved to `miso-tmp` use the wrong path so we update it as well:**

```bash
./elasticsearch/document/move.sh miso-tmp /disk/kimchi/tofu /disk/miso/tofu
```

**5. Finally, after checking everything is fine, we substitue the `miso` index by `miso-tmp`:**

```bash
./elasticsearch/index/replace.sh miso-tmp miso
```

### Re-index an index

This opperation might be useful if mapping or settings of the index changed. 


**1. Create a `ricecake-tmp` empty index:**

```bash
./elasticsearch/index/create.sh ricecake-tmp
```

**1'. Alternatively, you can create a `ricecake-tmp` empty index with the mappings/settings of the desired version:**

```bash
./elasticsearch/index/create.sh ricecake-tmp 17.1.1
```

**2. Reindex all documents (under "/" path) from `ricecake` under to `ricecake-tmp`:**

```bash
./elasticsearch/documents/reindex.sh ricecake ricecake-tmp /
```

**3. Replace the old `ricecake` by the new one:**

```bash
./elasticsearch/index/replace.sh ricecake-tmp ricecake
```

### Queue files (for indexing)

This will get files from `find` and store them in the `extract:queue` list:

```bash
find /home/foo/bar -type f | ./redis/queue/rpush.sh extract:queue
```

Or to filtered that list with a `filtered.txt` file:

```bash
find ~+ -type f | grep -vFf filtered.txt | ./redis/queue/rpush.sh extract:queue
```

This can also be done with a single file:

```bash
echo "/file/to/index.pdf" | ./redis/queue/rpush.sh extract:report
```

### Add files to a report map

Report map are used to store error and skip already indexed files.

```bash
find /home/foo/bar -type f | ./redis/report/hset.sh extract:report
```
### Delete files from a report map

This can be usefull to force a reindex on certain files:

```bash
cat to-reindex.txt | ./redis/report/hdel.sh extract:report
```

This can also be done with a single file:

```bash
echo "/file/to/reindex.pdf" | ./redis/report/hdel.sh extract:report
```