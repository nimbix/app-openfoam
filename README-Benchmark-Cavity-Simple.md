# Benchmark Cavity Simple

## Overview

### Summery
Cavity Simple is a benchmark that utilizes the SIMPLE algorithm
for incompressible steady-state flow. The problem consists of a 3d
cube divided equally in each cardinal direction with all faces as
walls except the top. The top is open to air moving at 1 m/s in
the x-direction. The benchmark then runs this simulation for 30
steps and outputs the solver score (1). The number of cells is
semi controlled by the end user where they select a target number
of cells. The benchmark will then round that number up to the
nearest perfect cube.

### Boundary/Initial Conditions

* Velocity
    * Top - (1, 0, 0) m/s
    * Walls - No Slip
    * IC - (0, 0, 0) m/s
* Pressure (2)
    * Top - Zero Gradient
    * Walls - Zero Gradient
    * IC - 0 m2/s2

## Benchmark

The benchmark consists of calculating the solver score on two
systems consisting of 2 nodes of n10-us-02 (192 cores using EFA)
and 4 nodes of Spartan (128 cores using Infiniband). Each system
solved the same problem with 18,191,447 cells.

## Results

| Machine Type | Run Time (Sec) | Solver Score
|:------------:|:--------------:|:----------:|
| n10-us-02    |         74.595 |       1159 |
| Spartan      |         43.755 |       1975 |

## Notes

```text
(1) Solver score is calculated by taking the number of seconds in
    a day and dividing it by the amount of time the simulation
    took to run. Essentially telling the user how many simulations
    they could do in a day.

(2) This is pseudo pressure as OpenFOAM defines steady-state
    pressure as p/rho where rho is the density of the fluid. For
    steady-state solutions, pressure is used as a reference and
    normally means the change from standard pressure (0). From this
    you will see negative pressure.
```
