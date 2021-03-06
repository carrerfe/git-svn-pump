# git-svn-pump

Automatic GIT to SVN synchronization tool

Features
--------
- Commit-by-commit push from Git to Svn
- Traceability
  - Creates a git tag for each svn commit, containing the associated svn revision number
  - Appends the original git commit id to every svn commit message
- Creates a distinct svn branch for each git branch
- Allows filtering git branches by convention (branch name prefix or RegExp)
- Idempotent: can be run at any time manually or as a cron job, it will resume from where it left off
- Proxy support for SVN

Notes and Limitations
---------------------
Git branches intended to be pumped to SVN should have a linear history (no history rewrites).

The other git branches can be rebased and rewritten freely. They can be freely merged into "pumped" branches as well.

Prerequisites
-------------
- Bash
- git v1.7.2 or later
- svn client
