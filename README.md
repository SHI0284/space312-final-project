# SPACE312 Final Project

GTO-to-GEO transfer trajectory optimization for the GEO-KOMPSAT-2A target state.
The submitted workflow is based on course concepts: two-body propagation,
Lambert transfer, impulsive Delta V, ECI/ECEF/SEZ visibility, and Pareto
tradeoff evaluation.

## Final design choice

The project uses the target GEO state vector given in the project PDF Section 3.2.
Following the instructor clarification, the submitted workflow uses the target
GEO state vector from Section 3.2 as the authoritative rendezvous boundary
condition. The mission priority is defined before selecting the submitted design
point: complete rendezvous inside a practical four-day early-orbit operations
window, then minimize total impulsive Delta V inside that window. This treats
propellant as the limiting mission resource once the transfer duration remains
short enough for realistic commissioning and ground operations. The full
1-to-30-day sweep is still retained for the Pareto trade study.

Run `SPACE312_Final_Project_Main.m` to regenerate the final CSV files and plots.
The selected design point is printed in the MATLAB command window and written to
`results/FinalProject_ReportSolutions.csv`.

Main files:

- `SPACE312_Final_Project_Main.m`: MATLAB optimization and plotting script
- `SPACE312_Final_Project_Report_KR_final.docx`: final Korean report
- `results/FinalProject_ReportSolutions.csv`: representative Pareto solutions
- `results/balanced_knee/`: selected design point figures and summary
