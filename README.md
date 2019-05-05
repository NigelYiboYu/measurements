## Renaissance Benchmark Suite

<p align="center"><img height="180px" src="https://github.com/D-iii-S/renaissance-benchmarks/raw/master/website/resources/images/mona-lisa-round.png"/></p>

The Renaissance Benchmark Suite is an open source collaborative benchmark project where the community can propose and improve benchmark workloads.
This repository serves to track the performance of the suite on multiple JVM implementations,
currently the performance of initial benchmark release is presented.

Please note that performance measurements depend on many complex factors and therefore YMMV.
**The results given here serve only as examples, you should always collect your own measurements.**
(But do let us know if your results are significantly different from the results given here so that we can look.)

### Measurement information

The current measurements were collected with Renaissance `3284185` on multiple
8 core Intel Xeon E5-2620 v4 machines at 2100 GHz with 64 GB RAM,
running bare metal Fedora Linux 27 with kernel 4.13.9.

Each benchmark was run multiple times, each run was executed in a new JVM instance and terminated after 10 minutes.
The durations of all repetitions were collected and are included in the data,
but only the second half of each run is used in the plots as warm data.

As a shared setting, the JVM implementations were executed with the `-Xms12G -Xmx12G` command line options,
which serve to fix the heap size and reduce variability due to heap sizing.
Except as noted below, other settings were left at default values.

### Measurement results

The JVM implementations referenced in the results are:

- **GraalCE JDK 8** is Graal Community Edition 1.0.0-rc16.
```
> java -version
openjdk version "1.8.0_202"
OpenJDK Runtime Environment (build 1.8.0_202-20190206132807.buildslave.jdk8u-src-tar--b08)
OpenJDK GraalVM CE 1.0.0-rc16 (build 25.202-b08-jvmci-0.59, mixed mode)
```

- **GraalEE JDK 8** is Graal Enterprise Edition 1.0.0-rc16.
```
> java -version
java version "1.8.0_202"
Java(TM) SE Runtime Environment (build 1.8.0_202-b08)
Java HotSpot(TM) GraalVM EE 1.0.0-rc16 (build 25.202-b08-jvmci-0.59, mixed mode)
```

- **HotSpot JDK 8 JVMCI** is the Graal Enterprise Edition JVM implementation run with `-XX:-EnableJVMCI -XX:-UseJVMCICompiler`.

- **OpenJ9 JDK 8** is the Eclipse OpenJ9 JVM implementation.
```
java -version
openjdk version "1.8.0_212"
OpenJDK Runtime Environment (build 1.8.0_212-b03)
Eclipse OpenJ9 VM (build openj9-0.14.0, JRE 1.8.0 Linux amd64-64-Bit Compressed References 20190417_286 (JIT enabled, AOT enabled)
OpenJ9   - bad1d4d06
OMR      - 4a4278e6
JCL      - 5590c4f818 based on jdk8u212-b03)
```

- **OpenJDK JDK 8 JVMCI** is the Graal Community Edition JVM implementation run with `-XX:-EnableJVMCI -XX:-UseJVMCICompiler`.

#### Mean Repetition Times

The figure shows the mean repetition time for each benchmark, computed as the average duration of all warm repetitions.
The error bars show 99% confidence intervals for the mean computed using bootstrap.

<p align="center"><img src="https://github.com/D-iii-S/renaissance-measurements/raw/master/overview-mean.png"/></p>

#### Individual Repetition Times

The figure shows the individual repetition times for each benchmark in a violin plot.
The violin shape is the widest at the height of the most frequent repetition times,
the box inside the shape stretches from the low to the high quartile,
with a mark at the median.
Outlier filtering was used to discard no more than 10% of most extreme observations, to preserve plot scale.

<p align="center"><img src="https://github.com/D-iii-S/renaissance-measurements/raw/master/overview-violin.png"/></p>
