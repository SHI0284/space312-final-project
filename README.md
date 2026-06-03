# SPACE312 Final Project

## GTO-to-GEO Transfer Trajectory Optimization for GEO-KOMPSAT-2A

This project investigates an optimized impulsive transfer trajectory from an initial Geostationary Transfer Orbit (GTO) to the GEO-KOMPSAT-2A target GEO state using Earth-centered two-body dynamics.

The workflow combines:

* orbital propagation
* Lambert transfer trajectory generation
* rendezvous analysis
* visibility analysis
* Pareto tradeoff evaluation

to identify practical transfer solutions for GEO mission operations.

The project is based on the following SPACE312 concepts:

* Two-body orbital propagation
* Lambert transfer trajectory design
* Multi-revolution Lambert solutions
* Impulsive maneuver modeling
* ECI / ECEF / SEZ coordinate transformation
* GEO rendezvous analysis
* Ground visibility analysis
* Pareto-optimal transfer selection

---

# Mission Overview

The mission objective is to transfer a spacecraft from the given GTO initial condition to the GEO-KOMPSAT-2A target state while minimizing total impulsive Delta V and maintaining a realistic transfer duration.

Unlike a simple GEO insertion problem, this project treats the target GEO spacecraft as a moving rendezvous target.

The target spacecraft state vector provided in Section 3.2 of the project PDF is used as the authoritative rendezvous boundary condition.

Both the transfer spacecraft and the target GEO spacecraft are propagated using the same Earth-centered two-body dynamics model throughout the transfer duration.

Transfer search range:

* `1 day <= transfer duration <= 30 days`

The final submitted design point prioritizes:

1. Completion of rendezvous within a practical early-orbit operations window
2. Minimization of total impulsive Delta V inside that operational constraint
3. Stable rendezvous convergence and realistic mission feasibility

Selected representative solution:

| Parameter            | Value           |
| -------------------- | --------------- |
| Selected Method      | MultiRevLambert |
| Direction            | Prograde        |
| Revolution Count     | M = 3           |
| Transfer Duration    | 3.4709 days     |
| Delta V1             | 1.6784 km/s     |
| Delta V2             | 0.1616 km/s     |
| Total Delta V        | 1.8400 km/s     |
| Final Position Error | 0.000137 km     |

This design point provides a balanced tradeoff between transfer duration and fuel efficiency while remaining inside a realistic GEO commissioning timeline.

---

# Dynamics Model

The project uses Earth-centered inertial (ECI) two-body dynamics:

```text id="jp8gdr"
a = -mu * r / |r|^3
```

where:

* `mu = 398600.4418 km^3/s^2`
* `r = spacecraft position vector`

The following perturbations are intentionally excluded:

* J2 perturbation
* Atmospheric drag
* Solar radiation pressure
* Third-body gravity

This matches the assumptions specified in the project handout.

---

# Optimization Workflow

The MATLAB workflow performs the following steps:

1. Propagate the target GEO spacecraft for each transfer duration candidate
2. Generate Lambert transfer trajectories
3. Evaluate impulsive maneuver costs
4. Compute final rendezvous position and velocity errors
5. Apply Pareto filtering
6. Select the representative design point based on mission priority

Both zero-revolution and multi-revolution Lambert solutions are considered.

Impulsive maneuver costs are computed as:

```text id="k1zzlg"
Delta V1 = ||V_departure - V_GTO_initial||
```

```text id="2xgwj6"
Delta V2 = ||V_target_final - V_arrival||
```

```text id="7m8a6o"
Total Delta V = Delta V1 + Delta V2
```

Only trajectories satisfying the rendezvous error tolerance are retained as valid candidates.

---

# Repository Structure

```text id="ylrj3j"
SPACE312_Final_Project/
│
├── SPACE312_Final_Project_Main.m
├── SPACE312_Final_Project_Report_KR_final.docx
├── README.md
│
├── results/
│   ├── FinalProject_ReportSolutions.csv
│   ├── balanced_knee/
│   ├── pareto_front/
│   ├── trajectory_figures/
│   ├── visibility/
│   └── animations/
│
└── functions/
    ├── Lambert solver
    ├── Two-body propagator
    ├── Coordinate transforms
    ├── Visibility analysis
    └── Plot utilities
```

---

# Output Figures

The MATLAB workflow automatically generates:

* Pareto front plots
* 3D transfer trajectory figures
* Radius history plots
* Maneuver magnitude plots
* Final position error plots
* KHU visibility interval figures
* Rendezvous animation GIFs

Generated figures and CSV files are stored in the `results/` directory.

---

# How to Run

Run the main MATLAB script:

```matlab id="kq7m0j"
SPACE312_Final_Project_Main
```

The script will:

* regenerate all transfer candidates
* perform Pareto filtering
* print the selected solution
* export CSV result tables
* generate plots and animations

The selected design point is saved to:

```text id="0jv8h4"
results/FinalProject_ReportSolutions.csv
```

---

# Key Project Features

* Moving GEO target rendezvous interpretation
* Multi-revolution Lambert trajectory search
* Practical mission-priority-based solution selection
* Pareto tradeoff analysis
* Automated MATLAB post-processing
* ECI/ECEF/SEZ visibility analysis
* Transfer animation generation

---

# References

1. Howard D. Curtis, *Orbital Mechanics for Engineering Students*, 4th Edition, Elsevier, 2020.

2. David A. Vallado, *Fundamentals of Astrodynamics and Applications*, 5th Edition, Microcosm Press, 2021.
