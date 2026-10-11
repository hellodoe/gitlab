# Deployment Pipeline

Glossary for deploying a Python backend + React frontend from the on-prem GitLab to a non-production Linux host.

## Language

**Test server**:
The single non-production Linux host the project is deployed to, running Apache. Always called "test"; never "staging", "dev" or "non-production".

**Release**:
One timestamped folder on the **Test server** holding the backend source and the built frontend from a single **Deploy job** run. A `current` link points at the live Release; the last 5 are kept so a previous one can be re-pointed to.

**Deploy job**:
The pipeline job that ships the project's source files to the **Test server**. Runs automatically for `main`, and as a manual click-to-deploy for every other branch.
