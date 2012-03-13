This is a tool for making tar.gz archives for a list of projects under
version control.

The input is a list of pairs (package name, repository URL).
A tarball is created for each tag within each repository.
Only tags starting with a `v` and a digit are considered; the version 
ID is everything that follows after the `v`.
