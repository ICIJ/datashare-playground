<p align="center">
<a href="https://datashare.icij.org/">
  <img src="https://datashare.icij.org/android-chrome-512x512.png" width="158px">
</a>
</p>
<h1 align="center">Datashare Playground</h1>

A series of bash utilities to perform common operations on Datashare documents stored in ElasticSearch.

## Scripts

```bash
.
├── document
│   ├── count.sh # Count documents on under a given path
│   ├── move.sh # Move documents from a directory to another
│   └── reindex.sh # Reindex files from index under a specific directory
├── index
│   ├── clone.sh # Close a given index into another
│   └── list.sh # List all indices
├── lib
│   └── sync.sh # Sync this directory with another location with rsync
└── task
    ├── cancel.sh # Cancel a given task
    ├── get.sh # Get a given task status
    └── watch.sh # Watch a given task status
```
