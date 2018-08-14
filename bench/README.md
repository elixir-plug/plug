# Plug Benchmarks

Plug has a benchmark suite to track performance of sensitive operations. Benchmarks
are run using the [Benchee](https://github.com/PragTob/benchee) library.

To run the benchmarks tests just type in the console:

```
# POSIX-compatible shells
$ BENCHMARKS_OUTPUT_PATH=bench/results MIX_ENV=bench mix run bench/bench_helper.exs
```

```
# other shells
$ env BENCHMARKS_OUTPUT_PATH=bench/results MIX_ENV=bench mix run bench/bench_helper.exs
```

Plug benchmarks will (soon) be automatically run by the [ElixirBench](https://elixirbench.org)
service.
