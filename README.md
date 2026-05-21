# SPACE312 Final Project

GTO-to-GEO transfer trajectory optimization for the GEO-KOMPSAT-2A target state.
The submitted workflow is based on course concepts: two-body propagation,
Lambert transfer, impulsive Delta V, ECI/ECEF/SEZ visibility, and Pareto
tradeoff evaluation.

## Final design choice

The project uses the target GEO state vector given in the project PDF Section 3.2.
After defining the mission priority as a balanced design between propellant saving
and short transfer duration, the representative solution is selected from the
Pareto front near the knee point:

- Transfer duration: 1.2000 days
- Delta V1: 2.054971 km/s
- Delta V2: 0.543456 km/s
- Total Delta V: 2.598428 km/s

Main files:

- `SPACE312_Final_Project_Main.m`: MATLAB optimization and plotting script
- `SPACE312_Final_Project_Report_KR_final.docx`: final Korean report
- `results/FinalProject_ReportSolutions.csv`: representative Pareto solutions
- `results/balanced_knee/`: selected design point figures and summary
