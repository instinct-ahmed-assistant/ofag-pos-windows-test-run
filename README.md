# POS l163 native Windows probe

Manual workflow only (workflow_dispatch). Runs the TRIAL build of a pharmacy POS on a GitHub-hosted Windows runner against a synthetic database it creates itself. No customer data, no secrets, no payment. Screenshots and logs are uploaded as a one-day artifact.

Contents: the TRIAL candidate zip (pinned by sha256 in the workflow pre-flight and in the driver), the UI-automation driver scripts, the seed and snapshot helper exes (sha256-pinned by the driver), and synthetic import fixtures. No application source is in this repository.
