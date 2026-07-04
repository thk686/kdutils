# kdutils

Command line utilities for partitioning and searching large tabular files.

## `kdsplit`

`bin/kdsplit` recursively splits a delimited file into a kd-order directory
tree. It hard depends on GNU `sort` and GNU `split`; on macOS it will use
`gsort` and `gsplit` when those are installed by a coreutils package.

Example:

```bash
bin/kdsplit -t $'\t' --header -k 1,1 -k 2,2 -k 3,3 --max-depth 4 --min-rows 1024 --parallel-depth 1 table.tsv
```

Key definitions use GNU `sort -k` syntax and can include GNU sort's field,
character, and ordering modifiers. Extra GNU sort switches are passed through
unchanged, except `-o`/`--output`, which `kdsplit` reserves for its node-local
temporary output files. Use `-O` or `--output-dir` for the root directory.
Pass `--stable` explicitly if you want GNU sort's stable key-only behavior.

Top-level runs refuse to write into a non-empty output directory so old branches
are not accidentally mixed with a new partitioning run.

Use `--header` when the input has a header row. The header is stored as
`TREE/header` and excluded from all node `data` files. Header removal is
streamed into the root sort; `kdsplit` does not materialize a full headerless
copy of the input.

By default, only the root split runs its two children concurrently. Use
`--parallel-depth 0` for fully serial recursion, or a larger value to allow
parallel fan-out for more split levels.

At each node, the current file is sorted lexicographically by the active key
order. The sorted file is split into two line-balanced halves with GNU `split`.
The split key is the first active key, and the branch boundary is the value in
that key from the first row of the right half. Child directories use neutral
left/right names because GNU sort modifiers such as numeric or reverse ordering
change the ordering semantics:

```text
k<field>_left_<median>/
k<field>_right_<median>/
```

After every split, the key definition order is rotated for the children. For
example, `-k 1,1 -k 2,2 -k 3,3` becomes `-k 2,2 -k 3,3 -k 1,1`,
then `-k 3,3 -k 1,1 -k 2,2`, then back to the original order.

Each tree node contains:

- `sort.keys`: the key order used at that node.
- `split.meta`: split metadata, or the leaf stop reason.

Only leaf nodes retain `data` files. Internal node data is removed immediately
after it has been split into child partitions, so the persistent tree stores one
copy of each input row rather than one copy per level. During a split, GNU sort
and GNU split still need temporary working space for the partition currently
being processed. Child partitions are sorted in place before being split, while
the root input file is never overwritten.

The input is treated as raw delimited records with no CSV quoting.

A future `kdmerge` utility could traverse this tree depth-first and concatenate
the node files back into kd-order, except for the lowest leaves where records
remain in the final leaf-local sort order.

## `kdsearch`

`bin/kdsearch` searches a `kdsplit` tree with inclusive field ranges:

```bash
bin/kdsearch -t, --header --range 2:6:8 --range 14:LAX:LAX flights
```

Ranges use `FIELD:LOW:HIGH`; leave `LOW` or `HIGH` empty for an open bound.
`kdsearch` prunes tree branches when it can do so safely from the split metadata
and scans leaf files for exact filtering. It is conservative around duplicate
split-boundary values and unsupported sort modifiers, so query results should
match a direct scan even when pruning is limited.

## Benchmarks

Run the flights benchmark with:

```bash
scripts/benchmark_flights.sh data/flights.csv
```

The benchmark builds a `kdsplit` tree with `--header`, times several `kdsearch`
queries against direct `awk` scans, and writes results under `benchmarks/<UTC
timestamp>/`.

On the bundled `data/flights.csv` test data, one run produced:

```text
build                       5.28s
kdsearch summer_lax         0.64s  4122 rows
awk summer_lax              0.71s  4122 rows
kdsearch january            0.51s  36020 rows
awk january                 0.69s  36020 rows
kdsearch midmonth           1.15s  159309 rows
awk midmonth                0.73s  159309 rows
kdsearch summer_lax_midmonth 0.49s 1480 rows
awk summer_lax_midmonth      0.69s 1480 rows
```
